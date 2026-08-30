import Foundation

actor SecureGatewayProfileStore: GatewayProfileStoring {
    private let metadataStorage: any GatewayProfileMetadataStoring
    private let credentialStorage: any GatewayCredentialStoring

    init(
        metadataStorage: any GatewayProfileMetadataStoring =
            ProtectedFileGatewayProfileMetadataStorage(),
        credentialStorage: any GatewayCredentialStoring =
            KeychainGatewayCredentialStore()
    ) {
        self.metadataStorage = metadataStorage
        self.credentialStorage = credentialStorage
    }

    func load() async throws -> GatewayProfileSnapshot {
        let envelope = try await loadOperationalEnvelope()
        var profiles: [GatewayProfile] = []
        profiles.reserveCapacity(envelope.profiles.count)

        for metadata in envelope.profiles {
            guard let token = try await credentialStorage.token(
                credentialID: metadata.credentialID
            ) else {
                throw GatewayProfileStoreError.missingCredential(metadata.id)
            }
            profiles.append(try metadata.profile(token: token))
        }

        let active = envelope.activeGatewayID
            .flatMap { id in profiles.first { $0.id == id } }
            ?? profiles.first
        return GatewayProfileSnapshot(
            profiles: profiles,
            activeProfile: active
        )
    }

    func save(
        connection: GatewayConnection,
        name: String?
    ) async throws -> GatewayProfile {
        var envelope = try await loadOperationalEnvelope()
        let existingIndex = envelope.profiles.firstIndex {
            $0.baseURL == connection.normalizedBaseURL
        }
        let existing = existingIndex.map { envelope.profiles[$0] }
        let id = existing?.id ?? "gateway-\(UUID().uuidString.lowercased())"
        let credentialID = "credential-\(UUID().uuidString.lowercased())"
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = !trimmedName.isEmpty
            ? trimmedName
            : existing?.resolvedName
                ?? GatewayProfileStoreCodec.defaultName(
                    for: connection.normalizedBaseURL
                )
        let metadata = PersistedGatewayProfile(
            id: id,
            credentialID: credentialID,
            name: resolvedName,
            baseURL: connection.normalizedBaseURL,
            lastSessionID: existing?.lastSessionID,
            cleartextPermission: connection.endpoint.isCleartext
                ? connection.cleartextPermission
                : .denied
        )

        try await credentialStorage.storeToken(
            connection.token,
            credentialID: credentialID
        )
        if let existingIndex {
            envelope.profiles[existingIndex] = metadata
        } else {
            envelope.profiles.append(metadata)
        }
        envelope.activeGatewayID = id
        if let previousCredentialID = existing?.credentialID {
            envelope.pendingCredentialDeletions.append(previousCredentialID)
        }

        do {
            try await write(envelope)
        } catch {
            do {
                try await credentialStorage.removeToken(credentialID: credentialID)
            } catch {
                throw GatewayProfileStoreError.rollbackFailed
            }
            throw error
        }

        await finishPendingCredentialCleanup(in: envelope)
        return try metadata.profile(token: connection.token)
    }

    func selectGateway(id: String) async throws {
        var envelope = try await loadOperationalEnvelope()
        guard envelope.profiles.contains(where: { $0.id == id }) else {
            return
        }
        envelope.activeGatewayID = id
        try await write(envelope)
    }

    func removeGateway(id: String) async throws {
        var envelope = try await loadOperationalEnvelope()
        guard let removed = envelope.profiles.first(where: { $0.id == id }) else {
            return
        }

        envelope.profiles.removeAll { $0.id == id }
        envelope.pendingCredentialDeletions.append(removed.credentialID)
        if envelope.activeGatewayID == id
            || !envelope.profiles.contains(where: { $0.id == envelope.activeGatewayID }) {
            envelope.activeGatewayID = envelope.profiles.first?.id
        }

        try await write(envelope)
        await finishPendingCredentialCleanup(in: envelope)
    }

    func saveLastSessionID(
        gatewayID: String,
        storedSessionID: String
    ) async throws {
        var envelope = try await loadOperationalEnvelope()
        guard let index = envelope.profiles.firstIndex(where: { $0.id == gatewayID }) else {
            return
        }
        envelope.profiles[index].lastSessionID = storedSessionID
        envelope.activeGatewayID = envelope.activeGatewayID ?? gatewayID
        try await write(envelope)
    }

    private func loadOperationalEnvelope() async throws -> GatewayProfilesEnvelope {
        var envelope = try await loadEnvelope()
        guard !envelope.pendingCredentialDeletions.isEmpty else {
            return envelope
        }
        for credentialID in envelope.pendingCredentialDeletions {
            try await credentialStorage.removeToken(credentialID: credentialID)
        }
        envelope.pendingCredentialDeletions.removeAll()
        try await writeOrRemove(envelope)
        return envelope
    }

    private func loadEnvelope() async throws -> GatewayProfilesEnvelope {
        let data: Data?
        do {
            data = try await metadataStorage.read()
        } catch {
            throw GatewayProfileStoreError.metadataAccess
        }
        guard let data else {
            return GatewayProfilesEnvelope()
        }

        return try GatewayProfileStoreCodec.decode(data)
    }

    private func write(_ envelope: GatewayProfilesEnvelope) async throws {
        do {
            let data = try GatewayProfileStoreCodec.encode(envelope)
            try await metadataStorage.write(data)
        } catch let error as GatewayProfileStoreError {
            throw error
        } catch {
            throw GatewayProfileStoreError.metadataAccess
        }
    }

    private func writeOrRemove(_ envelope: GatewayProfilesEnvelope) async throws {
        if envelope.profiles.isEmpty
            && envelope.pendingCredentialDeletions.isEmpty {
            try await removeMetadata()
        } else {
            try await write(envelope)
        }
    }

    private func finishPendingCredentialCleanup(
        in committedEnvelope: GatewayProfilesEnvelope
    ) async {
        var envelope = committedEnvelope
        do {
            for credentialID in envelope.pendingCredentialDeletions {
                try await credentialStorage.removeToken(credentialID: credentialID)
            }
            envelope.pendingCredentialDeletions.removeAll()
            try await writeOrRemove(envelope)
        } catch {
            // The committed metadata is authoritative and retains the cleanup
            // ledger. The next store operation retries before exposing profiles.
        }
    }

    private func removeMetadata() async throws {
        do {
            try await metadataStorage.remove()
        } catch {
            throw GatewayProfileStoreError.metadataAccess
        }
    }
}
