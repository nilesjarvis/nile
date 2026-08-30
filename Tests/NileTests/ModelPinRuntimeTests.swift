import XCTest
@testable import Nile

@MainActor
final class ModelPinRuntimeTests: XCTestCase {
    func testFixtureMutationStaysInMemoryWithoutModelCapability() {
        let runtime = ModelPinRuntime(
            store: nil,
            permitsInMemoryMutation: true
        )
        let pin = ModelPin(providerSlug: "openai", modelID: "gpt-5")
        runtime.installFixture(pins: [], gatewayID: "fixture")
        var errors: [String?] = []

        runtime.toggle(
            owner: owner(generation: 0, gatewayID: "fixture"),
            provider: pin.providerSlug,
            model: pin.modelID,
            onError: { errors.append($0) }
        )

        XCTAssertEqual(runtime.pins, [pin])
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(runtime.canModify(gatewayID: "fixture"))
    }

    func testRestoreAndToggleUseProtectedStoreQueue() async {
        let existing = ModelPin(providerSlug: "one", modelID: "existing")
        let added = ModelPin(providerSlug: "two", modelID: "added")
        let store = SessionModelPinStoreStub(
            pinsByGateway: ["gateway": [existing]]
        )
        let runtime = ModelPinRuntime(
            store: store,
            permitsInMemoryMutation: false
        )
        let owner = owner(generation: 1, gatewayID: "gateway")
        runtime.reset(owner: owner)

        let restoreError = await runtime.restore(owner: owner)
        XCTAssertNil(restoreError)
        XCTAssertEqual(runtime.pins, [existing])
        runtime.toggle(
            owner: owner,
            provider: added.providerSlug,
            model: added.modelID,
            onError: { _ in }
        )
        await waitUntil { runtime.pins == [existing, added] }
        let persisted = await store.pins(gatewayID: "gateway")

        XCTAssertEqual(persisted, [existing, added])
    }

    func testInvalidPinIsRejectedBeforePersistence() async {
        let store = SessionModelPinStoreStub()
        let runtime = ModelPinRuntime(
            store: store,
            permitsInMemoryMutation: false
        )
        let owner = owner(generation: 1, gatewayID: "gateway")
        runtime.reset(owner: owner)
        _ = await runtime.restore(owner: owner)
        var error: String?

        runtime.toggle(
            owner: owner,
            provider: " openai ",
            model: "gpt-5",
            onError: { error = $0 }
        )
        let calls = await store.calls

        XCTAssertEqual(error, "That model pin is invalid.")
        XCTAssertEqual(calls, ["load:gateway"])
    }

    func testLateWriteCannotReplaceNewGatewayPins() async {
        let replacement = ModelPin(
            providerSlug: "openai",
            modelID: "replacement"
        )
        let store = SessionModelPinStoreStub(
            pinsByGateway: ["new": [replacement]],
            blockToggle: true
        )
        let runtime = ModelPinRuntime(
            store: store,
            permitsInMemoryMutation: false
        )
        let oldOwner = owner(generation: 1, gatewayID: "old")
        runtime.reset(owner: oldOwner)
        _ = await runtime.restore(owner: oldOwner)
        runtime.toggle(
            owner: oldOwner,
            provider: "google",
            model: "late",
            onError: { _ in }
        )
        await waitUntilAsync { await store.isToggleWaiting }

        let newOwner = owner(generation: 2, gatewayID: "new")
        runtime.reset(owner: newOwner)
        await store.releaseToggle()
        _ = await runtime.restore(owner: newOwner)
        await Task.yield()

        XCTAssertEqual(runtime.gatewayID, "new")
        XCTAssertEqual(runtime.pins, [replacement])
    }

    private func owner(
        generation: Int,
        gatewayID: String
    ) -> ModelControlGatewayOwner {
        ModelControlGatewayOwner(
            gatewayGeneration: generation,
            gatewayID: gatewayID
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for model-pin runtime state")
    }

    private func waitUntilAsync(
        _ predicate: @escaping @Sendable () async -> Bool
    ) async {
        for _ in 0..<100 {
            if await predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for model-pin store state")
    }
}
