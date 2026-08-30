import Foundation

struct GatewayFailureClassification: Sendable {
    let message: String
    let authRejected: Bool
    let retryable: Bool

    init(message: String, authRejected: Bool, retryable: Bool) {
        self.message = message
        self.authRejected = authRejected
        self.retryable = retryable
    }

    init(_ error: HermesError) {
        self.init(
            message: error.message,
            authRejected: error.authRejected,
            retryable: error.retryable
        )
    }
}

enum GatewayConnectionFailurePolicy {
    static func connectionError(for error: any Error) -> HermesError {
        let classification = classify(error)
        return HermesError(
            classification.message,
            authRejected: classification.authRejected,
            retryable: classification.retryable,
            isConnectionFailure: true
        )
    }

    static func classify(_ error: any Error) -> GatewayFailureClassification {
        guard let failure = error as? GatewayWebSocketFailure else {
            return genericFailure(message: error.localizedDescription)
        }
        if let closeCode = failure.closeCode {
            return classifyClose(
                code: closeCode,
                reason: failure.closeReason ?? ""
            )
        }
        if let status = failure.httpStatusCode {
            return classifyHTTP(status)
        }
        return genericFailure(message: failure.message)
    }

    private static func genericFailure(
        message: String
    ) -> GatewayFailureClassification {
        let safe = sanitizeCredential(message)
        return GatewayFailureClassification(
            message: safe.isEmpty
                ? "Gateway connection failed"
                : "Gateway connection failed: \(safe)",
            authRejected: false,
            retryable: true
        )
    }

    private static func classifyHTTP(
        _ status: Int
    ) -> GatewayFailureClassification {
        switch status {
        case 401:
            GatewayFailureClassification(
                message: "Gateway rejected the token (HTTP 401)",
                authRejected: true,
                retryable: false
            )
        case 403:
            GatewayFailureClassification(
                message: "Gateway refused the connection (HTTP 403); check the endpoint, token, and Host policy",
                authRejected: false,
                retryable: false
            )
        case 404:
            GatewayFailureClassification(
                message: "Gateway WebSocket endpoint was not found (HTTP 404)",
                authRejected: false,
                retryable: false
            )
        case 408, 425, 429:
            GatewayFailureClassification(
                message: "Gateway temporarily refused the connection (HTTP \(status))",
                authRejected: false,
                retryable: true
            )
        case 400...499:
            GatewayFailureClassification(
                message: "Gateway refused the connection (HTTP \(status))",
                authRejected: false,
                retryable: false
            )
        case 300...399:
            GatewayFailureClassification(
                message: "Gateway WebSocket endpoint redirected (HTTP \(status))",
                authRejected: false,
                retryable: false
            )
        default:
            GatewayFailureClassification(
                message: "Gateway connection failed",
                authRejected: false,
                retryable: true
            )
        }
    }

    private static func classifyClose(
        code: Int,
        reason: String
    ) -> GatewayFailureClassification {
        let safeReason = String(
            sanitizeCredential(reason)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(160)
        )
        let suffix = safeReason.isEmpty ? "" : ": \(safeReason)"
        return switch code {
        case 4_401:
            GatewayFailureClassification(
                message: "Gateway rejected the token (4401)\(suffix)",
                authRejected: true,
                retryable: false
            )
        case 4_403:
            GatewayFailureClassification(
                message: "Gateway refused the connection (4403); check endpoint access policy or credentials\(suffix)",
                authRejected: false,
                retryable: false
            )
        case 1_002, 1_003, 1_007:
            GatewayFailureClassification(
                message: "Gateway protocol error (\(code))\(suffix)",
                authRejected: false,
                retryable: false
            )
        case 1_008:
            GatewayFailureClassification(
                message: "Gateway closed the connection for a policy violation\(suffix)",
                authRejected: false,
                retryable: false
            )
        default:
            GatewayFailureClassification(
                message: "Gateway connection closed (\(code))\(suffix)",
                authRejected: false,
                retryable: true
            )
        }
    }

    private static func sanitizeCredential(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"([?&](?:token|ticket)=)[^&\s]+"#,
            with: "$1<redacted>",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
