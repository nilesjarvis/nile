import Foundation

/// Pure attachment source, redirect, and filename security policy.
///
/// Request execution and credential handling remain in
/// `GatewayDashboardDownload`; this policy has no HTTP transport authority.
enum GatewayDashboardDownloadPolicy {
    static let redirectStatuses: Set<Int> = [
        300, 301, 302, 303, 307, 308,
    ]

    static func source(
        connection: GatewayConnection,
        path: String
    ) throws -> GatewayDashboardDownloadSource {
        if let absolute = URL(string: path), absolute.scheme != nil {
            if absolute.scheme?.lowercased() == "file" {
                return try managedSource(
                    connection: connection,
                    path: normalizedManagedPath(absolute)
                )
            }
            guard ["http", "https"].contains(
                absolute.scheme?.lowercased() ?? ""
            ) else {
                return try managedSource(
                    connection: connection,
                    path: path
                )
            }
            try validateExternalMediaURL(absolute)
            return GatewayDashboardDownloadSource(
                url: absolute,
                authenticated: false,
                fallbackFilename: nonBlank(absolute.lastPathComponent)
            )
        }
        if path.lowercased().hasPrefix("http:")
            || path.lowercased().hasPrefix("https:") {
            throw HermesError(
                "Attachment URL is invalid or unsafe",
                retryable: false
            )
        }
        return try managedSource(connection: connection, path: path)
    }

    static func validateExternalMediaURL(_ url: URL) throws {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ), components.user == nil, components.password == nil else {
            throw HermesError(
                "Attachment URL is invalid or unsafe",
                retryable: false
            )
        }
        let scheme = components.scheme?.lowercased()
        let host = components.host?.lowercased()
        let safeLoopback = scheme == "http"
            && ["127.0.0.1", "localhost", "::1"].contains(host)
        guard scheme == "https" || safeLoopback else {
            throw HermesError(
                "Attachment URL is invalid or unsafe",
                retryable: false
            )
        }
    }

    static func validateRedirect(from: URL, to: URL) throws {
        guard let toComponents = URLComponents(
            url: to,
            resolvingAgainstBaseURL: false
        ), toComponents.user == nil, toComponents.password == nil else {
            throw HermesError(
                "Attachment redirect destination is unsafe",
                retryable: false
            )
        }
        if from.scheme?.lowercased() == "https",
           to.scheme?.lowercased() != "https" {
            throw HermesError(
                "Attachment redirect cannot downgrade HTTPS",
                retryable: false
            )
        }
    }

    static func safeFilename(
        contentDisposition: String?,
        fallback: String?
    ) -> String {
        let extended = contentDisposition.flatMap { disposition in
            extendedFilenamePattern.firstMatch(
                in: disposition,
                range: NSRange(disposition.startIndex..., in: disposition)
            ).flatMap { match in
                (1..<match.numberOfRanges).compactMap { index -> String? in
                    guard let range = Range(
                        match.range(at: index),
                        in: disposition
                    ) else {
                        return nil
                    }
                    return nonBlank(String(disposition[range]))
                }.first
            }.flatMap(decodeExtendedFilename)
        }
        let basic = contentDisposition.flatMap { disposition in
            filenamePattern.firstMatch(
                in: disposition,
                range: NSRange(disposition.startIndex..., in: disposition)
            ).flatMap { match in
                (1..<match.numberOfRanges).compactMap { index -> String? in
                    guard let range = Range(
                        match.range(at: index),
                        in: disposition
                    ) else {
                        return nil
                    }
                    return nonBlank(String(disposition[range]))
                }.first
            }
        }
        let raw = extended ?? basic ?? fallback ?? "attachment"
        let leaf = raw.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/").last.map(String.init) ?? "attachment"
        let safe = leaf.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }.map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return nonBlank(safe) ?? "attachment"
    }

    static func nonBlank(_ value: String) -> String? {
        value.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
        ).isEmpty ? nil : value
    }

    private static func managedSource(
        connection: GatewayConnection,
        path: String
    ) throws -> GatewayDashboardDownloadSource {
        guard !path.isBlank, !path.contains("\0") else {
            throw HermesError(
                "Attachment file URL does not contain a valid path",
                retryable: false
            )
        }
        let endpoint = try connection.endpoint.apiURL(
            pathSegments: ["api", "files", "download"]
        )
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw HermesError(
                "Attachment download URL is invalid",
                retryable: false
            )
        }
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else {
            throw HermesError(
                "Attachment download URL is invalid",
                retryable: false
            )
        }
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return GatewayDashboardDownloadSource(
            url: url,
            authenticated: true,
            fallbackFilename: normalized.split(separator: "/")
                .last.map(String.init).flatMap(nonBlank)
        )
    }

    private static func normalizedManagedPath(_ url: URL) throws -> String {
        guard url.query == nil, url.fragment == nil else {
            throw HermesError(
                "Attachment file URL cannot contain a query or fragment",
                retryable: false
            )
        }
        if let host = url.host,
           !host.isEmpty,
           host.caseInsensitiveCompare("localhost") != .orderedSame {
            throw HermesError(
                "Attachment file URL must refer to a local path",
                retryable: false
            )
        }
        var path = url.path
        if path.range(
            of: #"^/[A-Za-z]:/"#,
            options: .regularExpression
        ) != nil {
            path.removeFirst()
        }
        guard !path.isBlank, !path.contains("\0") else {
            throw HermesError(
                "Attachment file URL does not contain a valid path",
                retryable: false
            )
        }
        return path
    }

    private static let filenamePattern = try! NSRegularExpression(
        pattern:
            #"(?:^|;)\s*filename\s*=\s*(?:\"((?:[^\"\\]|\\.)*)\"|([^;]*))"#,
        options: [.caseInsensitive]
    )

    private static let extendedFilenamePattern = try! NSRegularExpression(
        pattern:
            #"(?:^|;)\s*filename\*\s*=\s*(?:\"([^\"]*)\"|([^;]*))"#,
        options: [.caseInsensitive]
    )

    private static func decodeExtendedFilename(_ value: String) -> String? {
        let parts = value.split(
            separator: "'",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard parts.count == 3,
              parts[0].caseInsensitiveCompare("UTF-8") == .orderedSame else {
            return nil
        }
        return String(parts[2]).removingPercentEncoding
    }
}

struct GatewayDashboardDownloadSource {
    let url: URL
    let authenticated: Bool
    let fallbackFilename: String?
}
