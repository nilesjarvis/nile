import Foundation
import XCTest
@testable import Nile

final class GatewayProfileStoreTests: XCTestCase, @unchecked Sendable {
    func testProfilesRoundTripWithSecretsOutsideDeterministicMetadata() async throws {
        let metadata = MemoryProfileMetadata()
        let credentials = MemoryGatewayCredentials()
        let store = SecureGatewayProfileStore(
            metadataStorage: metadata,
            credentialStorage: credentials
        )

        let home = try await store.save(
            connection: GatewayConnection(
                endpoint: try GatewayEndpoint.parse("http://home.local:9119"),
                token: "home-secret",
                cleartextPermission: .approved
            ),
            name: "  Home Pi  "
        )
        let lab = try await store.save(
            connection: GatewayConnection(
                endpoint: try GatewayEndpoint.parse("https://lab.local/hermes"),
                token: "lab-secret"
            ),
            name: nil
        )

        let storedBytes = await metadata.bytes
        let bytes = try XCTUnwrap(storedBytes)
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        XCTAssertFalse(text.contains("home-secret"))
        XCTAssertFalse(text.contains("lab-secret"))
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        )
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["activeGatewayID"] as? String, lab.id)
        XCTAssertEqual(object["pendingCredentialDeletions"] as? [String], [])
        let profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0]["baseURL"] as? String, "http://home.local:9119")
        XCTAssertEqual(profiles[0]["cleartextPermission"] as? String, "approved")
        XCTAssertEqual(profiles[0]["id"] as? String, home.id)
        XCTAssertEqual(profiles[0]["name"] as? String, "Home Pi")
        XCTAssertEqual(profiles[1]["baseURL"] as? String, "https://lab.local/hermes")
        XCTAssertEqual(profiles[1]["cleartextPermission"] as? String, "denied")
        XCTAssertEqual(profiles[1]["id"] as? String, lab.id)
        XCTAssertEqual(profiles[1]["name"] as? String, "lab.local/hermes")
        let credentialIDs = profiles.compactMap { $0["credentialID"] as? String }
        XCTAssertEqual(credentialIDs.count, 2)
        XCTAssertEqual(Set(credentialIDs).count, 2)
        XCTAssertTrue(credentialIDs.allSatisfy { $0.hasPrefix("credential-") })

        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.profiles, [home, lab])
        XCTAssertEqual(snapshot.activeProfile, lab)
        let storedTokens = await credentials.storedTokens
        XCTAssertEqual(Set(storedTokens.values), ["home-secret", "lab-secret"])
    }

    func testUpdatingEndpointKeepsIdentityAndLastSessionButReplacesTokenAndPolicy() async throws {
        let metadata = MemoryProfileMetadata()
        let credentials = MemoryGatewayCredentials()
        let store = SecureGatewayProfileStore(
            metadataStorage: metadata,
            credentialStorage: credentials
        )
        let endpoint = try GatewayEndpoint.parse("http://home.local:9119")
        let first = try await store.save(
            connection: GatewayConnection(
                endpoint: endpoint,
                token: "old",
                cleartextPermission: .legacyAllowed
            ),
            name: "Home"
        )
        try await store.saveLastSessionID(
            gatewayID: first.id,
            storedSessionID: "stored-1"
        )

        let updated = try await store.save(
            connection: GatewayConnection(
                endpoint: endpoint,
                token: "new",
                cleartextPermission: .approved
            ),
            name: " "
        )

        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.name, "Home")
        XCTAssertEqual(updated.lastSessionID, "stored-1")
        XCTAssertEqual(updated.cleartextPermission, .approved)
        XCTAssertEqual(updated.token, "new")
        let updatedSnapshot = try await store.load()
        XCTAssertEqual(updatedSnapshot.profiles, [updated])
    }

    func testSelectionAndRemovalFallBackInInsertionOrderAndDeleteCredentials() async throws {
        let metadata = MemoryProfileMetadata()
        let credentials = MemoryGatewayCredentials()
        let store = SecureGatewayProfileStore(
            metadataStorage: metadata,
            credentialStorage: credentials
        )
        let first = try await store.save(
            connection: try GatewayConnection(
                baseURL: "https://first.example",
                token: "first-secret"
            ),
            name: "First"
        )
        let second = try await store.save(
            connection: try GatewayConnection(
                baseURL: "https://second.example",
                token: "second-secret"
            ),
            name: "Second"
        )

        try await store.selectGateway(id: first.id)
        let selectedSnapshot = try await store.load()
        XCTAssertEqual(selectedSnapshot.activeProfile, first)
        try await store.removeGateway(id: first.id)

        let remaining = try await store.load()
        XCTAssertEqual(remaining.profiles, [second])
        XCTAssertEqual(remaining.activeProfile, second)
        let retainedTokens = await credentials.storedTokens
        XCTAssertEqual(Array(retainedTokens.values), ["second-secret"])

        try await store.removeGateway(id: second.id)
        let emptySnapshot = try await store.load()
        let removedMetadata = await metadata.bytes
        XCTAssertEqual(emptySnapshot, GatewayProfileSnapshot(profiles: [], activeProfile: nil))
        XCTAssertNil(removedMetadata)
    }

    func testMissingCredentialAndMalformedMetadataFailClosed() async throws {
        let metadata = MemoryProfileMetadata()
        let credentials = MemoryGatewayCredentials()
        let store = SecureGatewayProfileStore(
            metadataStorage: metadata,
            credentialStorage: credentials
        )
        let profile = try await store.save(
            connection: try GatewayConnection(
                baseURL: "https://gateway.example",
                token: "secret"
            ),
            name: "Gateway"
        )
        await credentials.eraseCredential(containing: "secret")

        do {
            _ = try await store.load()
            XCTFail("Expected missing Keychain item to fail the whole startup load")
        } catch let error as GatewayProfileStoreError {
            XCTAssertEqual(error, .missingCredential(profile.id))
        }

        await metadata.replace(with: Data(#"{"version":1,"profiles":[],"activeGatewayID":"missing"}"#.utf8))
        do {
            _ = try await store.load()
            XCTFail("Expected malformed active selection to fail closed")
        } catch let error as GatewayProfileStoreError {
            XCTAssertEqual(error, .malformedMetadata)
        }
    }

    func testFailedMetadataCommitRestoresPreviousCredential() async throws {
        let metadata = MemoryProfileMetadata()
        let credentials = MemoryGatewayCredentials()
        let store = SecureGatewayProfileStore(
            metadataStorage: metadata,
            credentialStorage: credentials
        )
        let connection = try GatewayConnection(
            baseURL: "https://gateway.example",
            token: "old-secret"
        )
        let first = try await store.save(connection: connection, name: "Old name")
        await metadata.failNextWrite()

        do {
            _ = try await store.save(
                connection: try GatewayConnection(
                    baseURL: connection.baseURL,
                    token: "new-secret"
                ),
                name: "New name"
            )
            XCTFail("Expected injected metadata failure")
        } catch let error as GatewayProfileStoreError {
            XCTAssertEqual(error, .metadataAccess)
        }

        let restoredTokens = await credentials.storedTokens
        let restoredSnapshot = try await store.load()
        XCTAssertEqual(Array(restoredTokens.values), ["old-secret"])
        XCTAssertEqual(restoredSnapshot.profiles, [first])
    }

    func testCommittedCredentialRotationRetriesInterruptedCleanupOnNextLoad() async throws {
        let metadata = MemoryProfileMetadata()
        let credentials = MemoryGatewayCredentials()
        let store = SecureGatewayProfileStore(
            metadataStorage: metadata,
            credentialStorage: credentials
        )
        let first = try await store.save(
            connection: try GatewayConnection(
                baseURL: "https://gateway.example",
                token: "old-secret"
            ),
            name: "Gateway"
        )
        await credentials.failNextRemove()

        let updated = try await store.save(
            connection: try GatewayConnection(
                baseURL: first.normalizedBaseURL,
                token: "new-secret"
            ),
            name: "Gateway"
        )

        XCTAssertEqual(updated.id, first.id)
        let interruptedTokens = await credentials.storedTokens
        XCTAssertEqual(Set(interruptedTokens.values), ["old-secret", "new-secret"])
        let pendingMetadataBytes = await metadata.bytes
        let interruptedBytes = try XCTUnwrap(pendingMetadataBytes)
        let interruptedObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: interruptedBytes) as? [String: Any]
        )
        let pending = try XCTUnwrap(
            interruptedObject["pendingCredentialDeletions"] as? [String]
        )
        XCTAssertEqual(pending.count, 1)
        XCTAssertNotNil(interruptedTokens[pending[0]])

        let recovered = try await store.load()

        XCTAssertEqual(recovered.profiles, [updated])
        let recoveredTokens = await credentials.storedTokens
        XCTAssertEqual(Array(recoveredTokens.values), ["new-secret"])
        let cleanedMetadataBytes = await metadata.bytes
        let recoveredBytes = try XCTUnwrap(cleanedMetadataBytes)
        let recoveredObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: recoveredBytes) as? [String: Any]
        )
        XCTAssertEqual(
            recoveredObject["pendingCredentialDeletions"] as? [String],
            []
        )
    }
}

