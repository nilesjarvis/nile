import Foundation
@testable import Nile

actor SessionModelPinStoreStub: ModelPinStoring {
    private var pinsByGateway: [String: Set<ModelPin>]
    private let blockToggle: Bool
    private var toggleContinuation: CheckedContinuation<Void, Never>?
    private(set) var calls: [String] = []

    init(
        pinsByGateway: [String: Set<ModelPin>] = [:],
        blockToggle: Bool = false
    ) {
        self.pinsByGateway = pinsByGateway
        self.blockToggle = blockToggle
    }

    var isToggleWaiting: Bool {
        toggleContinuation != nil
    }

    func load(gatewayID: String) -> Set<ModelPin> {
        calls.append("load:\(gatewayID)")
        return pinsByGateway[gatewayID] ?? []
    }

    func toggle(
        gatewayID: String,
        pin: ModelPin
    ) async -> Set<ModelPin> {
        calls.append(
            "toggle:\(gatewayID):\(pin.providerSlug ?? ""):\(pin.modelID)"
        )
        if blockToggle {
            await withCheckedContinuation { continuation in
                toggleContinuation = continuation
            }
        }
        var pins = pinsByGateway[gatewayID] ?? []
        let legacy = ModelPin(providerSlug: nil, modelID: pin.modelID)
        let wasPinned = pins.contains(pin)
            || (pin.providerSlug != nil && pins.contains(legacy))
        pins.remove(legacy)
        if wasPinned {
            pins.remove(pin)
        } else {
            pins.insert(pin)
        }
        pinsByGateway[gatewayID] = pins
        return pins
    }

    func removeGateway(id: String) {
        pinsByGateway.removeValue(forKey: id)
    }

    func pins(gatewayID: String) -> Set<ModelPin> {
        pinsByGateway[gatewayID] ?? []
    }

    func releaseToggle() {
        toggleContinuation?.resume()
        toggleContinuation = nil
    }
}

actor SessionPinStoreStub: SessionPinStoring {
    private var pinsByGateway: [String: Set<String>]
    private let setError: HermesError?
    private let blockFirstSet: Bool
    private var firstSetContinuation: CheckedContinuation<Void, Never>?
    private var recordedSetCalls: [String] = []
    private var completedSets = 0

    init(
        pinsByGateway: [String: Set<String>] = [:],
        setError: HermesError? = nil,
        blockFirstSet: Bool = false
    ) {
        self.pinsByGateway = pinsByGateway
        self.setError = setError
        self.blockFirstSet = blockFirstSet
    }

    func load(gatewayID: String) -> Set<String> {
        pinsByGateway[gatewayID] ?? []
    }

    func setPinned(
        gatewayID: String,
        sessionID: String,
        pinned: Bool
    ) async throws {
        recordedSetCalls.append(
            "\(gatewayID):\(sessionID):\(pinned)"
        )
        if blockFirstSet, recordedSetCalls.count == 1 {
            await withCheckedContinuation { continuation in
                firstSetContinuation = continuation
            }
        }
        completedSets += 1
        if let setError {
            throw setError
        }
        if pinned {
            pinsByGateway[gatewayID, default: []].insert(sessionID)
        } else {
            pinsByGateway[gatewayID, default: []].remove(sessionID)
        }
    }

    func removeGateway(id: String) {
        pinsByGateway.removeValue(forKey: id)
    }

    func pins(gatewayID: String) -> Set<String> {
        pinsByGateway[gatewayID] ?? []
    }

    func setCalls() -> [String] {
        recordedSetCalls
    }

    func completedSetCount() -> Int {
        completedSets
    }

    func releaseFirstSet() {
        firstSetContinuation?.resume()
        firstSetContinuation = nil
    }
}
