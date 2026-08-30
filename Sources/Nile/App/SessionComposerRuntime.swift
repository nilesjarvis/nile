import Foundation

/// Owns the visibility-independent composer projection and outbound recovery
/// ordering for every gateway/session owner.
///
/// `SessionDraftLifecycleRuntime` composes this projection with protected text
/// persistence. `SessionListModel` retains the currently rendered composer and
/// transcript presentation. This runtime keeps the durable projection's
/// in-memory peer, admission-ordered failure recovery, one-shot restoration
/// flags, and deferred notices in one state machine.
@MainActor
final class SessionComposerRuntime {
    struct Notice: Equatable, Sendable {
        let message: String
        let uncertain: Bool
        var showBanner = true
    }

    struct RecoveryToken: Sendable {
        let owner: ComposerDraftOwner
        fileprivate let gatewayID: String
        fileprivate let generation: Int64
        fileprivate let sequence: Int64
    }

    private struct OrderedRecovery {
        var failedInputs: [Int64: String]
        var baseDraft: String

        func rendered() -> String {
            SessionComposerRuntime.mergeRecovered(prefix(), with: baseDraft)
        }

        func reconciled(with currentDraft: String) -> OrderedRecovery? {
            let prefix = prefix()
            if currentDraft == prefix {
                return OrderedRecovery(
                    failedInputs: failedInputs,
                    baseDraft: ""
                )
            }
            let separator = "\(prefix)\n\n"
            if currentDraft.hasPrefix(separator) {
                return OrderedRecovery(
                    failedInputs: failedInputs,
                    baseDraft: String(currentDraft.dropFirst(separator.count))
                )
            }
            return nil
        }

        private func prefix() -> String {
            failedInputs
                .sorted { $0.key < $1.key }
                .map(\.value)
                .joined(separator: "\n\n")
        }
    }

    private var drafts: [ComposerDraftOwner: String] = [:]
    private var restoredOwners: Set<ComposerDraftOwner> = []
    private var orderedRecoveries: [ComposerDraftOwner: OrderedRecovery] = [:]
    private var steerNotices: [ComposerDraftOwner: Notice] = [:]
    private var operationNotices: [ComposerDraftOwner: Notice] = [:]
    private var gatewayGenerations: [String: Int64] = [:]
    private var sequence: Int64 = 0

    func text(for owner: ComposerDraftOwner) -> String {
        drafts[owner] ?? ""
    }

    func update(owner: ComposerDraftOwner, text: String) {
        drafts[owner] = text
        reconcileRecovery(owner: owner, text: text)
    }

    /// Replaces authoritative recovery state without treating it as a user
    /// edit of an admission-ordered failed-input projection.
    func replace(owner: ComposerDraftOwner, text: String) {
        drafts[owner] = text
    }

    func seed(
        owner: ComposerDraftOwner,
        text: String,
        restored: Bool = false
    ) {
        drafts[owner] = text
        if restored, !text.isEmpty {
            restoredOwners.insert(owner)
        } else {
            restoredOwners.remove(owner)
        }
    }

    /// Claims the visible draft for an outbound operation without invalidating
    /// its already-issued recovery token.
    func claim(owner: ComposerDraftOwner) {
        drafts[owner] = ""
        orderedRecoveries.removeValue(forKey: owner)
        steerNotices.removeValue(forKey: owner)
        operationNotices.removeValue(forKey: owner)
    }

    func migrate(
        from sourceOwner: ComposerDraftOwner,
        to targetOwner: ComposerDraftOwner,
        text: String
    ) {
        drafts.removeValue(forKey: sourceOwner)
        restoredOwners.remove(sourceOwner)
        update(owner: targetOwner, text: text)
    }

    func nonemptyOwners(gatewayID: String) -> [ComposerDraftOwner] {
        drafts.compactMap { owner, text in
            owner.gatewayID == gatewayID && !text.isEmpty ? owner : nil
        }
    }

