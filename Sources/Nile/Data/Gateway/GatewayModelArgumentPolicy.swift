import Foundation

enum GatewayModelArgumentPolicy {
    static func requireSafeModelName(_ model: String) throws {
        let spacingPreserved =
            !model.isBlank
            && model == model.trimmingCharacters(in: .whitespacesAndNewlines)
            && !model.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
                    || (CharacterSet.whitespacesAndNewlines.contains($0)
                        && $0 != " ")
            })
            && model.split(separator: " ", omittingEmptySubsequences: true)
                .joined(separator: " ") == model
        guard spacingPreserved, !containsUnsafeModelFlag(model) else {
            throw HermesError(
                "config.set model cannot encode that model name safely",
                retryable: false
            )
        }
    }

    static func requireSafeProviderIdentifier(_ provider: String) throws {
        guard !provider.isBlank,
            provider == provider.trimmingCharacters(in: .whitespacesAndNewlines),
            !provider.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.controlCharacters.contains($0)
            }),
            !containsUnsafeModelFlag(provider)
        else {
            throw HermesError(
                "config.set model requires a one-token provider identifier",
                retryable: false
            )
        }
    }

    private static func containsUnsafeModelFlag(_ value: String) -> Bool {
        let normalized = value.replacingOccurrences(
            of: #"[‒–—―](provider|global|session|refresh)"#,
            with: "--$1",
            options: .regularExpression
        )
        return normalized != value
            || normalized.range(
                of: #"--(?:global|session|refresh)"#,
                options: .regularExpression
            ) != nil
            || normalized.split(separator: " ").contains("--provider")
    }
}
