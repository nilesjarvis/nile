import XCTest
@testable import Nile

final class SessionPinStoreTests: XCTestCase {
    func testPinsRoundTripAndStayGatewayScoped() async throws {
        let fixture = try TemporarySessionPinStore()
        let store = ProtectedSessionPinStore(fileURL: fixture.fileURL)

        try await store.setPinned(
            gatewayID: "gateway-a",
            sessionID: "session-two",
            pinned: true
        )
        try await store.setPinned(
            gatewayID: "gateway-a",
            sessionID: "session-one",
            pinned: true
        )
        try await store.setPinned(
            gatewayID: "gateway-b",
            sessionID: "session-one",
            pinned: true
        )
        try await store.setPinned(
            gatewayID: "gateway-a",
            sessionID: "session-two",
            pinned: false
        )

        let relaunched = ProtectedSessionPinStore(fileURL: fixture.fileURL)
        let restoredA = try await relaunched.load(gatewayID: "gateway-a")
        let restoredB = try await relaunched.load(gatewayID: "gateway-b")
        XCTAssertEqual(restoredA, ["session-one"])
        XCTAssertEqual(restoredB, ["session-one"])
    }

    func testProtectedFileIsBackupExcludedAndRemovalBlocksLateRewrite()
        async throws
    {
        let fixture = try TemporarySessionPinStore()
        let store = ProtectedSessionPinStore(fileURL: fixture.fileURL)
        try await store.setPinned(
            gatewayID: "gateway",
            sessionID: "session",
            pinned: true
        )

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
        try await store.setPinned(
            gatewayID: "gateway",
            sessionID: "late-session",
            pinned: true
        )
        let pinsAfterRemoval = try await store.load(gatewayID: "gateway")
        XCTAssertTrue(pinsAfterRemoval.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.fileURL.path)
        )
    }

    func testMalformedDuplicateAndUnsupportedEnvelopesFailClosed() async throws {
        let fixture = try TemporarySessionPinStore()
        try Data(
            """
            {"gateways":[{"gatewayID":"gateway","sessionIDs":["same","same"]}],"version":1}
            """.utf8
        ).write(to: fixture.fileURL)
        var store = ProtectedSessionPinStore(fileURL: fixture.fileURL)
        do {
            _ = try await store.load(gatewayID: "gateway")
            XCTFail("Expected duplicate pins to fail closed")
        } catch let error as SessionPinStoreError {
            XCTAssertEqual(error, .malformedData)
        }

        try Data(#"{"gateways":[],"version":9}"#.utf8).write(
            to: fixture.fileURL,
            options: .atomic
        )
        store = ProtectedSessionPinStore(fileURL: fixture.fileURL)
        do {
            _ = try await store.load(gatewayID: "gateway")
            XCTFail("Expected unsupported data to fail closed")
        } catch let error as SessionPinStoreError {
            XCTAssertEqual(error, .unsupportedVersion(9))
        }
    }

    func testInvalidGatewayAndSessionIdentifiersAreRejected() async throws {
        let fixture = try TemporarySessionPinStore()
        let store = ProtectedSessionPinStore(fileURL: fixture.fileURL)

        do {
            try await store.setPinned(
                gatewayID: " gateway",
                sessionID: "session",
                pinned: true
            )
            XCTFail("Expected invalid gateway to fail")
        } catch let error as SessionPinStoreError {
            XCTAssertEqual(error, .invalidGateway)
        }

        do {
            try await store.setPinned(
                gatewayID: "gateway",
                sessionID: "session\nother",
                pinned: true
            )
            XCTFail("Expected invalid session to fail")
        } catch let error as SessionPinStoreError {
            XCTAssertEqual(error, .invalidSession)
        }
    }
}

private final class TemporarySessionPinStore: @unchecked Sendable {
    let directory: URL
    let fileURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "nile-session-pin-test-\(UUID())",
            directoryHint: .isDirectory
        )
        fileURL = directory.appending(
            path: "session-pins.json",
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