    func clearIfEqual(owner: ComposerDraftOwner, text: String) -> Bool {
        guard drafts[owner] == text else {
            return false
        }
        drafts[owner] = ""
        return true
    }

    func restoreIfEmpty(owner: ComposerDraftOwner, text: String) -> Bool {
        guard self.text(for: owner).isEmpty else {
            return false
        }
        drafts[owner] = text
        return true
    }

    func consumeRestored(owner: ComposerDraftOwner) -> Bool {
        restoredOwners.remove(owner) != nil
    }

    func capture(_ owner: ComposerDraftOwner) -> RecoveryToken {
        sequence += 1
        return RecoveryToken(
            owner: owner,
            gatewayID: owner.gatewayID,
            generation: gatewayGenerations[owner.gatewayID, default: 0],
            sequence: sequence
        )
    }

    func isCurrent(_ token: RecoveryToken) -> Bool {
        gatewayGenerations[token.gatewayID, default: 0] == token.generation
    }

    /// Restores a failed input into the owner projection in admission order,
    /// preserving edits made while remote operations were in flight.
    func recover(_ token: RecoveryToken, failedInput: String) -> String? {
        guard isCurrent(token) else {
            return nil
        }
        let currentDraft = text(for: token.owner)
        let previous = orderedRecoveries[token.owner]?
            .reconciled(with: currentDraft)
            ?? OrderedRecovery(
                failedInputs: [:],
                baseDraft: currentDraft
            )
        let updated = OrderedRecovery(
            failedInputs: previous.failedInputs.merging(
                [token.sequence: failedInput],
                uniquingKeysWith: { _, new in new }
            ),
            baseDraft: previous.baseDraft
        )
        orderedRecoveries[token.owner] = updated
        let restored = updated.rendered()
        drafts[token.owner] = restored
        return restored
    }

    func rememberSteerNotice(
        owner: ComposerDraftOwner,
        message: String,
        uncertain: Bool
    ) {
        Self.remember(
            Notice(message: message, uncertain: uncertain),
            for: owner,
            in: &steerNotices
        )
    }

    func takeSteerNotice(owner: ComposerDraftOwner) -> Notice? {
        steerNotices.removeValue(forKey: owner)
    }

    func rememberOperationNotice(
        owner: ComposerDraftOwner,
        message: String,
        uncertain: Bool,
        showBanner: Bool = true
    ) {
        Self.remember(
            Notice(
                message: message,
                uncertain: uncertain,
                showBanner: showBanner
            ),
            for: owner,
            in: &operationNotices
        )
    }

    func takeOperationNotice(owner: ComposerDraftOwner) -> Notice? {
        operationNotices.removeValue(forKey: owner)
    }

    func invalidateGateway(_ gatewayID: String) {
        gatewayGenerations[gatewayID, default: 0] += 1
    }

    func clearGatewayRecovery(_ gatewayID: String) {
        orderedRecoveries = orderedRecoveries.filter {
            $0.key.gatewayID != gatewayID
        }
        steerNotices = steerNotices.filter {
            $0.key.gatewayID != gatewayID
        }
        operationNotices = operationNotices.filter {
            $0.key.gatewayID != gatewayID
        }
    }

    nonisolated static func mergeRecovered(
        _ recovered: String,
        with currentDraft: String
    ) -> String {
        if recovered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return currentDraft
        }
        if currentDraft.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty {
            return recovered
        }
        if currentDraft == recovered {
            return currentDraft
        }
        return "\(recovered)\n\n\(currentDraft)"
    }

    private func reconcileRecovery(owner: ComposerDraftOwner, text: String) {
        guard let recovery = orderedRecoveries[owner] else {
            return
        }
        orderedRecoveries[owner] = recovery.reconciled(with: text)
    }

    private static func remember(
        _ notice: Notice,
        for owner: ComposerDraftOwner,
        in notices: inout [ComposerDraftOwner: Notice]
    ) {
        if notices[owner]?.uncertain == true, !notice.uncertain {
            return
        }
        notices[owner] = notice
    }
}
