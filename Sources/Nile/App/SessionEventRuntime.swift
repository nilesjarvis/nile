import Foundation

/// The single ordered consumer of Hermes session events.
///
/// Structural events are delivered in stream order. Assistant deltas for the
/// visible runtime are cadence-limited, but a pending delta is always published
/// before the next structural event. Deltas for hidden runtimes bypass the
/// visible cadence path so their bounded timeline projection stays current.
@MainActor
final class SessionEventRuntime {
    static let defaultAssistantDeltaPublicationInterval =
        AssistantDeltaEventCoalescer.publicationInterval

    typealias VisibleSessionID = @MainActor () -> String?
    typealias EventHandler = @MainActor (HermesStreamEvent) -> Void
    typealias VisibleAssistantDeltaHandler =
        @MainActor (HermesStreamEvent) -> Bool

    private let repository: (any HermesEventStreaming)?
    private let assistantDeltaPublicationInterval: Duration
    private var eventTask: Task<Void, Never>?
    private var assistantDeltaFlushTask: Task<Void, Never>?
    private var assistantDeltaCoalescer = AssistantDeltaEventCoalescer()
    private var visibleSessionID: VisibleSessionID?
    private var orderedEventHandler: EventHandler?
    private var visibleAssistantDeltaHandler:
        VisibleAssistantDeltaHandler?
    private var hiddenAssistantDeltaHandler: EventHandler?

    private(set) var assistantDeltaPublicationCount = 0

    init(
        repository: (any HermesEventStreaming)?,
        assistantDeltaPublicationInterval: Duration =
            SessionEventRuntime.defaultAssistantDeltaPublicationInterval
    ) {
        self.repository = repository
        self.assistantDeltaPublicationInterval =
            assistantDeltaPublicationInterval
    }

    func beginRouting(
        visibleSessionID: @escaping VisibleSessionID,
        onOrderedEvent: @escaping EventHandler,
        onVisibleAssistantDelta: @escaping VisibleAssistantDeltaHandler,
        onHiddenAssistantDelta: @escaping EventHandler
    ) {
        guard let repository, eventTask == nil else {
            return
        }
        self.visibleSessionID = visibleSessionID
        orderedEventHandler = onOrderedEvent
        visibleAssistantDeltaHandler = onVisibleAssistantDelta
        hiddenAssistantDeltaHandler = onHiddenAssistantDelta
        eventTask = Task { [weak self] in
            for await event in repository.events {
                guard !Task.isCancelled else {
                    return
                }
                self?.route(event)
            }
        }
    }

    func cancel() {
        eventTask?.cancel()
        eventTask = nil
        assistantDeltaFlushTask?.cancel()
        assistantDeltaFlushTask = nil
        visibleSessionID = nil
        orderedEventHandler = nil
        visibleAssistantDeltaHandler = nil
        hiddenAssistantDeltaHandler = nil
    }

    func flushPendingAssistantDelta() {
        flushAssistantDelta()
    }

    private func route(_ event: HermesStreamEvent) {
        guard case let .assistantDelta(sessionID, _) = event else {
            flushAssistantDelta()
            orderedEventHandler?(event)
            return
        }
        guard !sessionID.isEmpty else {
            return
        }
        guard sessionID == visibleSessionID?() else {
            hiddenAssistantDeltaHandler?(event)
            return
        }
        enqueueAssistantDelta(event)
    }

    private func enqueueAssistantDelta(_ event: HermesStreamEvent) {
        for pending in assistantDeltaCoalescer.receive(event) {
            publishAssistantDelta(pending)
        }
        guard assistantDeltaFlushTask == nil else {
            return
        }
        let publicationInterval = assistantDeltaPublicationInterval
        assistantDeltaFlushTask = Task { [weak self] in
            do {
                try await Task.sleep(for: publicationInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            self?.flushAssistantDelta()
        }
    }

    private func flushAssistantDelta() {
        assistantDeltaFlushTask?.cancel()
        assistantDeltaFlushTask = nil
        guard let event = assistantDeltaCoalescer.flush() else {
            return
        }
        publishAssistantDelta(event)
    }

    private func publishAssistantDelta(_ event: HermesStreamEvent) {
        guard visibleAssistantDeltaHandler?(event) == true else {
            return
        }
        assistantDeltaPublicationCount &+= 1
    }
}

struct AssistantDeltaEventCoalescer {
    static let maximumPublicationsPerSecond = 30
    static let publicationInterval = Duration.nanoseconds(
        1_000_000_000 / maximumPublicationsPerSecond
    )

    private var pendingSessionID: String?
    private var pendingText = ""

    mutating func receive(_ event: HermesStreamEvent) -> [HermesStreamEvent] {
        guard case let .assistantDelta(sessionID, text) = event else {
            var events: [HermesStreamEvent] = []
            if let pending = takePendingDelta() {
                events.append(pending)
            }
            events.append(event)
            return events
        }

        guard let pendingSessionID else {
            self.pendingSessionID = sessionID
            pendingText = text
            return []
        }
        guard pendingSessionID == sessionID else {
            let pending = takePendingDelta()
            self.pendingSessionID = sessionID
            pendingText = text
            return pending.map { [$0] } ?? []
        }
        pendingText += text
        return []
    }

    mutating func flush() -> HermesStreamEvent? {
        takePendingDelta()
    }

    private mutating func takePendingDelta() -> HermesStreamEvent? {
        guard let pendingSessionID else {
            return nil
        }
        let event = HermesStreamEvent.assistantDelta(
            sessionID: pendingSessionID,
            text: pendingText
        )
        self.pendingSessionID = nil
        pendingText = ""
        return event
    }
}
