extension NileAccessibilityID {
    static let delegationOverview = "niles.delegation.overview"

    static func delegationTranscriptGroup(_ id: String) -> String {
        "niles.delegation.group.\(id)"
    }

    static func delegationToggle(_ id: String) -> String {
        "niles.delegation.toggle.\(id)"
    }

    static func delegationAgentRow(_ id: String) -> String {
        "niles.delegation.agent.\(id)"
    }

    static func delegationAgentDetail(_ id: String) -> String {
        "niles.delegation.detail.\(id)"
    }

    static func delegationStop(_ id: String) -> String {
        "niles.delegation.stop.\(id)"
    }

    static func delegationOpenChild(_ id: String) -> String {
        "niles.delegation.open_child.\(id)"
    }
}
