extension NileAccessibilityID {
    static let composer = "niles.composer"
    static let composerSend = "niles.composer.send"
    static let composerStop = "niles.composer.stop"
    static let composerContextScale = "niles.composer.context_scale"
    static let composerUsage = "niles.composer.usage"
    static let contextSheet = "niles.context.sheet"
    static let contextBreakdown = "niles.context.breakdown"
    static let statsButton = "niles.stats.button"
    static let statsSheet = "niles.stats.sheet"
    static let statsRefresh = "niles.stats.refresh"
    static let statsHeatmap = "niles.stats.heatmap"
    static let composerModelName = "niles.composer.model_name"
    static let composerModelMenuStatus = "niles.composer.model_menu.status"
    static let composerModelSettings = "niles.composer.model_menu.settings"
    static let composerSpeakReplies = "niles.composer.speak_replies"
    static let talkEntry = "niles.talk.entry"
    static let talkSurface = "niles.talk.surface"
    static let talkStatus = "niles.talk.status"
    static let talkOrb = "niles.talk.orb"
    static let talkPrimary = "niles.talk.primary"
    static let talkPause = "niles.talk.pause"
    static let talkResume = "niles.talk.resume"
    static let talkInterruptSpeech = "niles.talk.interrupt_speech"
    static let talkViewTranscript = "niles.talk.view_transcript"
    static let talkClose = "niles.talk.close"
    static let talkEnd = "niles.talk.end"
    static let talkError = "niles.talk.error"
    static let talkBlockingPrompt = "niles.talk.blocking_prompt"
    static let attachPhoto = "niles.composer.attach_photo"
    static let attachmentStrip = "niles.composer.attachments"
    static let attachmentProgress = "niles.composer.attachment_progress"
    static let attachmentPreview = "niles.attachment.preview"
    static let shareAttachment = "niles.attachment.share"
    static let composerSurface = "niles.composer.surface"
    static let turnStatus = "niles.turn.status"

    static func pendingAttachment(_ id: String) -> String {
        "niles.composer.attachment.\(id)"
    }

    static func removeAttachment(_ id: String) -> String {
        "niles.composer.attachment.remove.\(id)"
    }

    static func statsPeriod(_ days: Int) -> String {
        "niles.stats.period.\(days)"
    }
}
