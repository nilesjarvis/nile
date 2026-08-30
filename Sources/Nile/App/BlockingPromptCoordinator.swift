import Foundation

struct BlockingPromptRecord {
    let id: String
    let gatewayID: String
    let liveSessionID: String
    var storedSessionID: String?
    let requestID: String?
    var prompt: TranscriptBlockingPrompt
    let arrivalOrder: Int64
    let expiresAtMilliseconds: Int64?
}

/// Owns one-shot Hermes input requests without ever retaining response values.
@MainActor
final class BlockingPromptCoordinator {
    private let monotonicMilliseconds: () -> Int64
    var records: [BlockingPromptRecord] = []
    private var storedIDs: [String: String] = [:]
    private var sequence: Int64 = 0
    private var statusPollGeneration: Int64 = 0

    init(
        monotonicMilliseconds: @escaping () -> Int64 = {
            Int64(ProcessInfo.processInfo.systemUptime * 1_000)
        }
    ) {
        self.monotonicMilliseconds = monotonicMilliseconds
    }

    func handleEvent(
        _ event: HermesStreamEvent,
        gatewayID: String?,
        fallbackStoredSessionID: String?
    ) -> BlockingPromptEventResult {
        guard let request = BlockingPromptEventRequest(event) else {
            return .notHandled
        }
        guard let gatewayID else {
            return .consumed
        }
        if let requestID = request.requestID,
           let kind = request.deduplicationKind,
           hasRequest(
               gatewayID: gatewayID,
               requestID: requestID,
               kind: kind
           ) {
            return .consumed
        }

        sequence += 1
        let prompt = request.makePrompt(sequence: sequence)
        let storedSessionID =
            storedIDs[request.liveSessionID] ?? fallbackStoredSessionID
        records.append(
            BlockingPromptRecord(
                id: prompt.id,
                gatewayID: gatewayID,
                liveSessionID: request.liveSessionID,
                storedSessionID: storedSessionID,
                requestID: request.requestID,
                prompt: prompt,
                arrivalOrder: sequence,
                expiresAtMilliseconds: BlockingPromptPolicy
                    .timeoutMilliseconds(for: prompt.kind)
                    .map { monotonicMilliseconds() + $0 }
            )
        )
        return .added(liveSessionID: request.liveSessionID)
    }

    func bindSession(
        gatewayID: String,
        liveSessionID: String,
        storedSessionID: String?,
        turnInFlight: Bool
    ) {
        guard let storedSessionID else {
            return
        }
        storedIDs[liveSessionID] = storedSessionID
        for index in records.indices
        where records[index].gatewayID == gatewayID
            && records[index].liveSessionID == liveSessionID {
            records[index].storedSessionID = storedSessionID
        }

        records.removeAll {
            $0.gatewayID == gatewayID
                && $0.storedSessionID == storedSessionID
                && $0.liveSessionID != liveSessionID
        }
        storedIDs = storedIDs.filter {
            $0.key == liveSessionID || $0.value != storedSessionID
        }
        if !turnInFlight {
            records.removeAll {
                $0.gatewayID == gatewayID
                    && $0.liveSessionID == liveSessionID
                    && $0.storedSessionID == storedSessionID
            }
        }
    }

    func visiblePrompts(
        gatewayID: String,
        liveSessionID: String,
        storedSessionID: String?
    ) -> [TranscriptBlockingPrompt] {
        records
            .filter {
                $0.gatewayID == gatewayID
                    && $0.liveSessionID == liveSessionID
                    && $0.storedSessionID == storedSessionID
            }
            .sorted { $0.arrivalOrder < $1.arrivalOrder }
            .map(\.prompt)
    }

    func finalizeRuntime(
        gatewayID: String,
        liveSessionID: String,
        message: String
    ) {
        for index in records.indices
        where records[index].gatewayID == gatewayID
            && records[index].liveSessionID == liveSessionID
            && records[index].prompt.status.isOpen {
            markUnavailable(index: index, message: message)
        }
    }

    func finalizeGateway(gatewayID: String, message: String) {
        for index in records.indices
        where records[index].gatewayID == gatewayID
            && records[index].prompt.status.isOpen {
            markUnavailable(index: index, message: message)
        }
    }

    func beginStatusPoll() -> BlockingPromptStatusPollToken {
        statusPollGeneration += 1
        return BlockingPromptStatusPollToken(
            generation: statusPollGeneration,
            arrivalWatermark: sequence
        )
    }

    func reconcileStatusPoll(
        token: BlockingPromptStatusPollToken,
        gatewayID: String?,
        currentGatewayID: String?,
        statuses: [String: String]
    ) -> Bool {
        guard token.generation == statusPollGeneration,
              gatewayID == currentGatewayID,
              let gatewayID else {
            return false
        }
        for index in records.indices {
            guard records[index].gatewayID == gatewayID,
                  let storedSessionID = records[index].storedSessionID,
                  records[index].arrivalOrder <= token.arrivalWatermark,
                  records[index].prompt.status.isOpen,
                  !BlockingPromptPolicy.isRuntimeBusy(
                      status: statuses[storedSessionID]
                  ) else {
                continue
            }
            markUnavailable(
                index: index,
                message: "This request is no longer waiting."
            )
        }
        return true
    }

    func refreshPresentation(gatewayID: String?) {
        let now = monotonicMilliseconds()
        for index in records.indices {
            if let expires = records[index].expiresAtMilliseconds,
               expires <= now,
               records[index].prompt.status.isOpen {
                markUnavailable(index: index, message: "This request timed out.")
            }
        }
        for index in records.indices where records[index].gatewayID == gatewayID {
            records[index].prompt.actionable = actionable(record: records[index])
        }
    }

    func project(
        gatewayID: String?,
        liveSessionID: String?,
        storedSessionID: String?,
        transcript: [TranscriptEntry]
    ) -> (
        transcript: [TranscriptEntry],
        sessionsNeedingInput: Set<String>
    ) {
        let visible: [TranscriptBlockingPrompt]
        if let gatewayID, let liveSessionID {
            visible = visiblePrompts(
                gatewayID: gatewayID,
                liveSessionID: liveSessionID,
                storedSessionID: storedSessionID
            )
        } else {
            visible = []
        }

        let merged = BlockingPromptPolicy.merge(
            visiblePrompts: visible,
            into: transcript
        )

        let attention: Set<String>
        if let gatewayID {
            attention = Set(
                records.compactMap { record in
                    guard record.gatewayID == gatewayID,
                          record.prompt.status.isOpen else {
                        return nil
                    }
                    return record.storedSessionID
                }
            )
        } else {
            attention = []
        }
        return (merged, attention)
    }

    func clearRuntimeRecords() {
        records.removeAll()
        storedIDs.removeAll()
        statusPollGeneration += 1
    }

    private func hasRequest(
        gatewayID: String,
        requestID: String,
        kind: BlockingPromptKind
    ) -> Bool {
        records.contains {
            $0.gatewayID == gatewayID
                && $0.requestID == requestID
                && $0.prompt.kind == kind
        }
    }

    func markUnavailable(index: Int, message: String) {
        records[index].prompt.status = .unavailable
        records[index].prompt.statusMessage = message
        records[index].prompt.actionable = false
    }
}
