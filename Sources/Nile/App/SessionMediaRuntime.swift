import Foundation
import Observation

/// Owns attachment-read, cache, viewer, and preview-operation authority.
///
/// Full-size viewer execution remains here. A same-runtime extension performs
/// preview reconciliation against this source's one repository capability and
/// task/failure registries without introducing another observable authority.
@MainActor
@Observable
final class SessionMediaRuntime {
    struct Owner: Equatable, Hashable, Sendable {
        let gatewayGeneration: Int
        let displayGeneration: Int
        let gatewayID: String
        let storedSessionID: String
    }

    struct PreviewUpdate: Equatable, Sendable {
        let owner: Owner
        let messageID: String
        let attachmentIndex: Int
        let path: String
        let attachment: MessageAttachment
    }

    struct PreviewOccurrence: Sendable {
        let messageID: String
        let attachmentIndex: Int
        let attachment: MessageAttachment
    }

    struct PreviewKey: Equatable, Hashable, Sendable {
        let owner: Owner
        let messageID: String
        let attachmentIndex: Int
        let path: String
    }

    struct PreviewOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    typealias OwnerValidator = @MainActor @Sendable (Owner) -> Bool
    typealias ErrorHandler = @MainActor @Sendable (String?) -> Void
    typealias PreviewHandler = @MainActor @Sendable (
        PreviewUpdate
    ) -> Void
    typealias ReconcileHandler = @MainActor @Sendable () -> Void

    static let viewerMaximumBytes: Int64 = 32 * 1_024 * 1_024
    static let previewMaximumBytes: Int64 = 2 * 1_024 * 1_024
    static let retainedPreviewCount = 8
    static let concurrentPreviewCount = 2

    private(set) var openedAttachment: CachedAttachment?
    private(set) var isOpeningAttachment = false

    @ObservationIgnored
    let repository: (any HermesAttachmentReading)?
    @ObservationIgnored
    private let cache: any AttachmentCaching
    @ObservationIgnored
    private var openingTask: Task<Void, Never>?
    @ObservationIgnored
    private var openingGeneration: Int64 = 0
    @ObservationIgnored
    var previewOperations: [PreviewKey: PreviewOperation] = [:]
    @ObservationIgnored
    var failedPreviewKeys: Set<PreviewKey> = []

    init(
        repository: (any HermesAttachmentReading)?,
        cache: any AttachmentCaching
    ) {
        self.repository = repository
        self.cache = cache
    }

    isolated deinit {
        openingTask?.cancel()
        previewOperations.values.forEach { $0.task.cancel() }
    }

    func open(
        path: String,
        owner: Owner?,
        isCurrentOwner: @escaping OwnerValidator,
        onError: @escaping ErrorHandler
    ) {
        guard !path.isBlank,
              let repository,
              let owner,
              !isOpeningAttachment else {
            return
        }
        openingGeneration &+= 1
        let generation = openingGeneration
        openingTask?.cancel()
        isOpeningAttachment = true
        onError(nil)
        let cache = cache
        openingTask = Task { [weak self] in
            do {
                let downloaded = try await repository.downloadAttachment(
                    path: path,
                    maxBytes: Self.viewerMaximumBytes
                )
                try Task.checkCancellation()
                guard let self,
                      self.openingGeneration == generation else {
                    return
                }
                guard isCurrentOwner(owner) else {
                    self.finishOpening(generation: generation)
                    return
                }
                let cached = try await cache.prepare(downloaded)
                guard self.openingGeneration == generation else {
                    return
                }
                guard isCurrentOwner(owner) else {
                    self.finishOpening(generation: generation)
                    return
                }
                self.openedAttachment = cached
                self.finishOpening(generation: generation)
            } catch is CancellationError {
                self?.finishOpening(generation: generation)
            } catch {
                guard let self,
                      self.openingGeneration == generation else {
                    return
                }
                if isCurrentOwner(owner) {
                    let detail = error.localizedDescription
                    onError(
                        detail.isBlank
                            ? "Could not open that attachment."
                            : "Could not open attachment: \(detail)"
                    )
                }
                self.finishOpening(generation: generation)
            }
        }
    }

    func dismissOpenedAttachment() {
        openedAttachment = nil
    }

    func cancelOpening() {
        openingGeneration &+= 1
        openingTask?.cancel()
        openingTask = nil
        isOpeningAttachment = false
    }

    func reset() {
        cancelOpening()
        openedAttachment = nil
        resetPreviews()
    }

    private func finishOpening(generation: Int64) {
        guard openingGeneration == generation else {
            return
        }
        openingTask = nil
        isOpeningAttachment = false
    }
}
