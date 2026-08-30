import Foundation
import XCTest
@testable import Nile

actor ModelGatewayStore: GatewayProfileStoring {
    private var profiles: [GatewayProfile]
    private var activeID: String?
    private(set) var loadCount = 0
    private(set) var savedConnections: [GatewayConnection] = []
    private(set) var selectedIDs: [String] = []

    var currentActiveID: String? {
        activeID
    }

    init(
        profiles: [GatewayProfile] = [],
        activeID: String? = nil
    ) {
        self.profiles = profiles
        self.activeID = activeID
    }

    func load() -> GatewayProfileSnapshot {
        loadCount += 1
        return GatewayProfileSnapshot(
            profiles: profiles,
            activeProfile: activeID
                .flatMap { id in profiles.first { $0.id == id } }
                ?? profiles.first
        )
    }

    func save(
        connection: GatewayConnection,
        name: String?
    ) -> GatewayProfile {
        savedConnections.append(connection)
        let existing = profiles.first {
            $0.normalizedBaseURL == connection.normalizedBaseURL
        }
        let profile = GatewayProfile(
            id: existing?.id ?? "gateway-test",
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            endpoint: connection.endpoint,
            token: connection.token,
            lastSessionID: existing?.lastSessionID,
            cleartextPermission: connection.endpoint.isCleartext
                ? connection.cleartextPermission
                : .denied
        )
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        activeID = profile.id
        return profile
    }

    func selectGateway(id: String) {
        if profiles.contains(where: { $0.id == id }) {
            activeID = id
            selectedIDs.append(id)
        }
    }

    func removeGateway(id: String) {
        profiles.removeAll { $0.id == id }
        if activeID == id {
            activeID = profiles.first?.id
        }
    }

    func saveLastSessionID(
        gatewayID: String,
        storedSessionID: String
    ) {}
}

actor ModelComposerDraftStore: ComposerDraftStoring {
    private var records: [PersistedComposerDraft]

    init(records: [PersistedComposerDraft] = []) {
        self.records = records
    }

    func load() -> [PersistedComposerDraft] {
        records
    }

    func update(_ draft: PersistedComposerDraft) -> Bool {
        records.removeAll { $0.owner == draft.owner }
        records.append(draft)
        return true
    }

    func migrate(_ changes: [ComposerDraftMigrationChange]) -> Bool {
        for change in changes {
            let current = records.first { $0.owner == change.owner }
            guard current == change.expected else {
                return false
            }
        }
        for change in changes {
            records.removeAll { $0.owner == change.owner }
            records.append(change.replacement)
        }
        return true
    }

    func removeGateway(id: String) {
        records.removeAll { $0.gatewayID == id }
    }
}

actor GatewayModelPinStore: ModelPinStoring {
    private var pinsByGateway: [String: Set<ModelPin>]

    init(pinsByGateway: [String: Set<ModelPin>] = [:]) {
        self.pinsByGateway = pinsByGateway
    }

    func load(gatewayID: String) -> Set<ModelPin> {
        pinsByGateway[gatewayID] ?? []
    }

    func toggle(
        gatewayID: String,
        pin: ModelPin
    ) -> Set<ModelPin> {
        var pins = pinsByGateway[gatewayID] ?? []
        if pins.remove(pin) == nil {
            pins.insert(pin)
        }
        pinsByGateway[gatewayID] = pins
        return pins
    }

    func removeGateway(id: String) {
        pinsByGateway.removeValue(forKey: id)
    }
}

actor GatewaySessionPinStore: SessionPinStoring {
    private var pinsByGateway: [String: Set<String>]

    init(pinsByGateway: [String: Set<String>] = [:]) {
        self.pinsByGateway = pinsByGateway
    }

    func load(gatewayID: String) -> Set<String> {
        pinsByGateway[gatewayID] ?? []
    }

    func setPinned(
        gatewayID: String,
        sessionID: String,
        pinned: Bool
    ) {
        if pinned {
            pinsByGateway[gatewayID, default: []].insert(sessionID)
        } else {
            pinsByGateway[gatewayID, default: []].remove(sessionID)
        }
    }

    func removeGateway(id: String) {
        pinsByGateway.removeValue(forKey: id)
    }
}
