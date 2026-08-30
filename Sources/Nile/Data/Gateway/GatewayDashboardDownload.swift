import Foundation

/// Security-sensitive attachment download transport loop.
///
/// Pure source, redirect, and filename decisions live in
/// `GatewayDashboardDownloadPolicy`; this extension alone performs requests,
/// attaches or strips credentials, enforces response bounds, and follows the
/// bounded manual redirect sequence.
extension GatewayDashboardClient {
    func download(
        connection: GatewayConnection,
        path: String,
        maximumBytes: Int64
    ) async throws -> DownloadedAttachment {
        guard (1...(32 * 1_024 * 1_024)).contains(maximumBytes) else {
            throw HermesError(
                "Attachment download limit must be between 1 and 33554432 bytes",
                retryable: false
            )
        }
        let source = try GatewayDashboardDownloadPolicy.source(
            connection: connection,
            path: path
        )
        var url = source.url
        var authenticated = source.authenticated
        var redirectCount = 0
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            if authenticated, !connection.token.isBlank {
                request.setValue(
                    connection.token,
                    forHTTPHeaderField: "X-Hermes-Session-Token"
                )
            }
            let bounded = try await transport.data(
                for: request,
                maximumBytes: maximumBytes
            )
            let response = bounded.response
            if response.statusCode == 401, authenticated {
                throw GatewaySignInRequiredError(
                    loginURL: try GatewayDashboardResponsePolicy.safeLoginURL(
                        connection: connection,
                        responseData: response.data
                    ),
                    message:
                        "Your Hermes dashboard session has expired or requires sign-in"
                )
            }
            if GatewayDashboardDownloadPolicy.redirectStatuses.contains(
                response.statusCode
            ) {
                guard redirectCount < 5 else {
                    throw HermesError(
                        "Attachment download redirected too many times",
                        retryable: false
                    )
                }
                guard let location = response.header("Location") else {
                    throw HermesError(
                        "Attachment redirect did not include a destination",
                        retryable: false
                    )
                }
                guard let redirected = URL(
                    string: location,
                    relativeTo: url
                )?.absoluteURL else {
                    throw HermesError(
                        "Attachment redirect destination is invalid",
                        retryable: false
                    )
                }
                try GatewayDashboardDownloadPolicy.validateRedirect(
                    from: url,
                    to: redirected
                )
                redirectCount += 1
                if !GatewayURLOriginPolicy.sameOrigin(
                    redirected,
                    source.url
                ) {
                    try GatewayDashboardDownloadPolicy
                        .validateExternalMediaURL(redirected)
                    authenticated = false
                }
                url = redirected
                continue
            }
            guard (200...299).contains(response.statusCode) else {
                throw HermesError(
                    "Could not download attachment (HTTP \(response.statusCode))",
                    retryable: GatewayDashboardResponsePolicy
                        .isRetryableHTTPStatus(response.statusCode)
                )
            }
            guard !bounded.tooLarge else {
                throw HermesError(
                    "Attachment is too large to download safely",
                    retryable: false
                )
            }
            return DownloadedAttachment(
                path: path,
                filename: GatewayDashboardDownloadPolicy.safeFilename(
                    contentDisposition: response.header(
                        "Content-Disposition"
                    ),
                    fallback: source.fallbackFilename
                        ?? (authenticated ? nil : url.lastPathComponent)
                ),
                mimeType: response.header("Content-Type")?
                    .split(separator: ";", maxSplits: 1)
                    .first
                    .map(String.init)
                    .flatMap(GatewayDashboardDownloadPolicy.nonBlank)
                    ?? "application/octet-stream",
                bytes: response.data
            )
        }
    }

}
