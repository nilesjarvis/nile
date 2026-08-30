extension NileAccessibilityID {
    static let transcript = "niles.transcript"
    static let transcriptJumpToBottom = "niles.transcript.jump_to_bottom"
    static let markdownTable = "niles.markdown.table"
    static let sessionLaunchpad = "niles.session.launchpad"
    static let activePlan = "niles.transcript.active_plan"

    static func sessionLaunchpadQuickStart(_ index: Int) -> String {
        "niles.session.launchpad.quick_start.\(index)"
    }

    static func transcriptMessage(_ id: String) -> String {
        "niles.transcript.message.\(id)"
    }

    static func transcriptTool(_ id: String) -> String {
        "niles.transcript.tool.\(id)"
    }

    static func markdownTableHeader(_ column: Int) -> String {
        "niles.markdown.table.header.\(column)"
    }

    static func markdownTableCell(row: Int, column: Int) -> String {
        "niles.markdown.table.cell.\(row).\(column)"
    }

    static func toolActivityGroup(_ id: String) -> String {
        "niles.transcript.tool_group.\(id)"
    }

    static func copyAssistantResponse(_ id: String) -> String {
        "niles.transcript.copy.\(id)"
    }

    static func systemNotice(_ id: String) -> String {
        "niles.transcript.system.\(id)"
    }

    static func messageAttachment(_ path: String) -> String {
        "niles.transcript.attachment.\(path)"
    }
}
