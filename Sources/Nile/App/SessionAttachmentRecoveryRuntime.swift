import Foundation

/// Owns process-relaunch acceptance and quarantine decisions for protected
/// photo drafts and mutation markers.
///
/// This runtime composes protected persistence and read-only navigation. It
/// decides whether interrupted work is accepted, recoverable, or still
/// quarantined, then delegates composer reconstruction to a same-runtime
/// extension. It never consumes the Hermes event stream.
@MainActor
final class SessionAttachmentRecoveryRuntime {
    typealias CommitGuard = @MainActor @Sendable () -> Bool
    typealias EditFailureHandler = @MainActor @Sendable
        (RecoveredEditFailure) -> Void

    struct DraftPresentation: Equatable, Sendable {
        let owner: ComposerDraftOwner
        let composer: String
        let attachments: [PendingAttachment]
    }

    struct RecoveredEditFailure: Equatable, Sendable {
        let owner: ComposerDraftOwner
        let attemptedText: String
        let fallbackText: String
    }

    enum QuarantineReason: Equatable, Sendable {
        case unresolvedRuntime
        case recoveryWriteFailed
    }

    enum UnavailableDraftResolution: Equatable, Sendable {
        case none
        case stale
        case recovered(DraftPresentation)
        case quarantined(
            owner: ComposerDraftOwner,
            reason: QuarantineReason
        )
    }

    let composerRuntime: SessionComposerRuntime
    let draftPersistenceRuntime: SessionDraftPersistenceRuntime
    let attachmentPersistenceRuntime: SessionAttachmentPersistenceRuntime
    private let navigationRuntime: SessionNavigationRuntime

    init(
        composerRuntime: SessionComposerRuntime,
        draftPersistenceRuntime: SessionDraftPersistenceRuntime,
        attachmentPersistenceRuntime: SessionAttachmentPersistenceRuntime,
        navigationRuntime: SessionNavigationRuntime
    ) {
        self.composerRuntime = composerRuntime
        self.draftPersistenceRuntime = draftPersistenceRuntime
        self.attachmentPersistenceRuntime = attachmentPersistenceRuntime
        self.navigationRuntime = navigationRuntime
    }

    /// Restores protected photo state, folds any ordinary text record into
    /// recovered marker authority, and rebuilds the in-memory projections.
    func restore(
        gatewayID: String,
        commitGuard: @escaping CommitGuard
    ) async throws {
        let restored = try await attachmentPersistenceRuntime.restore(
            gatewayID: gatewayID
        )
        for owner in restored.recoveredOwners {
            await consolidateComposerOwnership(
                owner: owner,
                commitGuard: commitGuard
            )
            restoreRecoveredMarkers(owner: owner)
        }
    }

    /// Returns true while the owner must remain closed because its old Hermes
    /// runtime still exists and could consume an interrupted image queue.
    func reconcileStoredMutations(
        owner: ComposerDraftOwner,
        navigationOwner: SessionNavigationRuntime.GatewayOwner
    ) async throws -> Bool {
        let markers = attachmentPersistenceRuntime.markers(for: owner)
        guard !markers.isEmpty else {
            attachmentPersistenceRuntime.releaseQuarantine(owner: owner)
            return false
        }
        let unresolvedMarkers = markers.filter {
            $0.stage != .draftRecovered
        }
        for marker in unresolvedMarkers {
            if try await navigationRuntime.liveRuntimeStatus(
                liveSessionID: marker.liveSessionID,
                owner: navigationOwner
            ) != nil {
                attachmentPersistenceRuntime.quarantine(owner: owner)
                return true
            }
        }

        let needsHistory = unresolvedMarkers.contains {
            $0.stage == .promptPending || $0.stage == .quarantineOnly
        }
        let history = needsHistory
            ? try await navigationRuntime.readStoredSession(
                storedSessionID: owner.storedSessionID,
                owner: navigationOwner
            )
            : []
        for marker in markers {
            if marker.stage == .draftRecovered {
                continue
            }
            let userMessages = history.filter {
                $0.role.caseInsensitiveCompare("user") == .orderedSame
            }
            let accepted = marker.stage != .uploadPending
                && userMessages.dropFirst(marker.userMessagesBefore).contains {
                    Self.durableHistoryMatchesAttachment(
                        raw: $0.text,
                        input: marker.input
                    )
                }
            if accepted {
                let cleared = try await attachmentPersistenceRuntime
                    .clearMutationPreservingError(marker)
                guard cleared else {
                    attachmentPersistenceRuntime.quarantine(owner: owner)
                    return true
                }
                continue
            }

            let recoveredMarker = marker.advancing(to: .draftRecovered)
            let recovered = try await attachmentPersistenceRuntime
                .advanceMutationPreservingError(
                    from: marker,
                    to: recoveredMarker
                )
            guard recovered else {
                attachmentPersistenceRuntime.quarantine(owner: owner)
                return true
            }
        }
        restoreRecoveredMarkers(owner: owner)
        attachmentPersistenceRuntime.releaseQuarantine(owner: owner)
        return false
    }

