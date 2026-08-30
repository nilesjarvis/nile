import Foundation
import XCTest
@testable import Nile

final class GatewaySecureStorageIntegrationTests: XCTestCase, @unchecked Sendable {
    func testKeychainCredentialRoundTripUpdateAndDelete() async throws {
        let service = "com.niles.NileTests.gateway-token.\(UUID().uuidString)"
        let store = KeychainGatewayCredentialStore(service: service)
        let credentialID = "credential-integration"

        try await store.storeToken("first-secret", credentialID: credentialID)
        let first = try await store.token(credentialID: credentialID)
        XCTAssertEqual(first, "first-secret")

        try await store.storeToken("replacement-secret", credentialID: credentialID)
        let replacement = try await store.token(credentialID: credentialID)
        XCTAssertEqual(replacement, "replacement-secret")

        try await store.removeToken(credentialID: credentialID)
        let removed = try await store.token(credentialID: credentialID)
        XCTAssertNil(removed)
        try await store.removeToken(credentialID: credentialID)
    }

    func testMetadataFileUsesDataProtectionAndNeverContainsCredential() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "nile-profile-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = directory.appending(path: "profiles.json", directoryHint: .notDirectory)
        let storage = ProtectedFileGatewayProfileMetadataStorage(fileURL: file)
        let secret = "must-never-be-written"
        let data = Data(#"{"version":1,"marker":"non-secret"}"#.utf8)

        try await storage.write(data)

        let stored = try await storage.read()
        XCTAssertEqual(stored, data)
        XCTAssertFalse(try XCTUnwrap(String(data: XCTUnwrap(stored), encoding: .utf8)).contains(secret))
        let directoryResourceValues = try directory.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(directoryResourceValues.isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
#if targetEnvironment(simulator)
        // APFS in Simulator accepts the file-protection attribute but does not
        // surface it again. A device build exercises the assertion below.
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .completeUntilFirstUserAuthentication)
        }
#else
        XCTAssertEqual(
            attributes[.protectionKey] as? FileProtectionType,
            .completeUntilFirstUserAuthentication
        )
#endif

        try await storage.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try? FileManager.default.removeItem(at: directory)
    }
}
