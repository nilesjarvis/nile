import Foundation

enum GatewayEndpointParser {
    static func parse(
        _ value: String,
        legacy: Bool
    ) throws -> GatewayEndpoint {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            throw GatewayEndpointError("Gateway URL is required")
        }
        if candidate.contains("\\") || candidate.range(
            of: "%5c",
            options: [.caseInsensitive]
        ) != nil {
            throw GatewayEndpointError("Gateway URL cannot contain backslashes")
        }

        if candidate.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#,
            options: .regularExpression
        ) == nil {
            guard legacy else {
                throw GatewayEndpointError("Gateway URL must start with http:// or https://")
            }
            candidate = "http://" + candidate
        }
        if legacy {
            while candidate.last == "/" {
                candidate.removeLast()
            }
        }

        guard
            let schemeSeparator = candidate.range(of: "://"),
            !schemeSeparator.isEmpty
        else {
            throw GatewayEndpointError("Enter a valid gateway URL")
        }

        let rawScheme = String(candidate[..<schemeSeparator.lowerBound])
        let scheme = rawScheme.lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw GatewayEndpointError("Gateway URL must use http:// or https://")
        }

        let afterScheme = candidate[schemeSeparator.upperBound...]
        let authorityEnd = afterScheme.firstIndex { character in
            character == "/" || character == "?" || character == "#"
        } ?? afterScheme.endIndex
        let rawAuthority = String(afterScheme[..<authorityEnd])
        guard !rawAuthority.isEmpty else {
            throw GatewayEndpointError("Gateway URL must include a host")
        }
        guard !rawAuthority.contains("@") else {
            throw GatewayEndpointError("Gateway URL cannot include a username or password")
        }
        try validatePort(rawAuthority)

        let rawRemainder = String(afterScheme[authorityEnd...])
        if rawRemainder.contains("?") {
            throw GatewayEndpointError("Gateway URL cannot include a query")
        }
        if rawRemainder.contains("#") {
            throw GatewayEndpointError("Gateway URL cannot include a fragment")
        }
        try validateProxyPrefix(rawRemainder)

        guard var components = URLComponents(string: candidate) else {
            throw GatewayEndpointError("Enter a valid gateway URL")
        }
        guard components.scheme?.lowercased() == scheme else {
            throw GatewayEndpointError("Gateway URL must use http:// or https://")
        }
        guard components.user == nil, components.password == nil else {
            throw GatewayEndpointError("Gateway URL cannot include a username or password")
        }
        guard let host = components.host, !host.isEmpty else {
            throw GatewayEndpointError("Gateway URL must include a host")
        }
        guard components.query == nil else {
            throw GatewayEndpointError("Gateway URL cannot include a query")
        }
        guard components.fragment == nil else {
            throw GatewayEndpointError("Gateway URL cannot include a fragment")
        }

        components.scheme = scheme
        components.host = host.lowercased()
        if (scheme == "https" && components.port == 443)
            || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        while components.percentEncodedPath.last == "/"
            && components.percentEncodedPath != "/" {
            components.percentEncodedPath.removeLast()
        }
        if components.percentEncodedPath == "/" {
            components.percentEncodedPath = ""
        }

        guard let canonical = components.url?.absoluteString else {
            throw GatewayEndpointError("Enter a valid gateway URL")
        }
        return GatewayEndpoint(baseURL: canonical)
    }

    private static func validateProxyPrefix(_ rawPath: String) throws {
        guard !rawPath.isEmpty, rawPath != "/" else {
            return
        }
        guard rawPath.first == "/" else {
            throw GatewayEndpointError("Gateway URL path must be a clean proxy prefix")
        }

        let withoutLeadingSlash = rawPath.dropFirst()
        let segments = withoutLeadingSlash.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        for (index, segmentValue) in segments.enumerated() {
            let segment = String(segmentValue)
            let isAllowedTrailingSlash = index == segments.count - 1 && segment.isEmpty
            if segment.isEmpty && !isAllowedTrailingSlash {
                throw GatewayEndpointError("Gateway URL path must be a clean proxy prefix")
            }
            if segment.range(
                of: #"%(?:2f|5c)"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                throw GatewayEndpointError("Gateway URL path cannot contain encoded slashes")
            }
            let decodedDots = segment.replacingOccurrences(
                of: "%2e",
                with: ".",
                options: [.caseInsensitive]
            )
            if decodedDots == "." || decodedDots == ".." {
                throw GatewayEndpointError("Gateway URL path cannot contain dot segments")
            }
        }
    }

    private static func validatePort(_ rawAuthority: String) throws {
        let suffix: Substring
        if rawAuthority.first == "[" {
            guard let closingBracket = rawAuthority.firstIndex(of: "]") else {
                throw GatewayEndpointError("Enter a valid gateway URL")
            }
            suffix = rawAuthority[rawAuthority.index(after: closingBracket)...]
        } else if let colon = rawAuthority.lastIndex(of: ":") {
            suffix = rawAuthority[colon...]
        } else {
            suffix = ""
        }

        guard !suffix.isEmpty else {
            return
        }
        guard suffix.first == ":" else {
            throw GatewayEndpointError("Gateway URL port must be between 1 and 65535")
        }
        let portText = suffix.dropFirst()
        guard
            !portText.isEmpty,
            portText.allSatisfy(\.isNumber),
            let port = Int(portText),
            (1...65_535).contains(port)
        else {
            throw GatewayEndpointError("Gateway URL port must be between 1 and 65535")
        }
    }
}
