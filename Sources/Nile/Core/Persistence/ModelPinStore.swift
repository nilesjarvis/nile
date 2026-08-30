import Foundation

protocol ModelPinStoring: Sendable {
    func load(gatewayID: String) async throws -> Set<ModelPin>

    /// Atomically toggles one provider-aware pin and returns the committed set.
    func toggle(
        gatewayID: String,
        pin: ModelPin
    ) async throws -> Set<ModelPin>

    func removeGateway(id: String) async throws
}

enum ModelPinWriteResult {
    case committed(Set<ModelPin>)
    case failed(any Error, authoritative: Set<ModelPin>?)
}

/// FIFO persistence queue. Enqueue is main-actor synchronous so rapid taps
/// cannot invert before reaching the protected actor, and queued writes keep
/// running even if the originating session model is replaced.
@MainActor
final class ModelPinWriteQueue {
    private let store: any ModelPinStoring
    private let queue = OrderedPersistenceQueue()

    init(store: any ModelPinStoring) {
        self.store = store
    }

    func enqueue(
        gatewayID: String,
        pin: ModelPin,
        completion: @escaping @MainActor (ModelPinWriteResult) -> Void
    ) {
        let store = store
        queue.enqueue {
            do {
                completion(
                    .committed(
                        try await store.toggle(
                            gatewayID: gatewayID,
                            pin: pin
                        )
                    )
                )
            } catch {
                let authoritative = try? await store.load(
                    gatewayID: gatewayID
                )
                completion(
                    .failed(error, authoritative: authoritative)
                )
            }
        }
    }
}

enum ModelPinStoreError: LocalizedError, Equatable, Sendable {
    case malformedData
    case unsupportedVersion(Int)
    case invalidGateway
    case invalidPin
    case storageAccess

    var errorDescription: String? {
        switch self {
        case .malformedData:
            "Saved model pins are damaged."
        case let .unsupportedVersion(version):
            "Saved model pins use unsupported version \(version)."
        case .invalidGateway:
            "A saved model-pin gateway is invalid."
        case .invalidPin:
            "A saved model pin is invalid."
        case .storageAccess:
            "Nile could not access protected model pins."
        }
    }
}

actor ProtectedModelPinStore: ModelPinStoring {
    private let storage: ProtectedFileStorage
    private var removedGatewayIDs: Set<String> = []

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        storage = ProtectedFileStorage(
            fileURL: fileURL ?? ProtectedFileStorage.applicationSupportURL(
                fileName: "model-pins-v1.json",
                fileManager: fileManager
            ),
            fileManager: fileManager
        )
    }

    func load(gatewayID: String) throws -> Set<ModelPin> {
        try Self.validateGatewayID(gatewayID)
        return Set(
            try loadEnvelope().gateways.first {
                $0.gatewayID == gatewayID
            }?.pins ?? []
        )
    }

    func toggle(
        gatewayID: String,
        pin: ModelPin
    ) throws -> Set<ModelPin> {
        try Self.validateGatewayID(gatewayID)
        try Self.validate(pin)
        guard !removedGatewayIDs.contains(gatewayID) else {
            return []
        }
        var envelope = try loadEnvelope()
        let index = envelope.gateways.firstIndex {
            $0.gatewayID == gatewayID
        }
        var pins = Set(index.map { envelope.gateways[$0].pins } ?? [])
        let legacyPin = ModelPin(providerSlug: nil, modelID: pin.modelID)
        let wasPinned = pins.contains(pin)
            || (pin.providerSlug != nil && pins.contains(legacyPin))
        pins.remove(legacyPin)
        if wasPinned {
            pins.remove(pin)
        } else {
            pins.insert(pin)
        }
        if pins.isEmpty {
            envelope.gateways.removeAll { $0.gatewayID == gatewayID }
        } else {
            let record = PersistedGatewayModelPins(
                gatewayID: gatewayID,
                pins: Self.sortedPins(pins)
            )
            if let index {
                envelope.gateways[index] = record
            } else {
                envelope.gateways.append(record)
            }
        }
        envelope.gateways.sort { $0.gatewayID < $1.gatewayID }
        if envelope.gateways.isEmpty {
            try removeFile()
        } else {
            try write(envelope)
        }
        return pins
    }

    func removeGateway(id: String) throws {
        try Self.validateGatewayID(id)
        removedGatewayIDs.insert(id)
        var envelope = try loadEnvelope()
        let count = envelope.gateways.count
        envelope.gateways.removeAll { $0.gatewayID == id }
        guard envelope.gateways.count != count else {
            return
        }
        if envelope.gateways.isEmpty {
            try removeFile()
        } else {
            try write(envelope)
        }
    }

    private func loadEnvelope() throws -> ModelPinEnvelope {
        let envelope: ModelPinEnvelope
        do {
            guard let stored = try storage.decode(ModelPinEnvelope.self) else {
                return ModelPinEnvelope()
            }
            envelope = stored
        } catch is DecodingError {
            throw ModelPinStoreError.malformedData
        } catch {
            throw ModelPinStoreError.storageAccess
        }
        guard envelope.version == ModelPinEnvelope.currentVersion else {
            throw ModelPinStoreError.unsupportedVersion(envelope.version)
        }
        try Self.validate(envelope)
        return envelope
    }

    private func write(_ envelope: ModelPinEnvelope) throws {
        do {
            try storage.write(envelope)
        } catch {
            throw ModelPinStoreError.storageAccess
        }
    }

    private func removeFile() throws {
        do {
            try storage.remove()
        } catch {
            throw ModelPinStoreError.storageAccess
        }
    }

    private static func validate(_ envelope: ModelPinEnvelope) throws {
        var gatewayIDs: Set<String> = []
        for gateway in envelope.gateways {
            try validateGatewayID(gateway.gatewayID)
            guard gatewayIDs.insert(gateway.gatewayID).inserted,
                  !gateway.pins.isEmpty,
                  gateway.pins == sortedPins(Set(gateway.pins)),
                  Set(gateway.pins).count == gateway.pins.count else {
                throw ModelPinStoreError.malformedData
            }
            try gateway.pins.forEach(validate)
        }
    }

    private static func validateGatewayID(_ gatewayID: String) throws {
        let trimmed = gatewayID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmed == gatewayID,
              !gatewayID.isEmpty,
              !gatewayID.contains("\n"),
              !gatewayID.contains("\r") else {
            throw ModelPinStoreError.invalidGateway
        }
    }

    private static func validate(_ pin: ModelPin) throws {
        let model = pin.modelID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let provider = pin.providerSlug?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard model == pin.modelID,
              !model.isEmpty,
              !model.contains("\n"),
              !model.contains("\r"),
              provider == pin.providerSlug,
              provider?.isEmpty != true,
              provider?.contains("\n") != true,
              provider?.contains("\r") != true else {
            throw ModelPinStoreError.invalidPin
        }
    }

    private static func sortedPins(_ pins: Set<ModelPin>) -> [ModelPin] {
        pins.sorted {
            let leftProvider = $0.providerSlug ?? ""
            let rightProvider = $1.providerSlug ?? ""
            return leftProvider == rightProvider
                ? $0.modelID < $1.modelID
                : leftProvider < rightProvider
        }
    }
}

private struct PersistedGatewayModelPins: Codable, Equatable, Sendable {
    let gatewayID: String
    let pins: [ModelPin]
}

private struct ModelPinEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var gateways: [PersistedGatewayModelPins]

    init(
        version: Int = currentVersion,
        gateways: [PersistedGatewayModelPins] = []
    ) {
        self.version = version
        self.gateways = gateways
    }
}
