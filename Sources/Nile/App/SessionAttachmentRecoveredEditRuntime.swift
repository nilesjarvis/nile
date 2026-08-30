import Foundation

/// Owns replaceable recovered-marker edit tasks and their bounded CAS retries.
///
/// The parent persistence runtime supplies narrow protected-store operations and
/// remains the sole owner of durable marker projection.
@MainActor
final class SessionAttachmentRecoveredEditRuntime {
    typealias CommitGuard = @MainActor @Sendable () -> Bool
    typealias Migrate = @MainActor @Sendable (
        [AttachmentMutationMigration],
        @escaping CommitGuard
    ) async -> Bool
    typealias Load = @MainActor @Sendable () async ->
        AttachmentRecoverySnapshot?
    typealias MarkerSource = @MainActor @Sendable
        (ComposerDraftOwner) -> [AttachmentMutationMarker]
    typealias MarkerSink = @MainActor @Sendable
        (AttachmentMutationMarker) -> Void
    typealias Failure = @MainActor @Sendable
        ([AttachmentMutationMarker]) -> Void

    private struct Operation {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var operations: [ComposerDraftOwner: Operation] = [:]

    isolated deinit {
        operations.values.forEach { $0.task.cancel() }
    }

    func schedule(
        owner: ComposerDraftOwner,
        markers initialMarkers: [AttachmentMutationMarker],
        text: String,
        isCurrent: @escaping CommitGuard,
        migrate: @escaping Migrate,
        load: @escaping Load,
        markerSource: @escaping MarkerSource,
        markerSink: @escaping MarkerSink,
        onFailure: @escaping Failure
    ) {
        operations.removeValue(forKey: owner)?.task.cancel()
        let operationID = UUID()
        let markerIDs = initialMarkers.map(\.id)
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            var expected = initialMarkers
            for _ in 0..<3 {
                guard self.isCurrent(owner: owner, id: operationID) else {
                    return
                }
                let migrations = expected.map { marker in
                    AttachmentMutationMigration(
                        expected: marker,
                        replacement: marker.retargeting(
                            storedSessionID: marker.storedSessionID,
                            liveSessionID: marker.liveSessionID,
                            input: text,
                            attachments: marker.attachments
                        )
                    )
                }
                let updated = await migrate(
                    migrations,
                    { [weak self] in
                        self?.isCurrent(
                            owner: owner,
                            id: operationID
                        ) == true && isCurrent()
                    }
                )
                guard self.isCurrent(owner: owner, id: operationID) else {
                    return
                }
                if updated {
                    migrations.forEach { markerSink($0.replacement) }
                    self.finish(owner: owner, id: operationID)
                    return
                }

                guard let snapshot = await load() else {
                    break
                }
                let current = snapshot.markers.filter {
                    markerIDs.contains($0.id)
                        && $0.owner == owner
                        && $0.stage == .draftRecovered
                }.sorted { $0.id < $1.id }
                guard current.count == markerIDs.count else {
                    break
                }
                expected = current
                current.forEach(markerSink)
            }

            guard self.isCurrent(owner: owner, id: operationID) else {
                return
            }
            let durable = markerSource(owner)
            self.finish(owner: owner, id: operationID)
            onFailure(durable)
        }
        operations[owner] = Operation(id: operationID, task: task)
    }

    private func isCurrent(owner: ComposerDraftOwner, id: UUID) -> Bool {
        operations[owner]?.id == id
    }

    private func finish(owner: ComposerDraftOwner, id: UUID) {
        guard operations[owner]?.id == id else {
            return
        }
        operations.removeValue(forKey: owner)
    }
}
