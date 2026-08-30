import XCTest
@testable import Nile

@MainActor
final class SessionRenameRuntimeTests: XCTestCase {
    func testRenameTrimsAndPublishesOnlyCurrentOwner() async {
        let repository = ImmediateRenameRepository()
        let runtime = SessionRenameRuntime(repository: repository)
        let owner = renameOwner()
        let capture = RenameCapture()

        runtime.setDialogVisible(true, owner: owner)
        runtime.rename(
            "  Release notes  ",
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onRenamed: { title, owner in
                capture.values.append((title, owner))
            }
        )

        await eventually { !runtime.isRenaming }
        let renameCalls = await repository.renameCalls
        XCTAssertEqual(renameCalls, ["live-one:Release notes"])
        XCTAssertEqual(capture.values.map(\.0), ["Release notes"])
        XCTAssertEqual(capture.values.map(\.1), [owner])
        XCTAssertFalse(runtime.isDialogVisible)
        XCTAssertNil(runtime.error)
    }

    func testResetInvalidatesLateRenameCompletion() async {
        let repository = BlockingRenameRepository()
        let runtime = SessionRenameRuntime(repository: repository)
        let owner = renameOwner()
        let capture = RenameCapture()

        runtime.setDialogVisible(true, owner: owner)
        runtime.rename(
            "Stale title",
            owner: owner,
            isCurrentOwner: { $0 == owner },
            onRenamed: { title, owner in
                capture.values.append((title, owner))
            }
        )
        await eventuallyAsync { await repository.renameStarted }

        runtime.reset()
        await repository.releaseRename()
        await Task.yield()

        XCTAssertTrue(capture.values.isEmpty)
        XCTAssertFalse(runtime.isRenaming)
        XCTAssertFalse(runtime.isDialogVisible)
    }

    private func renameOwner() -> SessionRenameRuntime.Owner {
        SessionRenameRuntime.Owner(
            gatewayGeneration: 1,
            gatewayID: "gateway-one",
            storedSessionID: "one",
            liveSessionID: "live-one"
        )
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }

    private func eventuallyAsync(
        _ condition: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<200 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
    }
}

@MainActor
private final class RenameCapture {
    var values: [(String, SessionRenameRuntime.Owner)] = []
}

private actor ImmediateRenameRepository: HermesSessionRenaming {
    private(set) var renameCalls: [String] = []

    func renameSession(liveSessionID: String, title: String) async throws {
        renameCalls.append("\(liveSessionID):\(title)")
    }
}

private actor BlockingRenameRepository: HermesSessionRenaming {
    private(set) var renameStarted = false
    private var renameContinuation: CheckedContinuation<Void, Never>?

    func renameSession(liveSessionID: String, title: String) async throws {
        renameStarted = true
        await withCheckedContinuation { continuation in
            renameContinuation = continuation
        }
    }

    func releaseRename() {
        renameContinuation?.resume()
        renameContinuation = nil
    }
}
