import Foundation

struct GatewayBlockingEventProjector: Sendable {
    func project(_ frame: GatewayEventFrame) -> HermesStreamEvent {
        blocking(frame) {
            switch frame.type {
            case "clarify.request":
                .clarificationRequest(
                    sessionID: frame.sessionID,
                    requestID: try requiredString(
                        frame.payload,
                        "request_id"
                    ),
                    question: try requiredString(frame.payload, "question"),
                    choices: try optionalStrings(frame.payload, "choices")
                )
            case "approval.request":
                .approvalRequest(
                    sessionID: frame.sessionID,
                    command: try requiredString(frame.payload, "command"),
                    description: try requiredString(
                        frame.payload,
                        "description",
                        allowBlank: true
                    ),
                    allowPermanent: try optionalBool(
                        frame.payload,
                        "allow_permanent"
                    ) ?? true
                )
            case "sudo.request":
                .sudoRequest(
                    sessionID: frame.sessionID,
                    requestID: try requiredString(
                        frame.payload,
                        "request_id"
                    )
                )
            case "secret.request":
                .secretRequest(
                    sessionID: frame.sessionID,
                    requestID: try requiredString(
                        frame.payload,
                        "request_id"
                    ),
                    envVar: try requiredString(frame.payload, "env_var"),
                    prompt: try requiredString(frame.payload, "prompt"),
                    metadata: try secretMetadata(frame.payload)
                )
            default:
                throw InvalidBlockingPayload("unsupported request type")
            }
        }
    }

    private func blocking(
        _ frame: GatewayEventFrame,
        parse: () throws -> HermesStreamEvent
    ) -> HermesStreamEvent {
        do {
            return try parse()
        } catch let error as InvalidBlockingPayload {
            return .blockingRequestInvalid(
                sessionID: frame.sessionID,
                requestType: frame.type,
                message: "Malformed \(frame.type): \(error.message)"
            )
        } catch {
            return .blockingRequestInvalid(
                sessionID: frame.sessionID,
                requestType: frame.type,
                message: "Malformed \(frame.type): invalid payload"
            )
        }
    }

    private func requiredString(
        _ object: JSONValue.Object?,
        _ name: String,
        allowBlank: Bool = false
    ) throws -> String {
        guard let value = object?[name]?.stringValue else {
            throw InvalidBlockingPayload("\(name) was missing or not text")
        }
        if !allowBlank, value.isBlank {
            throw InvalidBlockingPayload("\(name) was blank")
        }
        return value
    }

    private func optionalBool(
        _ object: JSONValue.Object?,
        _ name: String
    ) throws -> Bool? {
        guard let object, let value = object[name], value != .null else {
            return nil
        }
        guard case let .bool(bool) = value else {
            throw InvalidBlockingPayload("\(name) was not true or false")
        }
        return bool
    }

    private func optionalStrings(
        _ object: JSONValue.Object?,
        _ name: String
    ) throws -> [String]? {
        guard let object, let value = object[name], value != .null else {
            return nil
        }
        guard case let .array(values) = value else {
            throw InvalidBlockingPayload("\(name) was not a list")
        }
        return try values.enumerated().map { index, value in
            guard let string = value.stringValue, !string.isBlank else {
                throw InvalidBlockingPayload(
                    "\(name)[\(index)] was missing or blank"
                )
            }
            return string
        }
    }

    private func secretMetadata(
        _ object: JSONValue.Object?
    ) throws -> SecretRequestMetadata? {
        guard
            let object,
            let raw = object["metadata"],
            raw != .null
        else {
            return nil
        }
        guard let metadata = raw.objectValue else {
            throw InvalidBlockingPayload("metadata was not an object")
        }
        return SecretRequestMetadata(
            skillName: try optionalMetadataString(metadata, "skill_name"),
            help: try optionalMetadataString(metadata, "help"),
            requiredFor: try optionalMetadataString(metadata, "required_for")
        )
    }

    private func optionalMetadataString(
        _ object: JSONValue.Object,
        _ name: String
    ) throws -> String? {
        guard let value = object[name], value != .null else {
            return nil
        }
        guard let string = value.stringValue, !string.isBlank else {
            throw InvalidBlockingPayload(
                "metadata.\(name) was missing or blank"
            )
        }
        return string
    }
}

private struct InvalidBlockingPayload: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
