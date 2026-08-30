import Foundation

enum VoiceDraftTransition: Equatable, Sendable {
    case preparing
    case transcribing
    case listening(composer: String)
    case finished(composer: String)
    case error(composer: String, message: String)
}

@MainActor
final class VoiceInputCoordinator {
    let input: any VoiceInput
    private var composerBeforeVoice = ""
    private(set) var eventsAreEnabled = false

    init(input: any VoiceInput) {
        self.input = input
    }

    var isAvailable: Bool { input.isAvailable }
    var events: AsyncStream<VoiceInputEvent> { input.events }

    func start(composer: String) {
        composerBeforeVoice = composer
        eventsAreEnabled = true
        input.start()
    }

    func stop() {
        input.stop()
    }

    func cancel() {
        eventsAreEnabled = false
        input.cancel()
    }

    func cancelAdapter() {
        input.cancel()
    }

    func transition(
        event: VoiceInputEvent
    ) -> VoiceDraftTransition? {
        guard eventsAreEnabled else {
            return nil
        }
        switch event {
        case .preparing:
            return .preparing
        case let .listening(partialText):
            return .listening(composer: join(partialText))
        case .transcribing:
            return .transcribing
        case let .finished(text):
            return .finished(composer: join(text))
        case let .error(message):
            return .error(
                composer: composerBeforeVoice,
                message: message
            )
        }
    }

    func finishEvents() {
        eventsAreEnabled = false
    }

    private func join(_ spoken: String) -> String {
        if spoken.isBlank {
            return composerBeforeVoice
        }
        if composerBeforeVoice.isBlank {
            return spoken
        }
        return composerBeforeVoice
            .replacingOccurrences(
                of: #"\s+$"#,
                with: "",
                options: .regularExpression
            )
            + " "
            + spoken
    }
}

struct HermesVoiceRequest: Sendable {
    let generation: Int64
    let gatewayID: String?
    let operation: HermesVoiceOperation
}

enum HermesVoiceOperation: Equatable, Sendable {
    case load
    case update(expectedProvider: String, voice: String)
}

enum HermesVoiceResult: Sendable {
    case success(
        request: HermesVoiceRequest,
        config: HermesVoiceConfig
    )
    case failure(
        request: HermesVoiceRequest,
        error: any Error
    )

    var request: HermesVoiceRequest {
        switch self {
        case let .success(request, _), let .failure(request, _):
            return request
        }
    }
}

@MainActor
final class HermesVoiceCoordinator {
    private let loadVoice:
        @Sendable () async throws -> HermesVoiceConfig
    private let updateVoice:
        @Sendable (String, String) async throws -> HermesVoiceConfig
    private var generation: Int64 = 0
    private var requestTask: Task<Void, Never>?

    init(
        loadVoice: @escaping @Sendable () async throws ->
            HermesVoiceConfig,
        updateVoice: @escaping @Sendable (
            String,
            String
        ) async throws -> HermesVoiceConfig
    ) {
        self.loadVoice = loadVoice
        self.updateVoice = updateVoice
    }

    func load(
        gatewayID: String?,
        onStarted: () -> Void,
        onResult: @escaping @MainActor (HermesVoiceResult) -> Void
    ) {
        start(
            gatewayID: gatewayID,
            operation: .load,
            onStarted: onStarted,
            onResult: onResult
        )
    }

    func update(
        gatewayID: String?,
        expectedProvider: String,
        voice: String,
        onStarted: () -> Void,
        onResult: @escaping @MainActor (HermesVoiceResult) -> Void
    ) {
        start(
            gatewayID: gatewayID,
            operation: .update(
                expectedProvider: expectedProvider,
                voice: voice
            ),
            onStarted: onStarted,
            onResult: onResult
        )
    }

    func invalidate() {
        generation += 1
        requestTask?.cancel()
        requestTask = nil
    }

    func isCurrent(_ request: HermesVoiceRequest) -> Bool {
        request.generation == generation
    }

    private func start(
        gatewayID: String?,
        operation: HermesVoiceOperation,
        onStarted: () -> Void,
        onResult: @escaping @MainActor (HermesVoiceResult) -> Void
    ) {
        invalidate()
        let request = HermesVoiceRequest(
            generation: generation,
            gatewayID: gatewayID,
            operation: operation
        )
        onStarted()
        let loadVoice = loadVoice
        let updateVoice = updateVoice
        requestTask = Task {
            do {
                let config: HermesVoiceConfig
                switch operation {
                case .load:
                    config = try await loadVoice()
                case let .update(expectedProvider, voice):
                    config = try await updateVoice(
                        expectedProvider,
                        voice
                    )
                }
                try Task.checkCancellation()
                onResult(.success(request: request, config: config))
            } catch is CancellationError {
                return
            } catch {
                onResult(.failure(request: request, error: error))
            }
        }
    }
}
