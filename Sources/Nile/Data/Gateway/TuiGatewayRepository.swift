import Foundation

final class TuiGatewayRepository:
    SessionRepositoryCapabilityProviding,
    HermesEventStreaming,
    HermesConnectionServing,
    GatewayConnecting,
    Sendable
{
    let events: AsyncStream<HermesStreamEvent>

    var sessionCapabilities: SessionRepositoryCapabilities {
        SessionRepositoryCapabilities(
            events: self,
            sessions: sessions,
            sessionClaim: sessions,
            sessionRenaming: sessions,
            turns: turns,
            talk: talk,
            delegation: delegation,
            blockingPrompts: blockingPrompts,
            models: models,
            sessionUsage: usage,
            gatewayStatistics: usage,
            attachmentReading: attachments,
            attachmentMutating: attachments,
            prompts: turns,
            disconnect: self,
            transcription: speech,
            speechSynthesis: speech,
            commands: commands,
            goals: goals
        )
    }

    var voiceService: any HermesVoiceServing {
        speech
    }

    private let connectionClient: any GatewayConnecting
    private let delegation: GatewayDelegationService
    private let blockingPrompts: GatewayBlockingPromptService
    private let commands: GatewayCommandService
    private let goals: GatewayGoalService
    private let models: GatewayModelService
    private let usage: GatewayUsageService
    private let attachments: GatewayAttachmentService
    private let speech: GatewaySpeechService
    private let sessions: GatewaySessionService
    private let turns: GatewayTurnService
    private let talk: GatewayTalkService
    private let connectionState: GatewayConnectionState

    convenience init(
        client: TuiGatewayClient,
        dashboard: (any GatewayDashboardReading)? = GatewayDashboardClient()
    ) {
        self.init(
            rpc: client,
            connectionClient: client,
            signalSequence: client.signals,
            dashboard: dashboard
        )
    }

    convenience init(
        rpc: any GatewayRPCRequesting,
        connectionClient: any GatewayConnecting,
        signals: AsyncStream<GatewaySignal>,
        dashboard: (any GatewayDashboardReading)? = nil
    ) {
        self.init(
            rpc: rpc,
            connectionClient: connectionClient,
            signalSequence: signals,
            dashboard: dashboard
        )
    }

    private init<Signals>(
        rpc: any GatewayRPCRequesting,
        connectionClient: any GatewayConnecting,
        signalSequence: Signals,
        dashboard: (any GatewayDashboardReading)?
    ) where
        Signals: AsyncSequence & Sendable,
        Signals.Element == GatewaySignal
    {
        let connectionState = GatewayConnectionState()
        let commands = GatewayCommandService(rpc: rpc)
        let sessions = GatewaySessionService(
            rpc: rpc,
            connectionState: connectionState,
            dashboard: dashboard
        )
        let turns = GatewayTurnService(rpc: rpc)
        self.connectionClient = connectionClient
        delegation = GatewayDelegationService(rpc: rpc)
        blockingPrompts = GatewayBlockingPromptService(rpc: rpc)
        self.commands = commands
        goals = GatewayGoalService(rpc: rpc, commands: commands)
        models = GatewayModelService(rpc: rpc)
        usage = GatewayUsageService(
            rpc: rpc,
            connectionState: connectionState,
            dashboard: dashboard
        )
        attachments = GatewayAttachmentService(
            rpc: rpc,
            connectionState: connectionState,
            dashboard: dashboard
        )
        speech = GatewaySpeechService(
            connectionState: connectionState,
            dashboard: dashboard
        )
        self.sessions = sessions
        self.turns = turns
        talk = GatewayTalkService(
            prompts: turns,
            runtimeStatus: sessions
        )
        self.connectionState = connectionState
        events = Self.projectedEvents(signalSequence)
    }

    func connect(_ connection: GatewayConnection) async throws {
        try await connectionClient.connect(
            connection,
            timeoutMilliseconds: 15_000
        )
        await connectionState.set(connection)
    }

    func connect(
        _ connection: GatewayConnection,
        timeoutMilliseconds: Int64
    ) async throws {
        try await connectionClient.connect(
            connection,
            timeoutMilliseconds: timeoutMilliseconds
        )
        await connectionState.set(connection)
    }

    func close() async {
        await connectionState.clear()
        await connectionClient.close()
    }

    func disconnect() async {
        await close()
    }

    private static func projectedEvents<S>(
        _ signals: S
    ) -> AsyncStream<HermesStreamEvent>
    where S: AsyncSequence & Sendable, S.Element == GatewaySignal {
        AsyncStream { continuation in
            let task = Task {
                let projector = GatewayEventProjector()
                do {
                    for try await signal in signals {
                        switch signal {
                        case let .event(_, frame):
                            if let event = projector.project(frame) {
                                continuation.yield(event)
                            }
                        case let .failure(_, failure):
                            continuation.yield(
                                .connectionLost(
                                    message: failure.message,
                                    authRejected: failure.authRejected,
                                    retryable: failure.retryable
                                )
                            )
                        }
                    }
                } catch {
                    continuation.yield(
                        .connectionLost(
                            message: error.localizedDescription,
                            authRejected: false,
                            retryable: true
                        )
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