private actor MemoryProfileMetadata: GatewayProfileMetadataStoring {
    private(set) var bytes: Data?
    private var shouldFailWrite = false

    func read() -> Data? {
        bytes
    }

    func write(_ data: Data) throws {
        if shouldFailWrite {
            shouldFailWrite = false
            throw InjectedStorageError()
        }
        bytes = data
    }

    func remove() {
        bytes = nil
    }

    func replace(with data: Data?) {
        bytes = data
    }

    func failNextWrite() {
        shouldFailWrite = true
    }
}

private actor MemoryGatewayCredentials: GatewayCredentialStoring {
    private var tokens: [String: String] = [:]
    private var shouldFailRemove = false

    var storedTokens: [String: String] {
        tokens
    }

    func token(credentialID: String) -> String? {
        tokens[credentialID]
    }

    func storeToken(_ token: String, credentialID: String) {
        tokens[credentialID] = token
    }

    func removeToken(credentialID: String) throws {
        if shouldFailRemove {
            shouldFailRemove = false
            throw InjectedStorageError()
        }
        tokens.removeValue(forKey: credentialID)
    }

    func eraseCredential(containing token: String) {
        guard let id = tokens.first(where: { $0.value == token })?.key else {
            return
        }
        tokens.removeValue(forKey: id)
    }

    func failNextRemove() {
        shouldFailRemove = true
    }
}

private struct InjectedStorageError: Error {}
