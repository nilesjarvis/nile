import Foundation
import Observation

@MainActor
@Observable
final class SessionPinRuntime {
    struct GatewayOwner: Equatable, Sendable {
        let gatewayGeneration: Int
        let gatewayID: String
    }

    typealias ErrorHandler = @MainActor @Sendable (String) -> Void

    private(set) var pinnedSessionIDs: Set<String> = []

    private let store: (any SessionPinStoring)?
    private let writeQueue: SessionPinWriteQueue?
    private var currentOwner: GatewayOwner?

    init(
        store: (any SessionPinStoring)?,
        writeQueue: SessionPinWriteQueue? = nil
    ) {
        self.store = store
        self.writeQueue = store.map {
            writeQueue ?? SessionPinWriteQueue(store: $0)
        }
    }

    func resetGateway(owner: GatewayOwner) {
        currentOwner = owner
        pinnedSessionIDs = []
    }

    func synchronizeGateway(owner: GatewayOwner) {
        currentOwner = owner
    }

    func restorePins(owner: GatewayOwner) async -> String? {
        guard currentOwner == owner else {
            return nil
        }
        guard let store else {
            pinnedSessionIDs = []
            return nil
        }
        do {
            let pins = try await store.load(gatewayID: owner.gatewayID)
            guard currentOwner == owner else {
                return nil
            }
            pinnedSessionIDs = pins
            return nil
        } catch {
            guard currentOwner == owner else {
                return nil
            }
            pinnedSessionIDs = []
            return
                "Nile could not restore protected session pins: \(error.localizedDescription)"
        }
    }

    func togglePin(
        sessionID: String,
        owner: GatewayOwner,
        onError: @escaping ErrorHandler
    ) {
        guard currentOwner == owner else {
            return
        }
        let pinned = !pinnedSessionIDs.contains(sessionID)
        setPinned(sessionID, pinned: pinned)
        guard let writeQueue else {
            return
        }
        writeQueue.enqueue(
            gatewayID: owner.gatewayID,
            sessionID: sessionID,
            pinned: pinned
        ) { [weak self] result in
            guard let self,
                  self.currentOwner == owner,
                  case let .failed(error) = result else {
                return
            }
            if self.pinnedSessionIDs.contains(sessionID) == pinned {
                self.setPinned(sessionID, pinned: !pinned)
            }
            onError(
                "Could not save the session pin: \(error.localizedDescription)"
            )
        }
    }

    private func setPinned(_ sessionID: String, pinned: Bool) {
        if pinned {
            pinnedSessionIDs.insert(sessionID)
        } else {
            pinnedSessionIDs.remove(sessionID)
        }
    }
}
