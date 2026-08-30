import Foundation

final class LiveTranscriptCoordinator {
    private let idFactory: (String) -> String
    private let toolProjector: LiveTranscriptToolProjector
    private var activeAssistantID: String?
    private var turnProducedText = false
    private var imageCache: TranscriptImagePayloadCache

    init(
        idFactory: @escaping (String) -> String = {
            "\($0)-\(UUID().uuidString.lowercased())"
        },
        clockMilliseconds: @escaping () -> Int64 = {
            Int64(Date().timeIntervalSince1970 * 1_000)
        },
        maxCachedImages: Int = 8,
        maxCachedImageBase64Characters: Int = 8 * 1_024 * 1_024
    ) {
        self.idFactory = idFactory
        toolProjector = LiveTranscriptToolProjector(
            clockMilliseconds: clockMilliseconds
        )
        imageCache = TranscriptImagePayloadCache(
            maximumEntryCount: maxCachedImages,
            maximumBase64CharacterCount: maxCachedImageBase64Characters
        )
    }

    func rememberImage(path: String, base64: String) {
        imageCache.remember(path: path, base64: base64)
    }

    func cachedImages() -> [String: String] {
        imageCache.images
    }

    func clearCachedImages() {
        imageCache.removeAll()
    }

    func beginTurn() {
        activeAssistantID = nil
        turnProducedText = false
    }

    func closeAssistantBubble() {
        activeAssistantID = nil
    }

    func restoreTurn(
        activeAssistantID: String?,
        turnProducedText: Bool
    ) {
        self.activeAssistantID = activeAssistantID
        self.turnProducedText = turnProducedText
    }

    func appendAssistant(
        _ delta: String,
        to transcript: [TranscriptEntry]
    ) -> [TranscriptEntry] {
        var transcript = transcript
        appendAssistant(delta, to: &transcript)
        return transcript
    }

    func appendAssistant(
        _ delta: String,
        to transcript: inout [TranscriptEntry]
    ) {
        let id: String
        if let activeAssistantID {
            id = activeAssistantID
        } else {
            id = idFactory("assistant")
            activeAssistantID = id
        }
        turnProducedText = true

        let assistantIndex: Int
        if transcript.last?.id == id {
            assistantIndex = transcript.index(before: transcript.endIndex)
        } else if let existingIndex = transcript.lastIndex(
            where: { $0.id == id }
        ) {
            assistantIndex = existingIndex
        } else {
            transcript.append(
                .message(
                    TranscriptMessage(
                        id: id,
                        role: .assistant,
                        content: ""
                    )
                )
            )
            assistantIndex = transcript.index(before: transcript.endIndex)
        }
        guard case var .message(message) = transcript[assistantIndex] else {
            return
        }
        message.content += delta
        transcript[assistantIndex] = .message(message)
    }

    func finalizeInterimAssistant(
        _ content: String,
        in transcript: [TranscriptEntry]
    ) -> [TranscriptEntry] {
        let authoritative = content.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !authoritative.isEmpty else {
            return transcript
        }
        let id = activeAssistantID ?? idFactory("assistant")
        activeAssistantID = nil
        // An interim message seals one assistant segment without ending the
        // turn. The next delta or completion must therefore be allowed to
        // create a new segment.
        turnProducedText = false
        return ensureAssistant(id, in: transcript).map { entry in
            guard case let .message(message) = entry,
                  message.id == id else {
                return entry
            }
            return .message(
                finalizeAssistant(
                    message,
                    authoritativeContent: content
                )
            )
        }
    }

    func completeAssistant(
        _ content: String,
        in transcript: [TranscriptEntry]
    ) -> [TranscriptEntry] {
        let completionID: String?
        if let activeAssistantID {
            completionID = activeAssistantID
        } else if !turnProducedText,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty {
            completionID = idFactory("assistant")
        } else {
            completionID = nil
        }
        activeAssistantID = nil
        guard let completionID else {
            return transcript
        }
        return ensureAssistant(completionID, in: transcript).map { entry in
            guard case let .message(message) = entry,
                  message.id == completionID else {
                return entry
            }
            return .message(
                finalizeAssistant(
                    message,
                    authoritativeContent: content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty ? nil : content
                )
            )
        }
    }

    func appendSystem(
        _ content: String,
        isError: Bool = false,
        to transcript: [TranscriptEntry]
    ) -> [TranscriptEntry] {
        let closedAssistantID = activeAssistantID
        closeAssistantBubble()
        return finalizeAssistant(
            closedAssistantID,
            in: transcript
        ) + [
            .message(
                TranscriptMessage(
                    id: idFactory("system"),
                    role: .system,
                    content: content,
                    isError: isError
                )
            ),
        ]
    }

    func upsertTool(
        in transcript: [TranscriptEntry],
        activeTodos: [TodoItem]?,
        event: LiveToolEvent
    ) -> LiveTranscriptProjection {
        let startsNewTool = toolProjector.startsNewTool(
            in: transcript,
            event: event
        )
        let closedAssistantID = startsNewTool ? activeAssistantID : nil
        if startsNewTool {
            closeAssistantBubble()
        }
        return toolProjector.upsert(
            in: finalizeAssistant(closedAssistantID, in: transcript),
            activeTodos: activeTodos,
            event: event
        )
    }

    private func finalizeAssistant(
        _ id: String?,
        in transcript: [TranscriptEntry]
    ) -> [TranscriptEntry] {
        guard let id else {
            return transcript
        }
        return transcript.map { entry in
            guard case let .message(message) = entry,
                  message.id == id else {
                return entry
            }
            return .message(
                finalizeAssistant(message, authoritativeContent: nil)
            )
        }
    }

    private func finalizeAssistant(
        _ message: TranscriptMessage,
        authoritativeContent: String?
    ) -> TranscriptMessage {
        let raw = authoritativeContent ?? message.content
        let parsed = parseMessageContent(raw)
        let hasDeliveryDirective =
            raw.range(of: "[[audio_as_voice]]", options: .caseInsensitive)
                != nil
            || raw.range(of: "[[as_document]]", options: .caseInsensitive)
                != nil
        if authoritativeContent == nil,
           parsed.attachments.isEmpty,
           parsed.inlineImages.isEmpty,
           parsed.imagePaths.isEmpty,
           !hasDeliveryDirective {
            return message
        }
        var finalized = message
        finalized.content = parsed.text
        if !parsed.inlineImages.isEmpty {
            finalized.images = parsed.inlineImages.map {
                MessageImage(base64: $0, label: "image")
            }
        }
        finalized.attachments = parsed.attachments
        return finalized
    }

    private func ensureAssistant(
        _ id: String,
        in transcript: [TranscriptEntry]
    ) -> [TranscriptEntry] {
        guard !transcript.contains(where: { $0.id == id }) else {
            return transcript
        }
        return transcript + [
            .message(
                TranscriptMessage(
                    id: id,
                    role: .assistant,
                    content: ""
                )
            ),
        ]
    }
}