    /// Resolves a protected draft whose stored session is absent from the
    /// directory. The model applies the returned presentation only when this
    /// method's generation guard remains current.
    func resolveUnavailableDraft(
        preferredSessionID: String?,
        gatewayID: String,
        navigationOwner: SessionNavigationRuntime.GatewayOwner,
        commitGuard: @escaping CommitGuard
    ) async -> UnavailableDraftResolution {
        let markerOwners = attachmentPersistenceRuntime.markerOwners(
            gatewayID: gatewayID
        )
        let composerOwners = composerRuntime.nonemptyOwners(
            gatewayID: gatewayID
        )
        let attachmentOwners = attachmentPersistenceRuntime.draftOwners(
            gatewayID: gatewayID
        )
        let owners = Set(markerOwners + composerOwners + attachmentOwners)
        let owner = preferredSessionID.flatMap { preferred in
            owners.first { $0.storedSessionID == preferred }
        } ?? owners.sorted {
            $0.storedSessionID < $1.storedSessionID
        }.first
        guard let owner else {
            return .none
        }
        let markers = attachmentPersistenceRuntime.markers(for: owner)

        for marker in markers where marker.stage != .draftRecovered {
            do {
                if try await navigationRuntime.liveRuntimeStatus(
                    liveSessionID: marker.liveSessionID,
                    owner: navigationOwner
                ) != nil {
                    guard commitGuard() else {
                        return .stale
                    }
                    attachmentPersistenceRuntime.quarantine(owner: owner)
                    return .quarantined(
                        owner: owner,
                        reason: .unresolvedRuntime
                    )
                }
            } catch {
                guard commitGuard() else {
                    return .stale
                }
                attachmentPersistenceRuntime.quarantine(owner: owner)
                return .quarantined(
                    owner: owner,
                    reason: .unresolvedRuntime
                )
            }
            guard commitGuard() else {
                return .stale
            }
            let recovered = marker.advancing(to: .draftRecovered)
            let accepted = await attachmentPersistenceRuntime
                .advanceMutation(from: marker, to: recovered)
            guard commitGuard() else {
                return .stale
            }
            guard accepted else {
                attachmentPersistenceRuntime.quarantine(owner: owner)
                return .quarantined(
                    owner: owner,
                    reason: .recoveryWriteFailed
                )
            }
        }

        guard commitGuard() else {
            return .stale
        }
        restoreRecoveredMarkers(owner: owner)
        attachmentPersistenceRuntime.releaseQuarantine(owner: owner)
        return .recovered(
            DraftPresentation(
                owner: owner,
                composer: composerRuntime.text(for: owner),
                attachments: attachmentPersistenceRuntime.draft(for: owner)
            )
        )
    }

    private static func durableHistoryMatchesAttachment(
        raw: String,
        input: String
    ) -> Bool {
        let expected = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let parsed = parseMessageContent(raw)
        let withoutNativeImages = parsed.text.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) != "[image]"
        }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !expected.isEmpty {
            return withoutNativeImages == expected
                || raw.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).hasSuffix("\n\n\(expected)")
        }
        return !parsed.imagePaths.isEmpty
            || !parsed.inlineImages.isEmpty
            || raw.contains("[image]")
            || raw.contains("[The user attached an image")
            || raw.contains("vision_analyze using image_url:")
    }
}
