import Observation

/// Owns gateway-scoped model-pin persistence and publication fencing.
@MainActor
@Observable
final class ModelPinRuntime {
    var gatewayID: String?
    var pins: Set<ModelPin> = []

    private let store: (any ModelPinStoring)?
    private let writeQueue: ModelPinWriteQueue?
    private let permitsInMemoryMutation: Bool
    private var mutationGeneration: Int64 = 0
    private var currentOwner: ModelControlGatewayOwner?

    init(
        store: (any ModelPinStoring)?,
        writeQueue: ModelPinWriteQueue? = nil,
        permitsInMemoryMutation: Bool
    ) {
        self.store = store
        self.writeQueue = store.map {
            writeQueue ?? ModelPinWriteQueue(store: $0)
        }
        self.permitsInMemoryMutation = permitsInMemoryMutation
    }

    func installFixture(
        pins: Set<ModelPin>,
        gatewayID: String?
    ) {
        self.gatewayID = gatewayID
        self.pins = pins
        currentOwner = gatewayID.map {
            ModelControlGatewayOwner(
                gatewayGeneration: 0,
                gatewayID: $0
            )
        }
    }

    func reset(owner: ModelControlGatewayOwner) {
        currentOwner = owner
        mutationGeneration &+= 1
        gatewayID = nil
        pins = []
    }

    func synchronize(owner: ModelControlGatewayOwner) {
        currentOwner = owner
        mutationGeneration &+= 1
    }

    func restore(owner: ModelControlGatewayOwner) async -> String? {
        guard currentOwner == owner else {
            return nil
        }
        guard let store else {
            gatewayID = owner.gatewayID
            pins = []
            return nil
        }
        do {
            let restored = try await store.load(gatewayID: owner.gatewayID)
            guard currentOwner == owner else {
                return nil
            }
            gatewayID = owner.gatewayID
            pins = restored
            return nil
        } catch {
            guard currentOwner == owner else {
                return nil
            }
            gatewayID = nil
            pins = []
            return
                "Nile could not restore protected model pins: \(error.localizedDescription)"
        }
    }

    func toggle(
        owner: ModelControlGatewayOwner?,
        provider: String?,
        model: String,
        onError: @escaping ModelControlErrorHandler
    ) {
        guard let owner,
              currentOwner == owner,
              gatewayID == owner.gatewayID else {
            onError(
                "Model pins are not ready for this gateway. Reopen the picker and try again."
            )
            return
        }
        let pin: ModelPin
        switch ModelControlPolicy.pinAdmission(
            provider: provider,
            model: model
        ) {
        case let .allowed(allowed):
            pin = allowed
        case let .rejected(message):
            onError(message)
            return
        }
        if store == nil, permitsInMemoryMutation {
            if pins.remove(pin) == nil {
                pins.insert(pin)
            }
            return
        }
        guard let writeQueue else {
            onError("Model-pin storage is unavailable.")
            return
        }
        mutationGeneration &+= 1
        let generation = mutationGeneration
        writeQueue.enqueue(
            gatewayID: owner.gatewayID,
            pin: pin
        ) { [weak self] result in
            guard let self,
                  currentOwner == owner,
                  gatewayID == owner.gatewayID,
                  mutationGeneration == generation else {
                return
            }
            switch result {
            case let .committed(committed):
                pins = committed
                onError(nil)
            case let .failed(error, authoritative):
                if let authoritative {
                    pins = authoritative
                }
                onError(error.localizedDescription)
            }
        }
    }

    func canModify(gatewayID: String?) -> Bool {
        guard let gatewayID, self.gatewayID == gatewayID else {
            return false
        }
        return store != nil || permitsInMemoryMutation
    }
}
