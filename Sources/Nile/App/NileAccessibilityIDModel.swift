extension NileAccessibilityID {
    static let commandPalette = "niles.command.palette"
    static let modelPicker = "niles.model_picker"
    static let modelPickerSurface = "niles.model_picker.surface"
    static let modelPickerScrim = "niles.model_picker.scrim"
    static let closeModelPicker = "niles.model_picker.close"
    static let modelSearch = "niles.model_picker.search"
    static let reasoningSelector = "niles.model_picker.reasoning"
    static let modelOptionsRetry = "niles.model_picker.retry"
    static let modelCatalogStatus = "niles.model_picker.catalog_status"
    static let modelSwitchProgress = "niles.model_switch.progress"
    static let sessionControlError = "niles.model_switch.error"
    static let modelConfirmation = "niles.model.confirmation"
    static let modelConfirmationBody =
        "niles.model_switch.confirmation_body"
    static let confirmModelSwitch = "niles.model_switch.confirm"
    static let modelControls = "niles.model.controls"

    static func commandCard(_ id: String) -> String {
        "niles.command.\(id)"
    }

    static func commandPaletteItem(_ display: String) -> String {
        "niles.command.palette.\(display)"
    }

    static func reasoningOption(_ effort: String) -> String {
        "niles.model_picker.reasoning.\(effort)"
    }

    static func composerModelProvider(_ slug: String) -> String {
        "niles.composer.model_menu.provider.\(slug)"
    }

    static func composerModelOption(
        provider: String,
        model: String
    ) -> String {
        "niles.composer.model_menu.option.\(provider).\(model)"
    }

    static func modelProvider(_ slug: String) -> String {
        "niles.model_picker.provider.\(slug)"
    }

    static func modelOption(provider: String, model: String) -> String {
        "niles.model_picker.option.\(provider).\(model)"
    }

    static func modelPinAction(provider: String?, model: String) -> String {
        "niles.model_picker.pin.\(modelPinKey(provider: provider, model: model))"
    }

    static func pinnedModelOption(
        provider: String?,
        model: String
    ) -> String {
        "niles.model_picker.pinned_model.\(modelPinKey(provider: provider, model: model))"
    }

    static func pinnedModelPinAction(
        provider: String?,
        model: String
    ) -> String {
        "niles.model_picker.pinned_pin.\(modelPinKey(provider: provider, model: model))"
    }

    private static func modelPinKey(
        provider: String?,
        model: String
    ) -> String {
        "\(provider?.count ?? -1):\(provider ?? "")|\(model.count):\(model)"
    }
}
