import Foundation

protocol SessionPinStoring: Sendable {
    func load(gatewayID: String) async throws -> Set<String>

    func setPinned(
        gatewayID: String,
        sessionID: String,
        pinned: Bool
    ) async throws

    func removeGateway(id: String) async throws
}

enum SessionPinWriteResult {
    case committed
    case failed(any Error)
}

/// FIFO persistence queue. A desired value, rather than a toggle, is written
/// so rapid taps cannot invert while crossing the actor boundary.
@MainActor
final class SessionPinWriteQueue {
    private let store: any SessionPinStoring
    private let queue = OrderedPersistenceQueue()

    init(store: any SessionPinStoring) {
        self.store = store
    }

    func enqueue(
        gatewayID: String,
        sessionID: String,
        pinned: Bool,
        completion: @escaping @MainActor (SessionPinWriteResult) -> Void
    ) {
        let store = store
        queue.enqueue {
            do {
                try await store.setPinned(
                    gatewayID: gatewayID,
                    sessionID: sessionID,
                    pinned: pinned
                )
                completion(.committed)
            } catch {
                completion(.failed(error))
            }
        }
    }
}

enum SessionPinStoreError: LocalizedError, Equatable, Sendable {
    case malformedData
    case unsupportedVersion(Int)
    case invalidGateway
    case invalidSession
    case storageAccess

    var errorDescription: String? {
        switch self {
        case .malformedData:
            "Saved session pins are damaged."
        case let .unsupportedVersion(version):
            "Saved session pins use unsupported version \(version)."
        case .invalidGateway:
            "A saved session-pin gateway is invalid."
        case .invalidSession:
            "A saved session pin is invalid."
        case .storageAccess:
            "Nile could not access protected session pins."
        }
    }
}

actor ProtectedSessionPinStore: SessionPinStoring {
    private let storage: ProtectedFileStorage
    private var removedGatewayIDs: Set<String> = []

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        storage = ProtectedFileStorage(
            fileURL: fileURL ?? ProtectedFileStorage.applicationSupportURL(
                fileName: "session-pins-v1.json",
                fileManager: fileManager
            ),
            fileManager: fileManager
        )
    }

    func load(gatewayID: String) throws -> Set<String> {
        try Self.validateGatewayID(gatewayID)
        return Set(
            try loadEnvelope().gateways.first {
                $0.gatewayID == gatewayID
            }?.sessionIDs ?? []
        )
    }

    func setPinned(
        gatewayID: String,
        sessionID: String,
        pinned: Bool
    ) throws {
        try Self.validateGatewayID(gatewayID)
        try Self.validateSessionID(sessionID)
        guard !removedGatewayIDs.contains(gatewayID) else {
            return
        }
        var envelope = try loadEnvelope()
        let index = envelope.gateways.firstIndex {
            $0.gatewayID == gatewayID
        }
        var sessionIDs = Set(
            index.map { envelope.gateways[$0].sessionIDs } ?? []
        )
        if pinned {
            sessionIDs.insert(sessionID)
        } else {
            sessionIDs.remove(sessionID)
        }
        if sessionIDs.isEmpty {
            envelope.gateways.removeAll { $0.gatewayID == gatewayID }
        } else {
            let record = PersistedGatewaySessionPins(
                gatewayID: gatewayID,
                sessionIDs: sessionIDs.sorted()
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

    private func loadEnvelope() throws -> SessionPinEnvelope {
        let envelope: SessionPinEnvelope
        do {
            guard let stored = try storage.decode(SessionPinEnvelope.self) else {
                return SessionPinEnvelope()
            }
            envelope = stored
        } catch is DecodingError {
            throw SessionPinStoreError.malformedData
        } catch {
            throw SessionPinStoreError.storageAccess
        }
        guard envelope.version == SessionPinEnvelope.currentVersion else {
            throw SessionPinStoreError.unsupportedVersion(envelope.version)
        }
        try Self.validate(envelope)
        return envelope
    }

    private func write(_ envelope: SessionPinEnvelope) throws {
        do {
            try storage.write(envelope)
        } catch {
            throw SessionPinStoreError.storageAccess
        }
    }

    private func removeFile() throws {
        do {
            try storage.remove()
        } catch {
            throw SessionPinStoreError.storageAccess
        }
    }

    private static func validate(_ envelope: SessionPinEnvelope) throws {
        var gatewayIDs: Set<String> = []
        for gateway in envelope.gateways {
            try validateGatewayID(gateway.gatewayID)
            guard gatewayIDs.insert(gateway.gatewayID).inserted,
                  !gateway.sessionIDs.isEmpty,
                  gateway.sessionIDs == Set(gateway.sessionIDs).sorted(),
                  Set(gateway.sessionIDs).count
                    == gateway.sessionIDs.count else {
                throw SessionPinStoreError.malformedData
            }
            try gateway.sessionIDs.forEach(validateSessionID)
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
            throw SessionPinStoreError.invalidGateway
        }
    }

    private static func validateSessionID(_ sessionID: String) throws {
        let trimmed = sessionID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmed == sessionID,
              !sessionID.isEmpty,
              !sessionID.contains("\n"),
              !sessionID.contains("\r") else {
            throw SessionPinStoreError.invalidSession
        }
    }
}

private struct PersistedGatewaySessionPins: Codable, Equatable, Sendable {
    let gatewayID: String
    let sessionIDs: [String]
}

private struct SessionPinEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    var gateways: [PersistedGatewaySessionPins]

    init(
        version: Int = currentVersion,
        gateways: [PersistedGatewaySessionPins] = []
    ) {
        self.version = version
        self.gateways = gateways
    }
}
