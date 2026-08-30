import Foundation

/// Owns debounced protected-draft writes behind the single persistence runtime
/// store, record mirror, task registry, and timestamp authority.
@MainActor
extension SessionDraftPersistenceRuntime {
    @discardableResult
    func storeText(
        owner: ComposerDraftOwner,
        text: String,
        debounce: Bool = true,
        onFailure: @escaping FailureHandler
    ) -> PersistedComposerDraft {
        let record = makeRecord(owner: owner, text: text)
        records[owner] = record
        scheduleWrite(
            owner: owner,
            record: record,
            debounce: debounce,
            onFailure: onFailure
        )
        return record
    }

    func flushAll(onFailure: @escaping FailureHandler) {
        for (owner, record) in records {
            scheduleWrite(
                owner: owner,
                record: record,
                debounce: false,
                onFailure: onFailure
            )
        }
    }

    func persistRecovered(
        owner: ComposerDraftOwner,
        text: String,
        onFailure: @escaping FailureHandler
    ) {
        guard store != nil else {
            return
        }
        _ = storeText(
            owner: owner,
            text: text,
            debounce: false,
            onFailure: onFailure
        )
    }

    private func scheduleWrite(
        owner: ComposerDraftOwner,
        record: PersistedComposerDraft,
        debounce: Bool,
        onFailure: @escaping FailureHandler
    ) {
        writeOperations.removeValue(forKey: owner)?.task.cancel()
        guard let store else {
            return
        }
        let operationID = UUID()
        let task = Task { [weak self] in
            if debounce {
                do {
                    try await Task.sleep(for: .milliseconds(350))
                } catch {
                    self?.finishWrite(owner: owner, id: operationID)
                    return
                }
            }
            guard !Task.isCancelled else {
                self?.finishWrite(owner: owner, id: operationID)
                return
            }
            do {
                let accepted = try await store.update(record)
                guard !Task.isCancelled else {
                    self?.finishWrite(owner: owner, id: operationID)
                    return
                }
                self?.finishWrite(
                    owner: owner,
                    id: operationID,
                    failure: accepted
                        ? nil
                        : "Nile could not save the latest draft revision.",
                    onFailure: onFailure
                )
            } catch is CancellationError {
                self?.finishWrite(owner: owner, id: operationID)
            } catch {
                self?.finishWrite(
                    owner: owner,
                    id: operationID,
                    failure:
                        "Nile could not save this draft: \(error.localizedDescription)",
                    onFailure: onFailure
                )
            }
        }
        writeOperations[owner] = WriteOperation(
            id: operationID,
            task: task
        )
    }

    private func finishWrite(
        owner: ComposerDraftOwner,
        id: UUID,
        failure: String? = nil,
        onFailure: FailureHandler? = nil
    ) {
        guard writeOperations[owner]?.id == id else {
            return
        }
        writeOperations.removeValue(forKey: owner)
        if let failure, records[owner] != nil {
            onFailure?(owner, failure)
        }
    }
}
