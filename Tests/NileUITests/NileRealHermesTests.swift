import XCTest

@MainActor
final class NileRealHermesTests: XCTestCase {
    private var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProductionGatewayJourneyThroughClaimControlsTurnStopAndGoal() throws {
        try requirePhase("journey")
        guard environment["NILE_LAB_REAL_HERMES"] == "1" else {
            throw XCTSkip(
                "Real-Hermes tests run only through scripts/test-lab/run.sh."
            )
        }
        let gatewayURL = try requiredEnvironment("NILE_LAB_GATEWAY_URL")
        let gatewayToken = try requiredEnvironment("NILE_LAB_GATEWAY_TOKEN")
        let cliMarker = try requiredEnvironment("NILE_LAB_CLI_MARKER")
        let modelTarget = try requiredEnvironment(
            "NILE_LAB_MODEL_SWITCH_TARGET"
        )
        let goalProgressMarker = try requiredEnvironment(
            "NILE_LAB_GOAL_PROGRESS_MARKER"
        )
        let goalDoneMarker = try requiredEnvironment(
            "NILE_LAB_GOAL_DONE_MARKER"
        )
        let goalMaxTurns = try requiredEnvironment(
            "NILE_LAB_GOAL_MAX_TURNS"
        )
        guard let goalBudget = Int(goalMaxTurns), (1...100).contains(goalBudget)
        else {
            XCTFail("NILE_LAB_GOAL_MAX_TURNS was not an integer from 1 to 100.")
            throw MissingLabInput()
        }

        let app = XCUIApplication()
        app.launchArguments = stableLaunchArguments
        app.launch()

        connect(
            app: app,
            gatewayURL: gatewayURL,
            token: gatewayToken + "-invalid"
        )
        let error = app.staticTexts["niles.gateway.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 30))
        XCTAssertTrue(error.label.localizedCaseInsensitiveContains("token"))
        XCTAssertFalse(
            app.descendants(matching: .any)["niles.session.shell"].exists
        )
        attachCheckpoint(app, name: "00-auth-rejected")

        replaceText(in: app.secureTextFields["niles.gateway.token"], with: gatewayToken, app: app)
        app.buttons["niles.gateway.connect"].tap()

        let readOnly = app.descendants(matching: .any)[
            "niles.session.read_only"
        ]
        XCTAssertTrue(readOnly.waitForExistence(timeout: 120))
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", cliMarker)
            ).firstMatch.waitForExistence(timeout: 30)
        )
        XCTAssertTrue(
            app.buttons["niles.session.claim"].waitForExistence(timeout: 30)
        )
        XCTAssertFalse(app.textFields["niles.composer"].exists)
        attachCheckpoint(app, name: "01-cli-read-only")

        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "NILE-PERSISTED-REFRESH-OK"
                )
            ).firstMatch.waitForExistence(timeout: 30)
        )
        XCTAssertFalse(app.textFields["niles.composer"].exists)
        attachCheckpoint(app, name: "01b-persisted-history-refreshed")

        app.buttons["niles.session.claim"].tap()
        let confirmClaim = app.buttons["niles.session.claim.confirm"]
        XCTAssertTrue(confirmClaim.waitForExistence(timeout: 10))
        attachCheckpoint(app, name: "02-claim-confirmation")
        confirmClaim.tap()

        let composer = app.textFields["niles.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 120))
        XCTAssertTrue(
            app.buttons["niles.model.controls"].waitForExistence(timeout: 30)
        )
        attachCheckpoint(app, name: "03-claimed")

        switchModel(app, to: modelTarget)
        attachCheckpoint(app, name: "04-model-switched")

        switchReasoning(app, to: "low")
        attachCheckpoint(app, name: "05-reasoning-switched")

        replaceText(in: composer, with: "Reply with exactly NILE-IOS-REAL-TURN-OK", app: app)
        let send = app.buttons["niles.composer.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "NILE-IOS-REAL-TURN-OK"
                )
            ).firstMatch.waitForExistence(timeout: 300)
        )
        XCTAssertTrue(
            app.buttons["niles.model.controls"].waitForExistence(timeout: 30)
        )
        attachCheckpoint(app, name: "06-real-turn")

        replaceText(
            in: app.textFields["niles.composer"],
            with: "Write a long numbered explanation of every month of the year.",
            app: app
        )
        app.buttons["niles.composer.send"].tap()
        let stop = app.buttons["niles.composer.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 30))
        stop.tap()
        XCTAssertTrue(
            app.staticTexts["stop requested"].waitForExistence(timeout: 60)
        )
        XCTAssertTrue(
            app.buttons["niles.composer.send"].waitForExistence(timeout: 60)
        )
        attachCheckpoint(app, name: "07-run-stopped")

        let goalPrompt =
            "Complete this goal in exactly two turns without tools. "
            + "On the first turn reply with: \(goalProgressMarker) unfinished. "
            + "Do not use the done marker. On the automatic continuation reply "
            + "with: \(goalDoneMarker) complete, and explicitly state that the "
            + "goal is achieved."
        let goalButton = app.buttons["niles.goal.button"]
        XCTAssertTrue(goalButton.waitForExistence(timeout: 60))
        XCTAssertTrue(goalButton.isEnabled)
        goalButton.tap()
        XCTAssertTrue(
            app.scrollViews["niles.goal.sheet"].waitForExistence(timeout: 15)
        )
        replaceText(in: app.textViews["niles.goal.objective"], with: goalPrompt, app: app)
        let budget = app.buttons["niles.goal.budget.\(goalBudget)"]
        XCTAssertTrue(budget.waitForExistence(timeout: 10))
        budget.tap()
        let startGoal = app.buttons["niles.goal.start"]
        XCTAssertTrue(startGoal.isEnabled)
        startGoal.tap()

        XCTAssertTrue(
            app.buttons["niles.goal.card"].waitForExistence(timeout: 60)
        )
        attachCheckpoint(app, name: "08-goal-started")
        try waitForTextOccurrences(
            app,
            containing: goalProgressMarker,
            minimum: 2,
            timeout: 300
        )
        attachCheckpoint(app, name: "09-goal-first-turn")
        try waitForTextOccurrences(
            app,
            containing: goalDoneMarker,
            minimum: 2,
            timeout: 300
        )
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label BEGINSWITH %@", "Finished")
            ).firstMatch.waitForExistence(timeout: 120)
        )
        XCTAssertFalse(
            app.buttons["niles.composer.stop"].waitForExistence(timeout: 3)
        )
        attachCheckpoint(app, name: "10-goal-finished")

        app.terminate()
    }

    func testPersistedGatewayFailsClosedWhileHermesIsOffline() throws {
        try requirePhase("offline")
        let app = XCUIApplication()
        app.launchArguments = stableLaunchArguments
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "niles.session.shell"
            ].waitForExistence(timeout: 45)
        )
        XCTAssertFalse(app.textFields["niles.composer"].exists)
        XCTAssertFalse(app.buttons["niles.model.controls"].isEnabled)
        attachCheckpoint(app, name: "11-offline-restoration")
        app.terminate()
    }

    func testRelaunchReconnectsAndRestoresClaimedSession() throws {
        try requirePhase("reconnect")
        let cliMarker = try requiredEnvironment("NILE_LAB_CLI_MARKER")
        let app = XCUIApplication()
        app.launchArguments = stableLaunchArguments
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "niles.session.shell"
            ].waitForExistence(timeout: 120)
        )
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", cliMarker)
            ).firstMatch.waitForExistence(timeout: 30)
        )
        XCTAssertTrue(
            app.textFields["niles.composer"].waitForExistence(timeout: 30)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["niles.session.read_only"].exists
        )
        attachCheckpoint(app, name: "12-relaunch-reconnected")
        app.terminate()
    }

    private var stableLaunchArguments: [String] {
        [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
    }

    private func requiredEnvironment(_ name: String) throws -> String {
        guard let value = environment[name], !value.isEmpty else {
            XCTFail("The real-Hermes runner omitted \(name).")
            throw MissingLabInput()
        }
        return value
    }

    private func requirePhase(_ expected: String) throws {
        guard environment["NILE_LAB_REAL_HERMES"] == "1" else {
            throw XCTSkip(
                "Real-Hermes tests run only through scripts/test-lab/run.sh."
            )
        }
        let phase = try requiredEnvironment("NILE_LAB_PHASE")
        guard phase == expected else {
            throw XCTSkip("This invocation runs the \(phase) phase.")
        }
    }

    private func connect(
        app: XCUIApplication,
        gatewayURL: String,
        token: String
    ) {
        XCTAssertTrue(
            app.scrollViews["niles.settings"].waitForExistence(timeout: 30)
        )
        app.buttons["niles.gateway.add"].tap()
        let urlField = app.textFields["niles.gateway.url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10))
        replaceText(in: urlField, with: gatewayURL, app: app)
        replaceText(in: app.secureTextFields["niles.gateway.token"], with: token, app: app)
        let cleartext = app.buttons["niles.gateway.approve_cleartext"]
        if gatewayURL.hasPrefix("http://"), cleartext.exists { cleartext.tap() }
        let connect = app.buttons["niles.gateway.connect"]
        XCTAssertTrue(connect.isEnabled)
        connect.tap()
        let sharing = app.buttons["niles.privacy.sharing.approve"]
        if sharing.waitForExistence(timeout: 5) { sharing.tap() }
    }

    private func switchModel(
        _ app: XCUIApplication,
        to modelTarget: String
    ) {
        let controls = app.buttons["niles.model.controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 120))
        XCTAssertTrue(controls.isEnabled)
        controls.tap()

        let picker = app.otherElements["niles.model_picker.surface"]
        XCTAssertTrue(picker.waitForExistence(timeout: 60))
        let search = app.textFields["niles.model_picker.search"]
        replaceText(in: search, with: modelTarget, app: app)
        let modelOption = app.buttons[
            "niles.model_picker.option.openrouter.\(modelTarget)"
        ]
        XCTAssertTrue(modelOption.waitForExistence(timeout: 60))
        XCTAssertTrue(modelOption.isEnabled)
        modelOption.tap()

        let confirmation = app.buttons["niles.model_switch.confirm"]
        if confirmation.waitForExistence(timeout: 10) {
            XCTAssertTrue(confirmation.isEnabled)
            confirmation.tap()
        }
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "switched this session to \(modelTarget)"
                )
            ).firstMatch.waitForExistence(timeout: 120)
        )
        XCTAssertFalse(picker.waitForExistence(timeout: 3))
    }

    private func switchReasoning(
        _ app: XCUIApplication,
        to effort: String
    ) {
        let controls = app.buttons["niles.model.controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 120))
        XCTAssertTrue(controls.isEnabled)
        controls.tap()
        let picker = app.otherElements["niles.model_picker.surface"]
        XCTAssertTrue(picker.waitForExistence(timeout: 60))
        let selector = app.buttons["niles.model_picker.reasoning"]
        XCTAssertTrue(selector.waitForExistence(timeout: 60))
        XCTAssertTrue(selector.isEnabled)
        selector.tap()
        let option = app.buttons["niles.model_picker.reasoning.\(effort)"]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        let label = effort == "none" ? "off" : effort.lowercased()
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "set this session's reasoning effort to \(label)"
                )
            ).firstMatch.waitForExistence(timeout: 120)
        )
        XCTAssertFalse(picker.waitForExistence(timeout: 3))
    }

    private func waitForTextOccurrences(
        _ app: XCUIApplication,
        containing text: String,
        minimum: Int,
        timeout: TimeInterval
    ) throws {
        let query = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", text)
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                (object as? XCUIElementQuery)?.count ?? 0 >= minimum
            },
            object: query
        )
        guard XCTWaiter.wait(
            for: [expectation],
            timeout: timeout
        ) == .completed else {
            XCTFail(
                "Expected at least \(minimum) text elements containing \(text)."
            )
            throw MissingLabInput()
        }
    }

    private func attachCheckpoint(
        _ app: XCUIApplication,
        name: String
    ) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}

private struct MissingLabInput: Error {}
