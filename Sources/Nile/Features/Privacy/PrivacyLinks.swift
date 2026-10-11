import Foundation

enum PrivacyLinks {
    static var privacyPolicyURL: URL? {
        httpsURL(Bundle.main.object(forInfoDictionaryKey: "NilePrivacyPolicyURL"))
    }

    static var supportURL: URL? {
        httpsURL(Bundle.main.object(forInfoDictionaryKey: "NileSupportURL"))
    }

    // Missing publishing configuration is a submission preflight failure;
    // never send people to an invented or placeholder policy URL.
    static func httpsURL(_ value: Any?) -> URL? {
        guard let value = value as? String,
              !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              !["\\", "$(", "${", "<", ">", "{", "}"].contains(where: value.contains),
              let components = URLComponents(string: value),
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              let rawHost = url.host,
              url.user == nil, url.password == nil,
              components.port != 0
        else { return nil }
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let reserved = ["example.com", "example.org", "example.net", "localhost", "local", "internal", "lan", "home", "test", "invalid", "example", "your-domain.com", "yourdomain.com"]
        guard !reserved.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              host.count <= 253 else { return nil }
        // Publishing destinations must use a DNS name, not a local or numeric
        // IP literal. Reachability is verified separately before submission.
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.last?.contains(where: { $0.isLetter }) == true,
              labels.allSatisfy({ label in
                  label.range(of: "^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$", options: .regularExpression) != nil
              }) else { return nil }
        let credentialKeys: Set<String> = [
            "token", "access_token", "refresh_token", "id_token", "api_key", "apikey",
            "password", "passwd", "secret", "client_secret", "credential", "credentials", "authorization", "auth", "key", "signature",
            "x-amz-credential", "x-amz-signature",
        ]
        guard !(components.queryItems ?? []).contains(where: {
            credentialKeys.contains($0.name.lowercased())
        }) else { return nil }
        return url
    }
}
