#if DEBUG || NILE_LOCAL_RELEASE
import Foundation

enum SessionListFixture: Equatable {
    case empty
    case showcase
    case visualRegressionBrand
    case visualRegressionMedia
    case visualRegressionAttachments
    case visualRegressionSyntax
    case visualRegressionModelPicker
    case visualRegressionDelegation
    case visualRegressionContext
    case visualRegressionStats
    case transcriptScroll
    case terminalBusy
    case attachments
    case modelPicker
    case goalCreation
    case goalActive
    case blockingClarification
    case blockingApprovals
    case blockingSudo
    case blockingSecret
    case blockingInvalid

    var sessions: [HermesSession] {
        let now = Date().timeIntervalSince1970
        if self == .empty {
            return []
        }
        if self == .visualRegressionMedia {
            return [
                HermesSession(
                    id: "20260716_222504_892479",
                    title: "20260716_222504_892479",
                    preview: nil,
                    source: "cli",
                    messageCount: 3,
                    startedAt: now - 60,
                    lastMessageAt: now - 8
                ),
            ]
        }
        if self == .blockingClarification {
            return [
                HermesSession(
                    id: "brand",
                    title: "Blocking request fixture",
                    preview: nil,
                    source: "niles",
                    messageCount: 0,
                    startedAt: 1,
                    lastMessageAt: nil
                ),
            ]
        }
        if self == .visualRegressionModelPicker
            || self == .visualRegressionAttachments
            || self == .visualRegressionSyntax
            || self == .visualRegressionDelegation
            || self == .visualRegressionContext
            || self == .visualRegressionStats
            || self == .goalCreation
            || self == .goalActive
        {
            return [
                HermesSession(
                    id: "session",
                    title: "Blocking request fixture",
                    preview: nil,
                    source: "niles",
                    messageCount: 0,
                    startedAt: 1,
                    lastMessageAt: nil
                ),
            ]
        }
        if self == .transcriptScroll {
            return [
                HermesSession(
                    id: "scroll-alpha",
                    title: "Alpha history",
                    preview: "Parked reading position",
                    source: "niles",
                    messageCount: 40,
                    startedAt: now - 3_600,
                    lastMessageAt: now - 4
                ),
                HermesSession(
                    id: "scroll-beta",
                    title: "Beta history",
                    preview: "Independent reading position",
                    source: "niles",
                    messageCount: 40,
                    startedAt: now - 7_200,
                    lastMessageAt: now - 8
                ),
            ]
        }
        return [
            HermesSession(
                id: "brand",
                title: "Brand polish",
                preview: "Neutral graphite theme and compact AI chat chrome.",
                source: "niles",
                messageCount: 8,
                startedAt: now - 1_800,
                lastMessageAt: now - 8
            ),
            HermesSession(
                id: "gateway",
                title: "Gateway hardening",
                preview: "Checking reconnect and token-handling paths.",
                source: "niles",
                messageCount: 14,
                startedAt: now - 7_200,
                lastMessageAt: now - 420
            ),
            HermesSession(
                id: "release",
                title: "Release checklist",
                preview: "Waiting for the signing decision.",
                source: "niles",
                messageCount: 5,
                startedAt: now - 10_800,
                lastMessageAt: now - 900
            ),
            HermesSession(
                id: "cli",
                title: "CLI handoff",
                preview: "Mirrored from the terminal.",
                source: "cli",
                messageCount: 11,
                startedAt: now - 86_400,
                lastMessageAt: now - 3_600
            ),
        ]
    }

    var activeStatuses: [String: String] {
        switch self {
        case .empty:
            [:]
        case .visualRegressionBrand:
            ["gateway": "working"]
        case .visualRegressionMedia:
            [:]
        case .visualRegressionAttachments:
            [:]
        case .visualRegressionSyntax:
            [:]
        case .visualRegressionModelPicker:
            [:]
        case .visualRegressionDelegation:
            ["session": "working"]
        case .visualRegressionContext:
            [:]
        case .visualRegressionStats:
            [:]
        case .blockingClarification:
            [:]
        case .goalCreation, .goalActive:
            [:]
        case .showcase,
             .attachments,
             .modelPicker,
             .blockingApprovals,
             .blockingSudo,
             .blockingSecret,
             .blockingInvalid:
            ["gateway": "working", "release": "waiting"]
        case .transcriptScroll:
            [:]
        case .terminalBusy:
            [
                "gateway": "working",
                "release": "waiting",
                "cli": "working",
            ]
        }
    }

    var selectedSessionID: String? {
        switch self {
        case .empty:
            nil
        case .visualRegressionModelPicker,
             .visualRegressionAttachments,
             .visualRegressionSyntax,
             .visualRegressionDelegation,
             .visualRegressionContext,
             .visualRegressionStats,
             .goalCreation,
             .goalActive:
            "session"
        case .showcase,
             .visualRegressionBrand,
             .attachments,
             .modelPicker,
             .blockingClarification,
             .blockingApprovals,
             .blockingSudo,
             .blockingSecret,
             .blockingInvalid:
            "brand"
        case .visualRegressionMedia:
            "20260716_222504_892479"
        case .transcriptScroll:
            "scroll-alpha"
        case .terminalBusy:
            "cli"
        }
    }

    var sessionsNeedingInput: Set<String> {
        switch self {
        case .empty:
            []
        case .visualRegressionModelPicker,
             .visualRegressionAttachments,
             .visualRegressionSyntax,
             .visualRegressionDelegation,
             .visualRegressionContext,
             .visualRegressionStats,
             .goalCreation,
             .goalActive:
            []
        case .showcase,
             .visualRegressionBrand,
             .terminalBusy,
             .attachments,
             .modelPicker:
            ["release"]
        case .visualRegressionMedia:
            []
        case .transcriptScroll:
            []
        case .blockingClarification:
            ["brand"]
        case .blockingApprovals,
             .blockingSudo,
             .blockingSecret,
             .blockingInvalid:
            []
        }
    }

    var liveSession: LiveSession? {
        selectedSessionID.flatMap { liveSessions[$0] }
    }
}
#endif
