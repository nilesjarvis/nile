import Foundation

/// Owns the ordinary text-draft lifecycle across the protected persistence and
/// visibility-independent composer runtimes.
///
/// This runtime restores protected records into the composer projection,
/// captures and retires exact outbound claims, persists admission-ordered
/// failure recovery, and routes offscreen notices. It returns immutable
/// presentation changes to `SessionListModel` and never consumes stream events.
@MainActor
final class SessionDraftLifecycleRuntime {
    typealias FailureHandler = @MainActor @Sendable (Failure) -> Void
    typealias ProjectionHandler = @MainActor @Sendable
        (ComposerProjection) -> Void

    struct Failure: Equatable, Sendable {
        let owner: ComposerDraftOwner
        let message: String
    }

    struct ComposerProjection: Equatable, Sendable {
        let owner: ComposerDraftOwner
        let text: String
    }

    struct RecoveryPresentation: Equatable, Sendable {
        let owner: ComposerDraftOwner
        let restoredText: String
        let notice: String
        let uncertain: Bool
    }

    enum NoticeChannel: Equatable, Sendable {
        case operation
        case steer
    }

    enum RecoveryResolution: Equatable, Sendable {
        case stale
        case deferred
        case visible(RecoveryPresentation)
    }

    private let composerRuntime: SessionComposerRuntime
    private let persistenceRuntime: SessionDraftPersistenceRuntime

    init(
        composerRuntime: SessionComposerRuntime,
        persistenceRuntime: SessionDraftPersistenceRuntime
    ) {
        self.composerRuntime = composerRuntime
        self.persistenceRuntime = persistenceRuntime
    }

    func record(for owner: ComposerDraftOwner) -> PersistedComposerDraft? {
        persistenceRuntime.record(for: owner)
    }

    @discardableResult
    func storeText(
        owner: ComposerDraftOwner,
        text: String,
        onFailure: @escaping FailureHandler
    ) -> PersistedComposerDraft {
        persistenceRuntime.storeText(
            owner: owner,
            text: text,
            onFailure: persistenceFailureHandler(onFailure)
        )
    }

    func flushAll(onFailure: @escaping FailureHandler) {
        persistenceRuntime.flushAll(
            onFailure: persistenceFailureHandler(onFailure)
        )
    }

    func captureClaim(
        owner: ComposerDraftOwner,
        fallbackText: String
    ) -> PersistedComposerDraft? {
        persistenceRuntime.captureClaim(
            owner: owner,
            fallbackText: fallbackText
        )
    }

    func flushClaim(
        owner: ComposerDraftOwner,
        claim: PersistedComposerDraft?
    ) async -> Bool {
        await persistenceRuntime.flushClaim(owner: owner, claim: claim)
    }

    /// Retires one exact protected claim and owns the matching in-memory
    /// composer clear/rollback. Only accepted projection changes are returned
    /// to the model for visible presentation.
    func retireClaim(
        owner: ComposerDraftOwner,
        claim: PersistedComposerDraft?,
        onProjection: @escaping ProjectionHandler,
        onFailure: @escaping FailureHandler
    ) async {
        await persistenceRuntime.retireClaim(
            owner: owner,
            claim: claim,
            onRetiring: { [weak self] claimText in
                guard let self,
                      self.composerRuntime.clearIfEqual(
                          owner: owner,
                          text: claimText
                      ) else {
                    return
                }
                onProjection(
                    ComposerProjection(owner: owner, text: "")
                )
            },
            onRollback: { [weak self] claimText in
                guard let self,
                      self.composerRuntime.restoreIfEmpty(
                          owner: owner,
                          text: claimText
                      ) else {
                    return
                }
                onProjection(
                    ComposerProjection(owner: owner, text: claimText)
                )
            },
            onFailure: persistenceFailureHandler(onFailure)
        )
    }

    /// Restores only newly accepted protected records and seeds their exact
    /// per-owner composer projections.
    @discardableResult
    func restore(gatewayID: String) async throws -> [ComposerProjection] {
        let records = try await persistenceRuntime.restore(
            gatewayID: gatewayID
        )
        return records.map { record in
            composerRuntime.seed(
                owner: record.owner,
                text: record.text,
                restored: !record.text.isEmpty
            )
            return ComposerProjection(
                owner: record.owner,
                text: record.text
            )
        }
    }

    /// Applies one admission-ordered failed input, immediately schedules its
    /// protected record, and either defers the notice to the owner or returns a
    /// visible presentation for the model to apply.
    func recover(
        token: SessionComposerRuntime.RecoveryToken,
        failedInput: String,
        notice: String,
        uncertain: Bool,
        noticeChannel: NoticeChannel,
        isVisible: Bool,
        onFailure: @escaping FailureHandler
    ) -> RecoveryResolution {
        guard let restored = composerRuntime.recover(
            token,
            failedInput: failedInput
        ) else {
            return .stale
        }
        persistenceRuntime.persistRecovered(
            owner: token.owner,
            text: restored,
            onFailure: persistenceFailureHandler(onFailure)
        )
        guard isVisible else {
            switch noticeChannel {
            case .operation:
                composerRuntime.rememberOperationNotice(
                    owner: token.owner,
                    message: notice,
                    uncertain: uncertain
                )
            case .steer:
                composerRuntime.rememberSteerNotice(
                    owner: token.owner,
                    message: notice,
                    uncertain: uncertain
                )
            }
            return .deferred
        }
        return .visible(
            RecoveryPresentation(
                owner: token.owner,
                restoredText: restored,
                notice: notice,
                uncertain: uncertain
            )
        )
    }

    private func persistenceFailureHandler(
        _ handler: @escaping FailureHandler
    ) -> SessionDraftPersistenceRuntime.FailureHandler {
        { owner, message in
            handler(Failure(owner: owner, message: message))
        }
    }
}
