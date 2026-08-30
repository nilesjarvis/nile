extension NileAccessibilityID {
    static let sessionShell = "niles.session.shell"
    static let sessionEmpty = "niles.session.empty"
    static let createSessionEmpty = "niles.session.empty.create"
    static let sessionsStrip = "niles.sessions.strip"
    static let sessionsCreateSwipe = "niles.sessions.create_swipe"
    static let sessionsPullHandle = "niles.sessions.pull_handle"
    static let sessionsNeedsInputCount = "niles.sessions.needs_input_count"
    static let sessionsSheet = "niles.sessions.sheet"
    static let sessionSearchToggle = "niles.session.search.toggle"
    static let sessionSearch = "niles.session.search"
    static let sessionSearchCancel = "niles.session.search.cancel"
    static let newSession = "niles.session.new"
    static let closeSessions = "niles.sessions.close"
    static let sessionError = "niles.session.error"
    static let sessionConnectionStatus = "niles.session.connection_status"
    static let sessionSwitchStatus = "niles.session.switch_status"
    static let sessionSwitchPlaceholder =
        "niles.session.switch_placeholder"
    static let readOnlySession = "niles.session.read_only"
    static let claimSession = "niles.session.claim"
    static let confirmClaimSession = "niles.session.claim.confirm"
    static let claimDialog = "niles.session.claim.dialog"
    static let sessionActionsMenu = "niles.session.actions"
    static let sessionActionsPopover = "niles.session.actions.popover"
    static let sessionSettings = "niles.session.settings"
    static let renameSession = "niles.session.rename"
    static let renameSessionDialog = "niles.session.rename.dialog"
    static let renameSessionTitle = "niles.session.rename.title"
    static let renameSessionError = "niles.session.rename.error"
    static let renameSessionCancel = "niles.session.rename.cancel"
    static let renameSessionSave = "niles.session.rename.save"

    static func sessionPill(_ id: String) -> String {
        "niles.session.pill.\(id)"
    }

    static func sessionRow(_ id: String) -> String {
        "niles.session.row.\(id)"
    }

    static func sessionPin(_ id: String) -> String {
        "niles.session.pin.\(id)"
    }
}
