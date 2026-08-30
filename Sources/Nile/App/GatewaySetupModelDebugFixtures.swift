#if DEBUG
import Foundation

@MainActor
extension GatewaySetupModel {
    @discardableResult
    func installDebugFixtures(arguments: [String]) -> Bool {
        let fixtureArguments = NileDebugFixturePolicy.arguments(from: arguments)
        if fixtureArguments.contains(
            "--nile-fixture-android-visual-parity"
        ) {
            dashboardURL = "http://10.0.2.2:9119"
            usesAndroidVisualParityCopy = true
        }
        if fixtureArguments.contains("--nile-fixture-invalid-gateway") {
            dashboardURL = "gateway.local:9119"
        }
        guard fixtureArguments.contains(
            "--nile-fixture-gateway-sign-in"
        ) else {
            return false
        }
        let fixtureURL = URL(
            string: "https://gateway.example/hermes/login"
        )!
        gatewaySignInURL = fixtureURL
        let fixtureEndpoint = try! GatewayEndpoint.parse(
            "https://gateway.example/hermes"
        )
        pendingSignIn = PendingSignIn(
            connection: GatewayConnection(
                endpoint: fixtureEndpoint,
                token: ""
            ),
            name: "Hermes gateway",
            profile: nil
        )
        let navigationLinks = fixtureArguments.contains(
            "--nile-fixture-gateway-sign-in-navigation"
        ) ? """
            <p><a href="https://accounts.example/login" style="color:#fff">Continue with identity provider</a></p>
            <p><a href="https://gateway.example/admin" style="color:#fff">Open gateway administration</a></p>
            """ : ""
        signInFixtureHTML = """
            <!doctype html>
            <html>
              <head><meta name="viewport" content="width=device-width"></head>
              <body style="background:#212121;color:#fff;font:16px -apple-system;padding:24px">
                <h2>Hermes dashboard</h2>
                <p style="color:#bababa">Sign in to continue to your gateway.</p>
                <label>Email</label>
                <input aria-label="Email" style="display:block;margin:10px 0 18px;padding:12px;width:90%">
                <label>Password</label>
                <input aria-label="Password" type="password" style="display:block;margin:10px 0 22px;padding:12px;width:90%">
                <button style="padding:12px 24px">Sign in</button>
                \(navigationLinks)
              </body>
            </html>
            """
        state = .idle
        return true
    }
}
#endif
