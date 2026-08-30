import Foundation
import Observation

@MainActor
@Observable
final class SessionModelControlRuntime {
    var modelOptions: ModelOptions?
    var modelOptionsError: String?
    var isPickerVisible = false
    var isLoadingOptions = false
    var isUpdatingControls = false
    var switchConfirmation: ModelSwitchConfirmation?

    let repository: (any HermesModelMutationServing)?
    private let optionsRuntime: ModelOptionsRuntime
    private let pinRuntime: ModelPinRuntime
    var controlTask: Task<Void, Never>?
    var controlGeneration: Int64 = 0
    var currentSessionOwner: SessionOwner?
    var pendingSwitch: PendingSwitch?

    init(
        repository: (any HermesModelServing)?,
        pinStore: (any ModelPinStoring)? = nil,
        pinWriteQueue: ModelPinWriteQueue? = nil
    ) {
        self.repository = repository
        optionsRuntime = ModelOptionsRuntime(repository: repository)
        pinRuntime = ModelPinRuntime(
            store: pinStore,
            writeQueue: pinWriteQueue,
            permitsInMemoryMutation: repository == nil
        )
    }

    isolated deinit {
        controlTask?.cancel()
    }

    var selectableProviders: [ModelProvider] {
        ModelControlPolicy.selectableProviders(from: modelOptions)
    }

    var pinnedModelsGatewayID: String? {
        get { pinRuntime.gatewayID }
        set { pinRuntime.gatewayID = newValue }
    }

    var pinnedModels: Set<ModelPin> {
        get { pinRuntime.pins }
        set { pinRuntime.pins = newValue }
    }

    var resolvedPinnedModels: Set<ModelPin> {
        ModelControlPolicy.resolvedPins(
            pinnedModels,
            selectableProviders: selectableProviders
        )
    }

    var unresolvedPinnedModels: Set<ModelPin> {
        ModelControlPolicy.unresolvedPins(
            pinnedModels,
            selectableProviders: selectableProviders
        )
    }

    func installFixture(
        options: ModelOptions,
        pins: Set<ModelPin>,
        gatewayID: String?
    ) {
        modelOptions = options
        pinRuntime.installFixture(pins: pins, gatewayID: gatewayID)
        isPickerVisible = true
    }

    func resetGateway(owner: GatewayOwner) {
        resetSessionControls()
        pinRuntime.reset(owner: owner)
    }

    func synchronizeGateway(owner: GatewayOwner) {
        pinRuntime.synchronize(owner: owner)
    }

    func resetSessionControls() {
        optionsRuntime.cancel()
        controlTask?.cancel()
        controlTask = nil
        controlGeneration &+= 1
        currentSessionOwner = nil
        pendingSwitch = nil
        modelOptions = nil
        modelOptionsError = nil
        isPickerVisible = false
        isLoadingOptions = false
        isUpdatingControls = false
        switchConfirmation = nil
    }

    func setPickerVisible(
        _ visible: Bool,
        owner: SessionOwner?,
        onError: @escaping ErrorHandler
    ) {
        guard visible else {
            guard !isUpdatingControls else {
                return
            }
            optionsRuntime.cancel()
            isLoadingOptions = false
            isPickerVisible = false
            return
        }
        guard let owner else {
            onError(
                "Wait for this session to be idle before changing its model."
            )
            return
        }
        currentSessionOwner = owner
        isPickerVisible = true
        modelOptionsError = nil
        onError(nil)
        loadOptions(owner: owner, refresh: false)
    }

    func refreshOptions(owner: SessionOwner?) {
        guard isPickerVisible, let owner else {
            return
        }
        currentSessionOwner = owner
        loadOptions(owner: owner, refresh: true)
    }

    func prepareCompactMenu(owner: SessionOwner?) {
        guard modelOptions == nil,
              !optionsRuntime.isLoading,
              let owner else {
            return
        }
        currentSessionOwner = owner
        loadOptions(
            owner: owner,
            refresh: false,
            requiresVisiblePicker: false
        )
    }

    func restorePins(owner: GatewayOwner) async -> String? {
        await pinRuntime.restore(owner: owner)
    }

    func togglePin(
        gatewayOwner: GatewayOwner?,
        provider: String?,
        model: String,
        onError: @escaping ErrorHandler
    ) {
        pinRuntime.toggle(
            owner: gatewayOwner,
            provider: provider,
            model: model,
            onError: onError
        )
    }

    func canModifyPins(gatewayID: String?) -> Bool {
        pinRuntime.canModify(gatewayID: gatewayID)
    }

    func isModelPinned(provider: String, model: String) -> Bool {
        ModelControlPolicy.isPinned(
            provider: provider,
            model: model,
            pins: pinnedModels,
            selectableProviders: selectableProviders
        )
    }

    func resolvedCurrentProviderSlug(info: SessionInfo?) -> String? {
        ModelControlPolicy.resolvedCurrentProvider(
            info: info,
            selectableProviders: selectableProviders
        )?.slug
    }

    func currentModelSupportsReasoning(info: SessionInfo?) -> Bool {
        guard let model = info?.model else {
            return true
        }
        return ModelControlPolicy.resolvedCurrentProvider(
            info: info,
            selectableProviders: selectableProviders
        )?
            .capabilities[model]?.reasoning ?? true
    }

    private func loadOptions(
        owner: SessionOwner,
        refresh: Bool,
        requiresVisiblePicker: Bool = true
    ) {
        modelOptionsError = nil
        let started = optionsRuntime.load(
            liveSessionID: owner.liveSessionID,
            refresh: refresh
        ) { [weak self] result in
            guard let self,
                  currentSessionOwner == owner,
                  !requiresVisiblePicker || isPickerVisible else {
                return
            }
            isLoadingOptions = false
            switch result {
            case let .success(options):
                modelOptions = options
                modelOptionsError = nil
            case let .failure(message):
                modelOptionsError = message
            }
        }
        isLoadingOptions = started
    }

}
