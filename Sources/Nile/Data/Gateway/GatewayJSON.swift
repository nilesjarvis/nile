import Foundation

extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case let .array(array) = self else {
            return nil
        }
        return array
    }

    var lenientStringValue: String {
        switch self {
        case let .string(value):
            value
        case let .number(value):
            Self.render(number: value)
        case let .bool(value):
            value ? "true" : "false"
        case .null:
            ""
        case .object, .array:
            (try? JSONSerialization.data(
                withJSONObject: foundationValue,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    var lenientIntValue: Int? {
        switch self {
        case let .number(value):
            guard
                value.isFinite,
                value >= Double(Int.min),
                value < Double(Int.max)
            else {
                return nil
            }
            return Int(value)
        case let .string(value):
            return Int(value)
        default:
            return nil
        }
    }

    var lenientDoubleValue: Double? {
        switch self {
        case let .number(value):
            value.isFinite ? value : nil
        case let .string(value):
            Double(value).flatMap { $0.isFinite ? $0 : nil }
        default:
            nil
        }
    }

    private static func render(number: Double) -> String {
        guard number.isFinite else {
            return "null"
        }
        if number.rounded(.towardZero) == number,
           number >= Double(Int64.min),
           number < Double(Int64.max) {
            return String(Int64(number))
        }
        return String(number)
    }
}

extension Dictionary where Key == String, Value == JSONValue {
    func optionalString(_ name: String) -> String? {
        guard let value = self[name], value != .null else {
            return nil
        }
        let string = value.lenientStringValue
        return string.isBlank ? nil : string
    }

    func string(_ name: String, default fallback: String = "") -> String {
        guard let value = self[name], value != .null else {
            return fallback
        }
        return value.lenientStringValue
    }

    func int(_ name: String, default fallback: Int = 0) -> Int {
        self[name]?.lenientIntValue ?? fallback
    }

    func bool(_ name: String, default fallback: Bool = false) -> Bool {
        guard let value = self[name] else {
            return fallback
        }
        switch value {
        case let .bool(value):
            return value
        case let .string(value):
            if value.caseInsensitiveCompare("true") == .orderedSame {
                return true
            }
            if value.caseInsensitiveCompare("false") == .orderedSame {
                return false
            }
            return fallback
        default:
            return fallback
        }
    }

    func requireObjectArray(method: String, name: String) throws -> [JSONValue.Object] {
        guard case let .array(values)? = self[name] else {
            throw HermesError(
                "Malformed response to \(method): \(name) was missing or not an array",
                retryable: false
            )
        }
        return try values.enumerated().map { index, value in
            guard let object = value.objectValue else {
                throw HermesError(
                    "Malformed response to \(method): \(name)[\(index)] was not an object",
                    retryable: false
                )
            }
            return object
        }
    }

    func requireNonBlankString(method: String, name: String) throws -> String {
        guard
            let value = self[name]?.stringValue,
            !value.isBlank
        else {
            throw HermesError(
                "Malformed response to \(method): \(name) was missing or blank",
                retryable: false
            )
        }
        return value
    }
}

extension Array where Element == JSONValue {
    var objectValues: [JSONValue.Object] {
        compactMap(\.objectValue)
    }
}

extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isProtocolNullText: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("null") == .orderedSame
    }

    func strippingANSI() -> String {
        replacingOccurrences(
            of: #"\u001B\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
    }
}

struct DisplayToolResult: Equatable, Sendable {
    let text: String
    let outcome: ToolCompletionOutcome
}

func displayToolResult(_ raw: String, toolName: String) -> DisplayToolResult {
    let clean = raw.strippingANSI().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
        return DisplayToolResult(text: "", outcome: .unknown)
    }
    guard ["terminal", "execute_code", "clarify"].contains(toolName),
          let envelope = parseJSONObject(clean)
    else {
        return DisplayToolResult(text: clean, outcome: .unknown)
    }
    if toolName == "clarify", envelope["user_response"] != nil {
        return DisplayToolResult(text: "Decision answered", outcome: .succeeded)
    }

    let output = envelope["output"]?.stringValue?
        .strippingANSI()
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? clean
    let exitCode = envelope["exit_code"]?.lenientIntValue
    let interrupted = exitCode == 130 || output
        .split(separator: "\n", omittingEmptySubsequences: false)
        .contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("[Command interrupted]") == .orderedSame
        }
    let outcome: ToolCompletionOutcome
    if interrupted {
        outcome = .interrupted
    } else if exitCode == 0 {
        outcome = .succeeded
    } else if exitCode != nil {
        outcome = .failed
    } else {
        outcome = .unknown
    }
    let visibleOutput: String
    if interrupted {
        visibleOutput = output
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("[Command interrupted]") != .orderedSame
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        visibleOutput = output
    }
    return DisplayToolResult(text: visibleOutput, outcome: outcome)
}

private func parseJSONObject(_ string: String) -> JSONValue.Object? {
    guard
        let data = string.data(using: .utf8),
        let raw = try? JSONSerialization.jsonObject(with: data),
        let value = try? JSONValue(any: raw)
    else {
        return nil
    }
    return value.objectValue
}
