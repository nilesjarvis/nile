import Foundation
import XCTest
@testable import Nile

extension GatewaySetupModelTests {
    func connectedModel(
        voice: ModelHermesVoiceService
    ) throws -> GatewaySetupModel {
        let active = try GatewayProfile(
            id: "gateway-active",
            name: "Active",
            baseURL: "https://active.example",
            token: "active-secret"
        )
        let model = GatewaySetupModel(
            arguments: [],
            profileStore: ModelGatewayStore(
                profiles: [active],
                activeID: active.id
            ),
            sharingConsentStore: AcceptedGatewaySharingConsentStore(),
            connectionClient: ModelGatewayClient(),
            hermesVoiceService: voice,
            automaticallyRestore: false
        )
        model.state = .connected
        model.savedGateways = [active]
        model.activeGatewayID = active.id
        model.connectedProfile = active
        model.isSettingsVisible = true
        return model
    }

    func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !(await condition()) {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for model state")
                return
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(2))
        }
    }
}
