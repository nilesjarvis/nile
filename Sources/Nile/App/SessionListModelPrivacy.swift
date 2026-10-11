import Foundation

@MainActor
extension SessionListModel {
    func stopForSharingConsentWithdrawal() {
        flushDrafts()
        runtimes.eventRuntime.suspendDelivery()
        applyVisibleConnectionLoss(
            message: "Sharing permission was withdrawn. Connect again to continue.",
            retryable: false,
            notifyGateway: false
        )
        // Preserve drafts and uncertain photo markers, but stop every local
        // operation before the gateway close crosses an asynchronous boundary.
        runtimes.lifecycleRuntime.hideSurface()
        runtimes.turnRuntime.reset()
        runtimes.attachmentRuntime.reset()
        runtimes.blockingPromptRuntime.reset()
        runtimes.commandRuntime.resetGateway()
        runtimes.mediaRuntime.reset()
        outboundTasks.values.forEach { $0.cancel() }
        outboundTasks.removeAll()
        isAttaching = false
        syncBlockingPromptUI()
    }
}
