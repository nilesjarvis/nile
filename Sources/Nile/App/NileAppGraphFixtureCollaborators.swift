import Foundation

#if DEBUG || NILE_LOCAL_RELEASE
extension NileAppGraphFixtures {
#if DEBUG
    @MainActor
    final class BiometricAppLockFixtureStore:
        BiometricAppLockStoring
    {
        func isEnabled() -> Bool {
            true
        }

        func setEnabled(_ enabled: Bool) {}
    }

    @MainActor
    final class BiometricAppLockFixtureAuthenticator:
        BiometricAuthenticating
    {
        private var outcomes = [true, false]

        func capability() -> NileBiometricCapability {
            .available(.faceID)
        }

        func authenticate(reason: String) -> Bool {
            outcomes.isEmpty ? false : outcomes.removeFirst()
        }
    }
#endif

    actor GatewayVisualFixtureProfileStore:
        GatewayProfileStoring
    {
        private var profiles: [GatewayProfile]
        private var activeID: String?

        init(profiles: [GatewayProfile], activeID: String?) {
            self.profiles = profiles
            self.activeID = activeID
        }

        func load() -> GatewayProfileSnapshot {
            GatewayProfileSnapshot(
                profiles: profiles,
                activeProfile: activeID.flatMap { activeID in
                    profiles.first { $0.id == activeID }
                } ?? profiles.first
            )
        }

        func save(
            connection: GatewayConnection,
            name: String?
        ) -> GatewayProfile {
            let existing = profiles.first {
                $0.normalizedBaseURL == connection.normalizedBaseURL
            }
            let saved = GatewayProfile(
                id: existing?.id ?? "fixture-saved",
                name: name ?? "",
                endpoint: connection.endpoint,
                token: connection.token,
                lastSessionID: existing?.lastSessionID,
                cleartextPermission: connection.cleartextPermission
            )
            profiles.removeAll { $0.id == saved.id }
            profiles.append(saved)
            activeID = saved.id
            return saved
        }

        func selectGateway(id: String) {
            guard profiles.contains(where: { $0.id == id }) else {
                return
            }
            activeID = id
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
        ) {
            guard let index = profiles.firstIndex(
                where: { $0.id == gatewayID }
            ) else {
                return
            }
            let current = profiles[index]
            profiles[index] = GatewayProfile(
                id: current.id,
                name: current.name,
                endpoint: current.endpoint,
                token: current.token,
                lastSessionID: storedSessionID,
                cleartextPermission: current.cleartextPermission
            )
        }
    }

    actor GatewaySwitchFixtureConnectionClient: GatewayConnecting {
        func connect(
            _ connection: GatewayConnection,
            timeoutMilliseconds: Int64
        ) async throws {}

        func close() async {}
    }

    struct GatewayRemovalFixtureSessionCleaner:
        GatewaySessionCleaning
    {
        func clearSession(
            for connection: GatewayConnection,
            includeHostWideCookies: Bool
        ) async throws {}
    }

    final class TalkFixtureVoiceInput:
        VoiceInput,
        @unchecked Sendable
    {
        let isAvailable = true
        let events: AsyncStream<VoiceInputEvent>
        private let continuation:
            AsyncStream<VoiceInputEvent>.Continuation

        init() {
            let pair = AsyncStream.makeStream(
                of: VoiceInputEvent.self,
                bufferingPolicy: .bufferingNewest(16)
            )
            events = pair.stream
            continuation = pair.continuation
        }

        func start() {
            continuation.yield(.preparing)
            continuation.yield(.listening(partialText: ""))
        }

        func stop() {
            continuation.yield(.finished(text: ""))
        }

        func cancel() {}
    }

    actor HermesVoiceFixtureService: HermesVoiceServing {
        private var config = HermesVoiceConfig(
            provider: "edge",
            voice: "en-US-AriaNeural"
        )

        func getHermesVoiceConfig() -> HermesVoiceConfig {
            config
        }

        func setHermesVoice(
            expectedProvider: String,
            voice: String
        ) throws -> HermesVoiceConfig {
            guard expectedProvider == config.provider else {
                throw HermesError(
                    "Hermes changed voice providers. Refresh and try again.",
                    retryable: false
                )
            }
            config = HermesVoiceConfig(
                provider: expectedProvider,
                voice: voice
            )
            return config
        }
    }
}
#endif
