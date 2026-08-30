import Foundation

enum GatewaySessionMessagePolicy {
    static func isPrivateGoalContinuation(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("[Continuing toward your standing goal]\nGoal:")
    }

    static func modelSwitchNotice(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            normalized.hasPrefix(modelSwitchPrefix),
            normalized.hasSuffix(modelSwitchSuffix)
        else {
            return nil
        }
        let start = normalized.index(
            normalized.startIndex,
            offsetBy: modelSwitchPrefix.count
        )
        let end = normalized.index(
            normalized.endIndex,
            offsetBy: -modelSwitchSuffix.count
        )
        let identity = normalized[start..<end]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else {
            return nil
        }
        return "model changed to \(identity)"
    }

    private static let modelSwitchPrefix =
        "[System: The active model for this chat has changed to "
    private static let modelSwitchSuffix =
        ". From this point forward, use this runtime metadata when answering questions about what model/provider is active.]"
}
