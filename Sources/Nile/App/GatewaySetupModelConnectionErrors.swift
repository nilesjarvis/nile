import Foundation

@MainActor
extension GatewaySetupModel {
    static func isRetryableConnectionFailure(
        _ error: any Error
    ) -> Bool {
        if let hermes = error as? HermesError {
            return hermes.isConnectionFailure && hermes.retryable
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        if let probe = error as? GatewayProbeError {
            guard case let .httpStatus(status) = probe else {
                return false
            }
            return status == 408 || status == 429 || status >= 500
        }
        return false
    }

    static func connectionMessage(for error: any Error) -> String {
        if let conflict = error as? GatewayCookieScopeConflictError {
            return conflict.localizedDescription
        }
        if let tokenError = error as? GatewayTokenRequiredError {
            return tokenError.localizedDescription
        }
        if let hermesError = error as? HermesError {
            return hermesError.localizedDescription
        }
        return GatewayProbePresentation.message(for: error)
    }
}
