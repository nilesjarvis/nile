import Foundation

struct GatewayCommandCodec: Sendable {
    func decodeCatalog(
        _ result: JSONValue.Object
    ) throws -> CommandCatalog {
        let warning = result.string("warning")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard warning.isEmpty else {
            throw HermesError(
                "Hermes command discovery was incomplete: \(warning)",
                retryable: false
            )
        }
        let categories = try result.requireObjectArray(
            method: "commands.catalog",
            name: "categories"
        ).map { category in
            CommandCategory(
                name: category.string("name").isBlank
                    ? "Commands"
                    : category.string("name"),
                commands: try decodePairs(category, name: "pairs")
            )
        }
        let allPairs = try decodePairs(result, name: "pairs")
        let skillCount = result.int("skill_count")
        let skills = skillCount >= 1 && skillCount <= allPairs.count
            ? Array(allPairs.suffix(skillCount))
            : []
        return CommandCatalog(
            categories: categories,
            skillCommands: skills
        )
    }

    func decodeCompletions(
        _ result: JSONValue.Object
    ) throws -> SlashCompletions {
        let replaceFrom = max(0, result.int("replace_from", default: 1))
        let items = try result.requireObjectArray(
            method: "complete.slash",
            name: "items"
        ).compactMap { item -> SlashCompletion? in
            guard var replacement = item["text"]?.stringValue,
                  !replacement.isBlank else {
                return nil
            }
            if replaceFrom == 1, replacement.hasPrefix("/") {
                replacement.removeFirst()
            }
            return SlashCompletion(
                text: replacement,
                display: item["display"]?.stringValue.flatMap {
                    $0.isBlank ? nil : $0
                } ?? "/\(replacement)",
                meta: item["meta"]?.stringValue ?? ""
            )
        }
        return SlashCompletions(
            items: items,
            replaceFrom: replaceFrom
        )
    }

    func decodeExecution(
        _ result: JSONValue.Object,
        method: String
    ) throws -> CommandExecution {
        guard result["type"] != nil else {
            return .output(try commandOutput(result, method: method))
        }
        let type = try requireString(
            result,
            method: method,
            name: "type",
            allowBlank: false
        )
        let notice = try commandNotice(result, method: method)
        switch type {
        case "exec", "plugin":
            return .output(
                try commandOutput(
                    result,
                    method: method,
                    leadingNotice: try optionalString(
                        result,
                        method: method,
                        name: "notice"
                    ).flatMap { $0.isBlank ? nil : $0 }
                )
            )
        case "send":
            return .submitPrompt(
                message: try requireString(
                    result,
                    method: method,
                    name: "message",
                    allowBlank: false
                ),
                notice: notice
            )
        case "skill":
            let name = try requireString(
                result,
                method: method,
                name: "name",
                allowBlank: false
            )
            return .submitPrompt(
                message: try requireString(
                    result,
                    method: method,
                    name: "message",
                    allowBlank: false
                ),
                notice: ["⚡ loading skill: \(name)", notice]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            )
        case "prefill":
            return .prefillComposer(
                message: try requireString(
                    result,
                    method: method,
                    name: "message",
                    allowBlank: true
                ),
                notice: notice
            )
        case "alias":
            return .alias(
                target: try requireString(
                    result,
                    method: method,
                    name: "target",
                    allowBlank: false
                )
            )
        default:
            throw malformedResult(
                method: method,
                detail: "unknown type '\(type)'"
            )
        }
    }

    private func decodePairs(
        _ result: JSONValue.Object,
        name: String
    ) throws -> [CommandInfo] {
        guard case let .array(values)? = result[name] else {
            throw HermesError(
                "Malformed response to commands.catalog: \(name) was missing or not an array",
                retryable: false
            )
        }
        return values.compactMap { value in
            guard case let .array(pair) = value,
                  let command = pair.first?.stringValue,
                  !command.isBlank else {
                return nil
            }
            return CommandInfo(
                name: command,
                description: pair.count > 1
                    ? pair[1].stringValue ?? ""
                    : ""
            )
        }
    }

    private func commandOutput(
        _ result: JSONValue.Object,
        method: String,
        leadingNotice: String? = nil
    ) throws -> String {
        let rawOutput = try requireString(
            result,
            method: method,
            name: "output",
            allowBlank: true
        )
        let output = rawOutput.isBlank ? "(no output)" : rawOutput
        let warning = try optionalString(
            result,
            method: method,
            name: "warning"
        ).flatMap { $0.isBlank ? nil : "warning: \($0)" }
        return [leadingNotice, warning, output]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private func commandNotice(
        _ result: JSONValue.Object,
        method: String
    ) throws -> String? {
        let notice = try optionalString(
            result,
            method: method,
            name: "notice"
        ).flatMap { $0.isBlank ? nil : $0 }
        let warning = try optionalString(
            result,
            method: method,
            name: "warning"
        ).flatMap { $0.isBlank ? nil : "warning: \($0)" }
        let values = [notice, warning].compactMap { $0 }
        return values.isEmpty ? nil : values.joined(separator: "\n")
    }

    private func optionalString(
        _ result: JSONValue.Object,
        method: String,
        name: String
    ) throws -> String? {
        guard let value = result[name], value != .null else {
            return nil
        }
        guard let string = value.stringValue else {
            throw malformedResult(
                method: method,
                detail: "\(name) was not a string"
            )
        }
        return string
    }

    private func requireString(
        _ result: JSONValue.Object,
        method: String,
        name: String,
        allowBlank: Bool
    ) throws -> String {
        guard let value = try optionalString(
            result,
            method: method,
            name: name
        ) else {
            throw malformedResult(
                method: method,
                detail: "\(name) was missing"
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

    private func malformedResult(
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
