import XCTest
@testable import Nile

final class ModelPinStoreTests: XCTestCase {
    func testProviderPinsRoundTripAndStayGatewayScoped() async throws {
        let fixture = try TemporaryModelPinStore()
        let store = ProtectedModelPinStore(fileURL: fixture.fileURL)
        let google = ModelPin(
            providerSlug: "google",
            modelID: "gemini-pro"
        )
        let openAI = ModelPin(
            providerSlug: "openai",
            modelID: "gpt-5"
        )

        let first = try await store.toggle(
            gatewayID: "gateway-a",
            pin: google
        )
        let second = try await store.toggle(
            gatewayID: "gateway-a",
            pin: openAI
        )
        let other = try await store.toggle(
            gatewayID: "gateway-b",
            pin: google
        )

        XCTAssertEqual(first, [google])
        XCTAssertEqual(second, [google, openAI])
        XCTAssertEqual(other, [google])
        let relaunched = ProtectedModelPinStore(fileURL: fixture.fileURL)
        let restoredA = try await relaunched.load(gatewayID: "gateway-a")
        let restoredB = try await relaunched.load(gatewayID: "gateway-b")
        XCTAssertEqual(restoredA, [google, openAI])
        XCTAssertEqual(restoredB, [google])
    }

    func testProviderToggleMigratesAndRemovesLegacyAlias() async throws {
        let fixture = try TemporaryModelPinStore()
        try Data(
            """
            {"gateways":[{"gatewayID":"gateway","pins":[{"modelID":"shared"}]}],"version":1}
            """.utf8
        ).write(to: fixture.fileURL)
        let store = ProtectedModelPinStore(fileURL: fixture.fileURL)
        let exact = ModelPin(
            providerSlug: "openai",
            modelID: "shared"
        )

        let removed = try await store.toggle(
            gatewayID: "gateway",
            pin: exact
        )
        XCTAssertTrue(removed.isEmpty)

        let inserted = try await store.toggle(
            gatewayID: "gateway",
            pin: exact
        )
        XCTAssertEqual(inserted, [exact])
        XCTAssertFalse(
            inserted.contains(
                ModelPin(providerSlug: nil, modelID: "shared")
            )
        )
    }

    func testProtectedFileIsBackupExcludedAndRemovalBlocksLateRewrite() async throws {
        let fixture = try TemporaryModelPinStore()
        let store = ProtectedModelPinStore(fileURL: fixture.fileURL)
        let pin = ModelPin(providerSlug: "openai", modelID: "gpt-5")
        _ = try await store.toggle(gatewayID: "gateway", pin: pin)

        let values = try fixture.directory.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(values.isExcludedFromBackup, true)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fixture.fileURL.path
        )
#if targetEnvironment(simulator)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(
                protection,
                .completeUntilFirstUserAuthentication
            )
        }
#else
        XCTAssertEqual(
            attributes[.protectionKey] as? FileProtectionType,
            .completeUntilFirstUserAuthentication
        )
#endif

        try await store.removeGateway(id: "gateway")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.fileURL.path)
        )
        let late = try await store.toggle(gatewayID: "gateway", pin: pin)
        XCTAssertEqual(late, [])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.fileURL.path)
        )
    }

    func testMalformedDuplicateAndUnsupportedEnvelopesFailClosed() async throws {
        let fixture = try TemporaryModelPinStore()
        try Data(
            """
            {"gateways":[{"gatewayID":"gateway","pins":[{"modelID":"gpt-5"},{"modelID":"gpt-5"}]}],"version":1}
            """.utf8
        ).write(to: fixture.fileURL)
        var store = ProtectedModelPinStore(fileURL: fixture.fileURL)
        do {
            _ = try await store.load(gatewayID: "gateway")
            XCTFail("Expected duplicate pins to fail closed")
        } catch let error as ModelPinStoreError {
            XCTAssertEqual(error, .malformedData)
        }

        try Data(#"{"gateways":[],"version":9}"#.utf8).write(
            to: fixture.fileURL,
            options: .atomic
        )
        store = ProtectedModelPinStore(fileURL: fixture.fileURL)
        do {
            _ = try await store.load(gatewayID: "gateway")
            XCTFail("Expected unsupported data to fail closed")
        } catch let error as ModelPinStoreError {
            XCTAssertEqual(error, .unsupportedVersion(9))
        }
    }
}

private final class TemporaryModelPinStore: @unchecked Sendable {
    let directory: URL
    let fileURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "nile-model-pin-test-\(UUID())",
            directoryHint: .isDirectory
        )
        fileURL = directory.appending(
            path: "model-pins.json",
            directoryHint: .notDirectory
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
