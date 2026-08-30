import Foundation

private let nativeMCPToolPattern = #"^mcp__[A-Za-z0-9_]+__[A-Za-z0-9_]+$"#
private let codexMCPToolPattern = #"^mcp\.[^.]+\..+$"#

func isMCPToolName(_ name: String) -> Bool {
    name.range(of: nativeMCPToolPattern, options: .regularExpression) != nil
        || name.range(of: codexMCPToolPattern, options: .regularExpression) != nil
}

func toolKind(_ name: String) -> ToolKind {
    switch name {
    case "terminal", "execute_code":
        .terminal
    case "memory":
        .memory
    case "skill_view", "skills_list", "skill_manage":
        .skill
    default:
        .tool
    }
}

func defaultToolLabel(_ name: String) -> String {
    switch name {
    case "terminal":
        "Running terminal command"
    case "execute_code":
        "Running code"
    case "memory":
        "Updating memory"
    case "skill_view":
        "Reading skill"
    case "skills_list":
        "Listing skills"
    case "skill_manage":
        "Updating skill"
    default:
        name.split(separator: "_")
            .filter { !$0.isEmpty }
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
            .nonBlank ?? "Tool"
    }
}

extension HermesMessage {
    func transcriptEntry(
        index: Int,
        imageCache: [String: String] = [:],
        goalObjective: String? = nil
    ) -> TranscriptEntry {
        let stableID = "history-\(index)-\(role)-\(javaStringHash(text))"
        if role == "tool", toolName == "clarify", text == "Decision answered" {
            return .message(
                TranscriptMessage(
                    id: stableID,
                    role: .system,
                    content: text
                )
            )
        }
        if role == "tool" {
            let name = toolName ?? "tool"
            let status = switch toolOutcome {
            case .succeeded:
                "done"
            case .failed:
                "failed"
            case .interrupted:
                "stopped"
            case .unknown:
                "recorded"
            }
            return .tool(
                TranscriptTool(
                    id: stableID,
                    name: name,
                    status: status,
                    content: text,
                    outcome: toolOutcome,
                    kind: toolKind(name),
                    label: toolContext ?? text.nonBlank
                )
            )
        }

        let mappedRole: TranscriptRole = switch role {
        case "user":
            .user
        case "system":
            .system
        default:
            .assistant
        }
        let displayText = mappedRole == .user
            ? text.userFacingGeneratedCommandText
            : text
        let parsed = parseMessageContent(
            displayText,
            extractMedia: mappedRole == .assistant
        )
        let images: [MessageImage]
        if !parsed.imagePaths.isEmpty {
            images = parsed.imagePaths.map { path in
                MessageImage(
                    base64: imageCache[path],
                    label: path.replacingOccurrences(of: "\\", with: "/")
                        .split(separator: "/").last.map(String.init) ?? path
                )
            }
        } else {
            images = parsed.inlineImages.map {
                MessageImage(base64: $0, label: "image")
            }
        }
        return .message(
            TranscriptMessage(
                id: stableID,
                role: mappedRole,
                content: parsed.text,
                images: images,
                attachments: parsed.attachments,
                isGoalPrompt: mappedRole == .user
                    && parsed.text.matchesGoalObjective(goalObjective)
            )
        )
    }
}

extension Array where Element == TranscriptEntry {
    func markingStandingGoalPrompts(
        objective: String?
    ) -> [TranscriptEntry] {
        guard objective?.nonBlank != nil else {
            return self
        }
        return map { entry in
            guard case var .message(message) = entry,
                  message.role == .user,
                  message.content.matchesGoalObjective(objective) else {
                return entry
            }
            message.isGoalPrompt = true
            return .message(message)
        }
    }

    func withoutDelegationCompletionEnvelopes() -> [TranscriptEntry] {
        filter { entry in
            guard case let .message(message) = entry,
                  message.role == .user else {
                return true
            }
            return !message.content.isHermesAsyncDelegationCompletionEnvelope
        }
    }
}

func javaStringHash(_ text: String) -> Int32 {
    var hash: Int32 = 0
    for unit in text.utf16 {
        hash = hash &* 31 &+ Int32(unit)
    }
    return hash
}

extension String {
    var userFacingGeneratedCommandText: String {
        let learnPrefix = "[/learn] The user wants you to learn a reusable skill"
        if hasPrefix(learnPrefix),
           let marker = range(of: "THE REQUEST:\n") {
            let requestStart = marker.upperBound
            let suffix = self[requestStart...]
            let request = suffix
                .components(separatedBy: "\n\nThe request is open-ended")[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !request.isEmpty {
                return "Generated /learn prompt (inferred summary): \(request)"
            }
        }

        let skillPrefix = "[IMPORTANT: The user has invoked the \""
        let invocationMarker = "The full skill content is loaded below.]"
        if hasPrefix(skillPrefix), contains(invocationMarker) {
            let firstLine = components(separatedBy: .newlines).first ?? ""
            let skillName = firstLine
                .replacingOccurrences(of: skillPrefix, with: "")
                .components(separatedBy: "\" skill")[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !skillName.isEmpty {
                let instructionMarker =
                    "The user has provided the following instruction alongside the skill invocation: "
                let instruction: String
                if let marker = range(of: instructionMarker, options: .backwards) {
                    instruction = self[marker.upperBound...]
                        .components(separatedBy: "\n\n[Runtime note:")[0]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    instruction = ""
                }
                if instruction.isEmpty {
                    return "Generated skill prompt (inferred summary): use the \(skillName) skill"
                }
                return "Generated skill prompt (inferred summary): use the \(skillName) skill — \(instruction)"
            }
        }
        return self
    }

    fileprivate func matchesGoalObjective(_ objective: String?) -> Bool {
        guard let objective = objective?.nonBlank else {
            return false
        }
        return normalizedGoalPromptText == objective.normalizedGoalPromptText
    }

    fileprivate var normalizedGoalPromptText: String {
        replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate var isHermesAsyncDelegationCompletionEnvelope: Bool {
        let lines = components(separatedBy: .newlines)
        guard let header = lines.first,
              header.range(
                  of: #"^\[ASYNC DELEGATION( BATCH)? COMPLETE — deleg_[0-9a-f]{8}]$"#,
                  options: .regularExpression
              ) != nil else {
            return false
        }
        if header.contains(" BATCH ") {
            guard lines.count >= 5,
                  lines[1].range(
                      of: #"^A background fan-out of \d+ subagent\(s\) you dispatched earlier has finished\."#,
                      options: .regularExpression
                  ) != nil,
                  lines[2].isEmpty,
                  lines.contains(where: { $0.range(
                      of: #"^Role: .+   Model: .+   Total duration: .+s$"#,
                      options: .regularExpression
                  ) != nil }),
                  lines.contains(where: { $0.range(
                      of: #"^--- [✓✗] TASK \d+/\d+"#,
                      options: .regularExpression
                  ) != nil }) else {
                return false
            }
            return true
        }
        let intro =
            "A background subagent you dispatched earlier has finished. You may have moved on since dispatching it; the full task source is below so you can act on the result or re-dispatch if things have changed."
        guard lines.count >= 7,
              lines[1] == intro,
              lines[2].isEmpty,
              lines.contains(where: { $0.hasPrefix("Original goal: ") }),
              lines.contains(where: { $0.range(
                  of: #"^Role: .+   Model: .+$"#,
                  options: .regularExpression
              ) != nil }),
              let resultIndex = lines.firstIndex(of: "--- RESULT ---") else {
            return false
        }
        return lines.dropFirst(resultIndex + 1).contains { !$0.isEmpty }
    }

    fileprivate var nonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
