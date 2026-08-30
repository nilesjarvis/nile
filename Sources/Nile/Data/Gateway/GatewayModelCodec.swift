struct GatewayModelCodec: Sendable {
    func decodeOptions(
        _ result: JSONValue.Object
    ) throws -> ModelOptions {
        let providers = try result.requireObjectArray(
            method: "model.options",
            name: "providers"
        ).map { provider in
            let slug = provider.string("slug")
            let models = try strictStringArray(
                provider,
                name: "models"
            )
            return ModelProvider(
                slug: slug,
                name: try strictOptionalString(provider, name: "name"),
                authenticated: try strictBool(
                    provider,
                    name: "authenticated"
                ),
                isCurrent: try strictBool(
                    provider,
                    name: "is_current"
                ),
                models: models,
                capabilities: try decodeCapabilities(provider),
                pricing: try decodePricing(provider),
                freeTier: try strictOptionalBool(
                    provider,
                    name: "free_tier"
                ),
                unavailableModels: Set(
                    try strictOptionalStringArray(
                        provider,
                        name: "unavailable_models"
                    )
                )
            )
        }
        return ModelOptions(
            model: try strictOptionalString(result, name: "model"),
            provider: try strictOptionalString(result, name: "provider"),
            providers: providers
        )
    }

    func decodeSwitchOutcome(
        _ result: JSONValue.Object
    ) throws -> ModelSwitchOutcome {
        try GatewayMutationCodec.requireLiteral(
            result,
            method: "config.set model",
            name: "key",
            expected: "model"
        )
        let resolvedModel = try GatewayMutationCodec.requireString(
            result,
            method: "config.set model",
            name: "value",
            allowBlank: false
        )
        let warning = try GatewayMutationCodec.requireString(
            result,
            method: "config.set model",
            name: "warning",
            allowBlank: true
        )
        let hasConfirmationRequired = result["confirm_required"] != nil
        let hasConfirmationMessage = result["confirm_message"] != nil
        if !hasConfirmationRequired, !hasConfirmationMessage {
            guard result["scope"] == nil else {
                throw GatewayMutationCodec.malformedResult(
                    method: "config.set model",
                    detail:
                        "confirmation metadata was missing from a scoped response"
                )
            }
            return .applied(
                resolvedModel: resolvedModel,
                warning: warning.isBlank ? nil : warning
            )
        }
        guard hasConfirmationRequired, hasConfirmationMessage else {
            throw GatewayMutationCodec.malformedResult(
                method: "config.set model",
                detail: "confirmation metadata was incomplete"
            )
        }
        let confirmationRequired = try GatewayMutationCodec.requireBool(
            result,
            method: "config.set model",
            name: "confirm_required"
        )
        let confirmationMessage = try GatewayMutationCodec.requireString(
            result,
            method: "config.set model",
            name: "confirm_message",
            allowBlank: !confirmationRequired
        )
        return confirmationRequired
            ? .confirmationRequired(
                resolvedModel: resolvedModel,
                message: confirmationMessage
            )
            : .applied(
                resolvedModel: resolvedModel,
                warning: warning.isBlank ? nil : warning
            )
    }

    func decodeReasoningMutation(
        _ result: JSONValue.Object
    ) throws -> String {
        try GatewayMutationCodec.requireLiteral(
            result,
            method: "config.set reasoning",
            name: "key",
            expected: "reasoning"
        )
        try GatewayMutationCodec.requireLiteral(
            result,
            method: "config.set reasoning",
            name: "scope",
            expected: "session"
        )
        let value = try GatewayMutationCodec.requireString(
            result,
            method: "config.set reasoning",
            name: "value",
            allowBlank: false
        )
        guard reasoningEffortOptions.contains(value) else {
            throw GatewayMutationCodec.malformedResult(
                method: "config.set reasoning",
                detail: "value was not a supported reasoning effort"
            )
        }
        return value
    }

    private func decodeCapabilities(
        _ provider: JSONValue.Object
    ) throws -> [String: ModelCapabilities] {
        guard let value = provider["capabilities"] else {
            return [:]
        }
        guard case .object(let entries) = value else {
            throw malformedOptions("capabilities was not an object")
        }
        var result: [String: ModelCapabilities] = [:]
        for (model, value) in entries {
            guard !model.isBlank, case .object(let capabilities) = value else {
                throw malformedOptions(
                    "capabilities contained an invalid model entry"
                )
            }
            result[model] = ModelCapabilities(
                fast: try strictBool(capabilities, name: "fast"),
                reasoning: try strictBool(capabilities, name: "reasoning")
            )
        }
        return result
    }

    private func decodePricing(
        _ provider: JSONValue.Object
    ) throws -> [String: ModelPricing] {
        guard let value = provider["pricing"] else {
            return [:]
        }
        guard case .object(let entries) = value else {
            throw malformedOptions("pricing was not an object")
        }
        var result: [String: ModelPricing] = [:]
        for (model, value) in entries {
            guard !model.isBlank, case .object(let pricing) = value else {
                throw malformedOptions(
                    "pricing contained an invalid model entry"
                )
            }
            result[model] = ModelPricing(
                input: try strictOptionalString(pricing, name: "input"),
                output: try strictOptionalString(pricing, name: "output"),
                cache: try strictOptionalString(pricing, name: "cache"),
                free: try strictBool(pricing, name: "free")
            )
        }
        return result
    }

    private func strictStringArray(
        _ object: JSONValue.Object,
        name: String
    ) throws -> [String] {
        guard case .array(let values)? = object[name] else {
            throw malformedOptions("\(name) was not an array")
        }
        return try values.enumerated().map { index, value in
            guard let string = value.stringValue, !string.isBlank else {
                throw malformedOptions(
                    "\(name)[\(index)] was not a non-blank string"
                )
            }
            return string
        }
    }

    private func strictOptionalStringArray(
        _ object: JSONValue.Object,
        name: String
    ) throws -> [String] {
        guard object[name] != nil else {
            return []
        }
        return try strictStringArray(object, name: name)
    }

    private func strictBool(
        _ object: JSONValue.Object,
        name: String
    ) throws -> Bool {
        guard case .bool(let value)? = object[name] else {
            throw malformedOptions("\(name) was not true or false")
        }
        return value
    }

    private func strictOptionalBool(
        _ object: JSONValue.Object,
        name: String
    ) throws -> Bool? {
        guard let value = object[name], value != .null else {
            return nil
        }
        guard case .bool(let result) = value else {
            throw malformedOptions("\(name) was not true, false, or null")
        }
        return result
    }

    private func strictOptionalString(
        _ object: JSONValue.Object,
        name: String
    ) throws -> String? {
        guard let value = object[name], value != .null else {
            return nil
        }
        guard let string = value.stringValue else {
            throw malformedOptions("\(name) was not a string or null")
        }
        return string
    }

    private func malformedOptions(_ detail: String) -> HermesError {
        HermesError(
            "Malformed response to model.options: \(detail)",
            retryable: false
        )
    }
}
