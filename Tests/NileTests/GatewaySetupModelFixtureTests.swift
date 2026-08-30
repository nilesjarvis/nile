import XCTest
@testable import Nile

extension GatewaySetupModelTests {
    func testUsesIOSLoopbackOutsideAndroidVisualParityFixture() {
        let model = GatewaySetupModel(
            arguments: [],
            automaticallyRestore: false
        )

        XCTAssertEqual(model.dashboardURL, "http://127.0.0.1:9119")
    }

    func testAndroidVisualParityFixtureUsesPinnedGatewayEndpoint() {
        let model = GatewaySetupModel(
            arguments: ["--nile-fixture-android-visual-parity"],
            automaticallyRestore: false
        )

        XCTAssertEqual(model.dashboardURL, "http://10.0.2.2:9119")
    }

    func testGatewaySignInFixtureSuppressesAutomaticProfileRestoration() async {
        let store = ModelGatewayStore()
        let model = GatewaySetupModel(
            arguments: ["--nile-fixture-gateway-sign-in"],
            profileStore: store,
            connectionClient: ModelGatewayClient()
        )
        await Task.yield()

        let loadCount = await store.loadCount
        XCTAssertEqual(loadCount, 0)
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(
            model.gatewaySignInURL?.absoluteString,
            "https://gateway.example/hermes/login"
        )
        XCTAssertEqual(model.pendingSignIn?.name, "Hermes gateway")
        XCTAssertTrue(
            model.signInFixtureHTML?.contains("Hermes dashboard") == true
        )
    }
}
