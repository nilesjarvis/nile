import Foundation

enum GatewayMutationCodec {
    static func requireLiteral(
        _ result: JSONValue.Object,
        method: String,
        name: String,
        expected: String
    ) throws {
        let actual = try requireString(
            result,
            method: method,
            name: name,
            allowBlank: false
        )
        guard actual == expected else {
            throw malformedResult(
                method: method,
                detail: "\(name) was not '\(expected)'"
            )
        }
    }

    static func requireString(
        _ result: JSONValue.Object,
        method: String,
        name: String,
        allowBlank: Bool
    ) throws -> String {
        guard let value = result[name]?.stringValue else {
            throw malformedResult(
                method: method,
                detail: "\(name) was missing or not a string"
            )
        }
        guard allowBlank || !value.isBlank else {
            throw malformedResult(
                method: method,
                detail: "\(name) was blank"
            )
        }
        return value
    }

    static func requireBool(
        _ result: JSONValue.Object,
        method: String,
        name: String
    ) throws -> Bool {
        guard case .bool(let value)? = result[name] else {
            throw malformedResult(
                method: method,
                detail: "\(name) was missing or not true or false"
            )
        }
        return value
    }

    static func malformedResult(
        method: String,
        detail: String
    ) -> HermesError {
        HermesError(
            "Malformed response to \(method): \(detail)",
            retryable: false,
            requestMayHaveSucceeded: true
        )
    }
}
