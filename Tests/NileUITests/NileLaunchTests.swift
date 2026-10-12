import XCTest

@MainActor
final class NileLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCleanLaunchShowsGatewayOnboardingContract() {
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["niles.settings"].waitForExistence(timeout: 10))
        let addGateway = app.buttons["niles.gateway.add"]
        XCTAssertTrue(addGateway.exists)
        XCTAssertGreaterThanOrEqual(addGateway.frame.height, 44)
        XCTAssertFalse(app.textFields["niles.gateway.name"].exists)
        XCTAssertFalse(app.textFields["niles.gateway.url"].exists)
        XCTAssertFalse(app.secureTextFields["niles.gateway.token"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "onboarding-clean"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(app, name: "onboarding-clean")

        addGateway.tap()
        XCTAssertTrue(
            app.textFields["niles.gateway.name"].waitForExistence(timeout: 3)
        )
        let urlField = app.textFields["niles.gateway.url"]
        XCTAssertTrue(urlField.exists)
        XCTAssertEqual(
            urlField.value as? String,
            "http://127.0.0.1:9119"
        )
        XCTAssertTrue(app.secureTextFields["niles.gateway.token"].exists)

        // Capture before accessing the off-screen controls below. XCTest may
        // scroll a queried descendant into view, which would make this source
        // comparison nondeterministic.
        let formScreenshot = XCTAttachment(screenshot: app.screenshot())
        formScreenshot.name = "onboarding-form"
        formScreenshot.lifetime = .keepAlways
        add(formScreenshot)
        attachAccessibilityHierarchy(app, name: "onboarding-form")

        let connect = app.buttons["niles.gateway.connect"]
        XCTAssertTrue(connect.exists)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 44)
        XCTAssertFalse(connect.isEnabled)
        XCTAssertTrue(
            app.staticTexts[
                "niles.gateway.cleartext_warning"
            ].exists
        )
        let cleartextApproval = app.buttons[
            "niles.gateway.approve_cleartext"
        ]
        XCTAssertTrue(cleartextApproval.exists)
        XCTAssertGreaterThanOrEqual(cleartextApproval.frame.height, 44)

        cleartextApproval.tap()
        XCTAssertTrue(connect.isEnabled)
    }

    func testCleartextOnboardingRequiresExplicitApproval() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let addGateway = app.buttons["niles.gateway.add"]
        XCTAssertTrue(addGateway.waitForExistence(timeout: 10))
        addGateway.tap()

        let warning = app.staticTexts[
            "niles.gateway.cleartext_warning"
        ]
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        XCTAssertTrue(
            warning.label.contains(
                "Use only a trusted simulator, LAN, or VPN."
            )
        )
        let approval = app.buttons["niles.gateway.approve_cleartext"]
        XCTAssertTrue(approval.exists)
        let connect = app.buttons["niles.gateway.connect"]
        XCTAssertFalse(connect.isEnabled)

        approval.tap()

        XCTAssertTrue(connect.isEnabled)
    }

    func testVisualRegressionOnboardingVisualFixtures() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-regression",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["niles.settings"].waitForExistence(timeout: 10)
        )
        let addGateway = app.buttons["niles.gateway.add"]
        XCTAssertTrue(addGateway.exists)

        let cleanScreenshot = XCTAttachment(screenshot: app.screenshot())
        cleanScreenshot.name = "visual-regression-onboarding-clean"
        cleanScreenshot.lifetime = .keepAlways
        add(cleanScreenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-onboarding-clean"
        )

        addGateway.tap()
        XCTAssertTrue(
            app.textFields["niles.gateway.name"].waitForExistence(timeout: 3)
        )
        let urlField = app.textFields["niles.gateway.url"]
        XCTAssertTrue(urlField.exists)
        XCTAssertEqual(
            urlField.value as? String,
            "http://10.0.2.2:9119"
        )
        XCTAssertTrue(app.secureTextFields["niles.gateway.token"].exists)

        let formScreenshot = XCTAttachment(screenshot: app.screenshot())
        formScreenshot.name = "visual-regression-onboarding-form"
        formScreenshot.lifetime = .keepAlways
        add(formScreenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-onboarding-form"
        )
    }

    func testGatewayRemovalRequiresConfirmationAndPreservesProductContract() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-gateway-removal",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["niles.settings"].waitForExistence(timeout: 10)
        )
        let manage = app.buttons["niles.gateway.management"]
        XCTAssertTrue(manage.exists)
        manage.tap()
        XCTAssertTrue(
            app.scrollViews["niles.gateway.list"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Home Hermes"].exists)
        XCTAssertTrue(app.staticTexts["https://hermes.example"].exists)

        let actions = app.buttons["niles.gateway.actions"]
        XCTAssertTrue(actions.exists)
        actions.tap()
        let remove = app.buttons["niles.gateway.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 2))
        remove.tap()

        var dialog = app.staticTexts["Remove Home Hermes?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Conversations remain on Hermes."
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Any Hermes turn already running may continue "
                        + "without Nile following it."
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(app.staticTexts["Home Hermes"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "visual-regression-gateway-removal-dialog"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-gateway-removal-dialog"
        )

        app.buttons["niles.gateway.remove.cancel"].tap()
        XCTAssertFalse(dialog.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Home Hermes"].exists)

        actions.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 2))
        remove.tap()
        dialog = app.staticTexts["Remove Home Hermes?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        let confirm = app.buttons[
            "niles.gateway.remove.confirm"
        ].firstMatch
        XCTAssertTrue(confirm.exists)
        confirm.tap()

        XCTAssertTrue(app.staticTexts["Connect Nile to Hermes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Home Hermes"].exists)
    }

    func testRunningTurnGatewaySwitchRequiresConfirmationAndPreservesProductContract() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-gateway-switch",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["niles.settings"].waitForExistence(timeout: 10)
        )
        let manage = app.buttons["niles.gateway.management"]
        XCTAssertTrue(manage.exists)
        manage.tap()
        XCTAssertTrue(
            app.scrollViews["niles.gateway.list"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Home Hermes"].exists)
        XCTAssertTrue(app.staticTexts["https://home.example"].exists)
        XCTAssertTrue(app.staticTexts["Lab Hermes"].exists)
        XCTAssertTrue(app.staticTexts["https://lab.example"].exists)

        let useLab = app.buttons["Use"].firstMatch
        XCTAssertTrue(useLab.exists)
        useLab.tap()

        var dialog = app.staticTexts["Switch to Lab Hermes?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts[
                "A Hermes turn is still running on the current gateway. "
                    + "It may continue after you switch, but Nile will no longer follow it."
            ].exists
        )
        let dismissSwitch = app.buttons["niles.gateway.switch.dismiss"]
        let confirmSwitch = app.buttons["niles.gateway.switch.confirm"]
        XCTAssertTrue(dismissSwitch.exists)
        XCTAssertTrue(confirmSwitch.exists)
        XCTAssertEqual(dismissSwitch.frame.height, 48, accuracy: 0.5)
        XCTAssertEqual(confirmSwitch.frame.height, 48, accuracy: 0.5)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "visual-regression-gateway-switch-dialog"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-gateway-switch-dialog"
        )

        dismissSwitch.tap()
        XCTAssertFalse(dialog.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Home Hermes"].exists)
        XCTAssertTrue(app.images["Connected"].exists)
        XCTAssertTrue(app.buttons["Use"].exists)

        app.buttons["Use"].firstMatch.tap()
        dialog = app.staticTexts["Switch to Lab Hermes?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        app.buttons["niles.gateway.switch.confirm"].tap()
        let sharing = app.buttons["niles.privacy.sharing.approve"]
        if sharing.waitForExistence(timeout: 3) { sharing.tap() }

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(
                timeout: 5
            )
        )
        XCTAssertFalse(app.scrollViews["niles.settings"].exists)
        XCTAssertFalse(dialog.exists)
    }

    func testVisualRegressionBrandVisualFixtures() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-brand",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(
                timeout: 10
            )
        )
        XCTAssertTrue(app.buttons["niles.session.pill.brand"].isSelected)
        XCTAssertTrue(
            app.staticTexts["Shaping the mobile agent experience"].exists
        )
        XCTAssertTrue(
            app.staticTexts[
                "The neutral graphite theme, violet actions, circular controls, and compact composer are ready for a final visual review."
            ].exists
        )
        XCTAssertEqual(
            app.textFields["niles.composer"].value as? String,
            "Review the final interaction details"
        )
        XCTAssertEqual(
            app.buttons["niles.composer.usage"].value as? String,
            "65 percent context left. 1.9k↑ 760↓ · 4 calls"
        )

        let chat = XCTAttachment(screenshot: app.screenshot())
        chat.name = "visual-regression-brand-chat"
        chat.lifetime = .keepAlways
        add(chat)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-brand-chat"
        )

        app.buttons["niles.sessions.pull_handle"].tap()
        XCTAssertTrue(
            app.buttons["niles.sessions.close"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.otherElements["niles.sessions.sheet"].exists)
        XCTAssertTrue(app.staticTexts["Sessions"].exists)
        XCTAssertTrue(app.staticTexts["1 needs input"].exists)
        XCTAssertTrue(app.buttons["niles.session.search.toggle"].exists)
        XCTAssertFalse(app.textFields["niles.session.search"].exists)
        XCTAssertTrue(app.buttons["niles.session.row.brand"].isSelected)
        XCTAssertTrue(app.buttons["niles.session.row.cli"].exists)

        let sessions = XCTAttachment(screenshot: app.screenshot())
        sessions.name = "visual-regression-brand-sessions"
        sessions.lifetime = .keepAlways
        add(sessions)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-brand-sessions"
        )
    }

    func testSessionSheetLightNativeVisualFixture() {
        XCUIDevice.shared.appearance = .light
        addTeardownBlock {
            XCUIDevice.shared.appearance = .dark
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Light",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(
                timeout: 10
            )
        )
        app.buttons["niles.sessions.pull_handle"].tap()

        let sheet = app.otherElements["niles.sessions.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        XCTAssertLessThan(sheet.frame.height, app.frame.height * 0.55)
        XCTAssertTrue(app.staticTexts["Sessions"].exists)
        XCTAssertTrue(app.staticTexts["1 needs input"].exists)
        XCTAssertTrue(app.buttons["niles.session.row.brand"].isSelected)
        XCTAssertTrue(app.buttons["niles.session.row.cli"].exists)
        XCTAssertTrue(app.buttons["niles.session.search.toggle"].exists)
        XCTAssertFalse(app.textFields["niles.session.search"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "native-session-sheet-light"
        attachment.lifetime = .keepAlways
        add(attachment)
        attachAccessibilityHierarchy(
            app,
            name: "native-session-sheet-light"
        )
    }

    func testSessionSheetSearchPinDismissAndSelect() {
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "--nile-fixture-reduced-motion",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(
                timeout: 10
            )
        )
        app.buttons["niles.sessions.pull_handle"].tap()

        let sheet = app.otherElements["niles.sessions.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))

        let cliPin = app.buttons["niles.session.pin.cli"]
        XCTAssertTrue(cliPin.exists)
        cliPin.tap()
        XCTAssertEqual(cliPin.label, "Unpin session")
        cliPin.tap()
        XCTAssertEqual(cliPin.label, "Pin session")

        app.buttons["niles.sessions.close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 3))
        app.buttons["niles.sessions.pull_handle"].tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))

        app.buttons["niles.session.search.toggle"].tap()
        let search = app.textFields["niles.session.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        search.typeText("CLI")
        XCTAssertTrue(app.buttons["niles.session.row.cli"].exists)
        XCTAssertFalse(app.buttons["niles.session.row.brand"].exists)

        let searchActive = XCTAttachment(screenshot: app.screenshot())
        searchActive.name = "session-sheet-search-active"
        searchActive.lifetime = .keepAlways
        add(searchActive)

        app.buttons["niles.session.search.cancel"].tap()
        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["niles.session.row.brand"].exists)

        app.buttons["niles.session.search.toggle"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("CLI")
        app.buttons["niles.session.row.cli"].tap()
        XCTAssertTrue(
            app.buttons["niles.session.pill.cli"].waitForExistence(
                timeout: 3
            )
        )
        XCTAssertTrue(app.buttons["niles.session.pill.cli"].isSelected)
        XCTAssertFalse(sheet.exists)
    }

    func testVisualRegressionMediaVisualFixture() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-media",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(
                timeout: 10
            )
        )
        XCTAssertTrue(app.staticTexts["20260716_222504_892479"].exists)
        XCTAssertTrue(app.staticTexts["CLI · read-only mirror"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Concatenate the four fragments NILE-, CLI-, FIXTURE-, and OK. Reply with only the concatenated token and no formatting."
            ].exists
        )
        XCTAssertTrue(
            app.staticTexts["NILE-CLI-FIXTURE-OK"].exists
        )
        XCTAssertTrue(app.staticTexts["niles-test-media.png"].exists)
        XCTAssertTrue(
            app.buttons[
                "niles.transcript.attachment./tmp/hermes/images/niles-test-media.png"
            ].exists
        )
        XCTAssertTrue(
            app.otherElements["niles.session.read_only"].exists
        )
        XCTAssertTrue(app.buttons["niles.session.claim"].exists)
        XCTAssertTrue(
            app.staticTexts["CLI session · read-only mirror"].exists
        )
        XCTAssertTrue(
            app.staticTexts["History refreshes every 5 seconds."].exists
        )
        XCTAssertFalse(app.textFields["niles.composer"].exists)

        let media = XCTAttachment(screenshot: app.screenshot())
        media.name = "visual-regression-media"
        media.lifetime = .keepAlways
        add(media)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-media"
        )
    }

    func testVisualRegressionTranscriptSyntaxVisualFixture() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-transcript-syntax",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(
                timeout: 10
            )
        )
        XCTAssertTrue(app.staticTexts["Blocking request fixture"].exists)
        let sessionStatus = app.staticTexts[
            "niles.session.connection_status"
        ]
        XCTAssertTrue(sessionStatus.exists)
        XCTAssertEqual(
            sessionStatus.label,
            "Model unavailable · effort default ▾"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["niles.transcript"].exists
        )
        XCTAssertTrue(
            app.staticTexts["History message 40"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Syntax reference:"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "val name = \"hermes\" // agent"
            ].exists
        )
        XCTAssertTrue(app.textFields["niles.composer"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "visual-regression-transcript-syntax-tail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-transcript-syntax-tail"
        )
    }

    func testVisualRegressionAttachmentVisualFixture() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-attachments",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(
                timeout: 10
            )
        )
        XCTAssertTrue(app.staticTexts["Blocking request fixture"].exists)
        let sessionStatus = app.staticTexts[
            "niles.session.connection_status"
        ]
        XCTAssertTrue(sessionStatus.exists)
        XCTAssertEqual(
            sessionStatus.label,
            "Model unavailable · effort default ▾"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["niles.transcript"].exists
        )
        XCTAssertTrue(
            app.staticTexts["Compare these two references."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.buttons[
                "niles.transcript.attachment./tmp/reference notes.txt"
            ].exists
        )
        XCTAssertTrue(
            app.scrollViews["niles.composer.attachments"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                identifier: "niles.composer.attachment.fixture-photo-one"
            ).firstMatch.exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                identifier: "niles.composer.attachment.fixture-photo-two"
            ).firstMatch.exists
        )
        XCTAssertTrue(app.textFields["niles.composer"].exists)
        XCTAssertTrue(app.buttons["niles.composer.send"].isEnabled)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name =
            "visual-regression-attachment-composer-and-media-cards"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-attachment-composer-and-media-cards"
        )
    }

    func testRecoveryStatesRetainTranscriptAndBlockInteraction() {
        for fixture in [
            (
                argument: "--nile-fixture-reconnecting",
                status: "Reconnecting…",
                screenshot: "gateway-reconnecting"
            ),
            (
                argument: "--nile-fixture-offline",
                status: "Waiting for network…",
                screenshot: "gateway-offline"
            ),
            (
                argument: "--nile-fixture-restoring",
                status: "Restoring session…",
                screenshot: "gateway-restoring"
            ),
        ] {
            let app = XCUIApplication()
            app.launchArguments = [
                fixture.argument,
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
                "-AppleInterfaceStyle", "Dark",
            ]
            app.launch()

            XCTAssertTrue(
                app.descendants(matching: .any)[
                    "niles.session.shell"
                ].waitForExistence(timeout: 10)
            )
            let status = app.staticTexts[
                "niles.session.connection_status"
            ]
            XCTAssertTrue(status.waitForExistence(timeout: 5))
            XCTAssertEqual(status.label, fixture.status)
            XCTAssertTrue(
                app.descendants(matching: .any)["niles.transcript"].exists
            )
            XCTAssertFalse(app.textFields["niles.composer"].exists)
            XCTAssertFalse(
                app.buttons["niles.model.controls"].isEnabled
            )

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = fixture.screenshot
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let settings = app.buttons["niles.session.settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 3))
            settings.tap()
            XCTAssertTrue(app.scrollViews["niles.settings"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.staticTexts["niles.gateway.status"].label, fixture.status)
            let done = app.buttons["niles.settings.done"]
            XCTAssertTrue(done.isEnabled)
            let settingsCapture = XCTAttachment(screenshot: app.screenshot())
            settingsCapture.name = "\(fixture.screenshot)-settings"
            settingsCapture.lifetime = .keepAlways
            add(settingsCapture)
            done.tap()
            XCTAssertTrue(app.scrollViews["niles.settings"].waitForNonExistence(timeout: 3))
            XCTAssertTrue(status.waitForExistence(timeout: 3))
            XCTAssertEqual(status.label, fixture.status)
            app.terminate()
        }
    }

    func testTranscriptScrollRestoresReadingPositionAndReanchorsOnSend() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-transcript-scroll",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let transcript = app.descendants(matching: .any)["niles.transcript"]
        let alphaTail = app.staticTexts["Alpha message 40"]
        let alphaEarlier = app.staticTexts["Alpha message 10"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        XCTAssertTrue(alphaTail.waitForExistence(timeout: 5))
        XCTAssertTrue(alphaTail.isHittable)
        XCTAssertFalse(alphaEarlier.isHittable)
        XCTAssertFalse(
            app.buttons["niles.transcript.jump_to_bottom"].exists
        )

        let syntaxScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        syntaxScreenshot.name = "transcript-syntax-tail"
        syntaxScreenshot.lifetime = .keepAlways
        add(syntaxScreenshot)

        for _ in 0..<4 {
            transcript.swipeDown()
        }
        XCTAssertTrue(
            app.buttons[
                "niles.transcript.jump_to_bottom"
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(alphaEarlier.waitForExistence(timeout: 3))
        XCTAssertTrue(alphaEarlier.isHittable)
        XCTAssertFalse(alphaTail.isHittable)

        app.buttons["niles.sessions.pull_handle"].tap()
        XCTAssertTrue(
            app.buttons["niles.session.row.scroll-beta"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["niles.session.row.scroll-beta"].tap()
        XCTAssertTrue(
            app.staticTexts["Beta message 40"].waitForExistence(timeout: 5)
        )

        app.buttons["niles.sessions.pull_handle"].tap()
        XCTAssertTrue(
            app.buttons["niles.session.row.scroll-alpha"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["niles.session.row.scroll-alpha"].tap()
        XCTAssertTrue(alphaEarlier.waitForExistence(timeout: 5))
        XCTAssertTrue(alphaEarlier.isHittable)
        XCTAssertFalse(alphaTail.isHittable)
        XCTAssertTrue(
            app.buttons["niles.transcript.jump_to_bottom"].exists
        )

        let parkedScreenshot = XCTAttachment(
            screenshot: app.screenshot()
        )
        parkedScreenshot.name = "transcript-reading-position-restored"
        parkedScreenshot.lifetime = .keepAlways
        add(parkedScreenshot)

        app.buttons["niles.transcript.jump_to_bottom"].tap()
        XCTAssertTrue(alphaTail.waitForExistence(timeout: 3))
        XCTAssertTrue(alphaTail.isHittable)
        XCTAssertFalse(
            app.buttons["niles.transcript.jump_to_bottom"].exists
        )

        for _ in 0..<3 {
            transcript.swipeDown()
        }
        XCTAssertTrue(
            app.buttons[
                "niles.transcript.jump_to_bottom"
            ].waitForExistence(timeout: 3)
        )
        let composer = app.textFields["niles.composer"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        composer.typeText("Re-anchor this turn")
        app.buttons["niles.composer.send"].tap()

        XCTAssertTrue(
            app.staticTexts["Re-anchor this turn"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(
            app.buttons["niles.transcript.jump_to_bottom"].exists
        )
    }

    func testOpeningComposerKeyboardKeepsPopulatedTranscriptVisible() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let existingMessage = app.staticTexts[
            "Polish the chat surface and verify the complete interaction."
        ]
        XCTAssertTrue(existingMessage.waitForExistence(timeout: 10))
        XCTAssertTrue(existingMessage.isHittable)

        let composer = app.textFields["niles.composer"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        XCTAssertTrue(
            existingMessage.isHittable,
            "Opening the keyboard must preserve the visible transcript position."
        )
        XCTAssertLessThan(existingMessage.frame.minY, composer.frame.minY)

        composer.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 3),
            "Tapping the focused composer must dismiss the keyboard."
        )

        composer.tap()
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 3),
            "The next composer tap must immediately restore the keyboard."
        )
    }

    func testBroadComposerTapOpensKeyboardImmediatelyAfterSessionSwitch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-transcript-scroll",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let composer = app.textFields["niles.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))

        app.buttons["niles.sessions.pull_handle"].tap()
        let betaSession = app.buttons["niles.session.row.scroll-beta"]
        XCTAssertTrue(betaSession.waitForExistence(timeout: 3))
        betaSession.tap()

        XCTAssertTrue(
            app.staticTexts["Beta message 40"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            keyboard.waitForNonExistence(timeout: 3),
            "Switching sessions must clear the outgoing field focus."
        )

        let composerSurface = app.otherElements["niles.composer.surface"]
        XCTAssertTrue(composerSurface.exists)
        composerSurface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)
        ).tap()
        XCTAssertTrue(
            keyboard.waitForExistence(timeout: 3),
            "The first tap on the broad composer surface must open the keyboard."
        )
    }

    func testRepeatedComposerKeyboardKeepsSwitchedTranscriptVisible() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-transcript-scroll",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let transcript = app.descendants(matching: .any)["niles.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["Alpha message 40"].waitForExistence(timeout: 5)
        )

        app.buttons["niles.sessions.pull_handle"].tap()
        let betaSession = app.buttons["niles.session.row.scroll-beta"]
        XCTAssertTrue(betaSession.waitForExistence(timeout: 3))
        betaSession.tap()

        let tail = app.staticTexts["Beta message 40"]
        XCTAssertTrue(tail.waitForExistence(timeout: 5))
        let composer = app.textFields["niles.composer"]
        XCTAssertTrue(composer.exists)

        for cycle in 1...4 {
            composer.tap()
            XCTAssertTrue(
                app.keyboards.firstMatch.waitForExistence(timeout: 3),
                "Keyboard did not open in cycle \(cycle)."
            )
            XCTAssertTrue(
                tail.exists && tail.isHittable,
                "Populated transcript disappeared in cycle \(cycle)."
            )
            XCTAssertLessThan(tail.frame.minY, composer.frame.minY)

            if cycle == 4 {
                let keyboardVisible = XCTAttachment(
                    screenshot: app.screenshot()
                )
                keyboardVisible.name =
                    "populated-transcript-repeated-keyboard"
                keyboardVisible.lifetime = .keepAlways
                add(keyboardVisible)
                break
            }

            transcript.swipeDown()
            XCTAssertTrue(
                app.keyboards.firstMatch.waitForNonExistence(timeout: 3),
                "Keyboard did not close in cycle \(cycle)."
            )
            let jumpToBottom = app.buttons[
                "niles.transcript.jump_to_bottom"
            ]
            if jumpToBottom.waitForExistence(timeout: 1) {
                jumpToBottom.tap()
            }
            XCTAssertTrue(tail.waitForExistence(timeout: 3))
        }
    }

    func testStreamingAssistantRendersEmptyAndPartialStatesWithoutCursor() {
        for fixture in [
            (
                argument: "--nile-fixture-streaming-empty",
                screenshot: "streaming-assistant-empty",
                expectedText: nil as String?
            ),
            (
                argument: "--nile-fixture-streaming-partial",
                screenshot: "streaming-assistant-partial",
                expectedText: "Live response"
            ),
        ] {
            let app = XCUIApplication()
            app.launchArguments = [
                fixture.argument,
                "--nile-fixture-reduced-motion",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryL",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
                "-AppleInterfaceStyle", "Dark",
            ]
            app.launch()

            XCTAssertTrue(
                app.otherElements["niles.session.shell"].waitForExistence(
                    timeout: 10
                )
            )
            XCTAssertTrue(
                app.otherElements[
                    "niles.transcript.message.streaming-assistant"
                ].exists
            )
            XCTAssertTrue(app.buttons["niles.composer.stop"].exists)
            XCTAssertFalse(
                app.buttons[
                    "niles.transcript.copy.streaming-assistant"
                ].exists
            )
            if let expectedText = fixture.expectedText {
                XCTAssertTrue(app.staticTexts[expectedText].exists)
                XCTAssertTrue(
                    app.images["Streaming inline image"].exists
                )
            }

            let accessibilityHierarchy = app.debugDescription
            XCTAssertFalse(accessibilityHierarchy.contains("▊"))

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = fixture.screenshot
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: accessibilityHierarchy)
            hierarchy.name = "\(fixture.screenshot)-accessibility"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            app.terminate()
        }
    }

    func testStreamingGrowthPreservesAttachedAndDetachedViewport() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-streaming-stress",
            "--nile-fixture-reduced-motion",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let transcript = app.descendants(matching: .any)["niles.transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 10))
        let checkpoint = app.staticTexts["STREAM CHECKPOINT 40"]
        XCTAssertTrue(checkpoint.waitForExistence(timeout: 10))
        XCTAssertFalse(
            app.buttons["niles.transcript.jump_to_bottom"].exists,
            "A growing response must remain attached to the tail."
        )

        transcript.swipeDown()
        let jumpToBottom = app.buttons[
            "niles.transcript.jump_to_bottom"
        ]
        XCTAssertTrue(jumpToBottom.waitForExistence(timeout: 3))
        let streamingParagraphs = app.staticTexts.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "Streaming paragraph"
            )
        )
        guard let parkedParagraph = streamingParagraphs
            .allElementsBoundByIndex
            .first(where: { $0.isHittable })
        else {
            XCTFail("A streamed paragraph should remain visible after detaching.")
            return
        }
        let parkedLabel = parkedParagraph.label
        let parkedY = parkedParagraph.frame.minY

        let composer = app.textFields["niles.composer"]
        XCTAssertTrue(composer.exists)
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let complete = app.staticTexts["STREAM COMPLETE"]
        XCTAssertTrue(complete.waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.buttons["niles.composer.send"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            jumpToBottom.exists,
            "Incoming deltas must not steal a detached reading position."
        )
        let retainedParagraph = app.staticTexts[parkedLabel]
        XCTAssertTrue(
            retainedParagraph.isHittable,
            "Parked paragraph moved outside the viewport: before y "
                + "\(parkedY), after \(retainedParagraph.frame), "
                + "viewport \(transcript.frame)."
        )
        XCTAssertEqual(
            retainedParagraph.frame.minY,
            parkedY,
            accuracy: 8,
            "Streaming and keyboard layout must retain the exact parked offset."
        )

        jumpToBottom.tap()
        XCTAssertFalse(jumpToBottom.waitForExistence(timeout: 3))
        XCTAssertTrue(complete.isHittable)
        XCTAssertLessThanOrEqual(
            complete.frame.maxY,
            composer.frame.minY + 1,
            "The completed response must settle above the composer."
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "streaming-transcript-stress-complete"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testActivePlanStaysCompactAndExpandsToItsChecklist() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-active-plan",
            "--nile-fixture-reduced-motion",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let plan = app.buttons["niles.transcript.active_plan"]
        XCTAssertTrue(plan.waitForExistence(timeout: 10))
        let toolGroup = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "niles.transcript.tool_group."
            )
        ).firstMatch
        XCTAssertTrue(toolGroup.waitForExistence(timeout: 3))
        XCTAssertTrue(
            toolGroup.label.contains(
                "Reading the transcript design guidance without cutting off "
                    + "the important context"
            )
        )
        XCTAssertGreaterThan(
            toolGroup.frame.height,
            76,
            "A long current action must wrap instead of ending in an ellipsis."
        )
        XCTAssertLessThanOrEqual(
            toolGroup.frame.height,
            104,
            "Wrapping one current action must keep the disclosure compact."
        )
        XCTAssertEqual(plan.value as? String, "Collapsed")
        XCTAssertLessThanOrEqual(
            plan.frame.height,
            84,
            "A collapsed plan must remain a compact two-line control."
        )
        XCTAssertTrue(
            plan.label.contains(
                "Keep the current task readable while collapsed without "
                    + "cutting off the end"
            )
        )
        XCTAssertFalse(plan.label.contains("Inspect the transcript layout"))
        XCTAssertFalse(
            plan.label.contains("Verify the expanded checklist spacing")
        )
        let collapsedHeight = plan.frame.height

        let collapsedScreenshot = XCTAttachment(screenshot: app.screenshot())
        collapsedScreenshot.name = "active-plan-collapsed-compact"
        collapsedScreenshot.lifetime = .keepAlways
        add(collapsedScreenshot)

        plan.tap()
        XCTAssertEqual(plan.value as? String, "Expanded")
        XCTAssertTrue(plan.label.contains("Inspect the transcript layout"))
        XCTAssertTrue(
            plan.label.contains("Verify the expanded checklist spacing")
        )
        XCTAssertGreaterThan(plan.frame.height, collapsedHeight)
        XCTAssertLessThanOrEqual(
            plan.frame.height,
            240,
            "Five concise tasks should expand to their content, not the viewport."
        )
        XCTAssertGreaterThan(
            app.descendants(matching: .any)["niles.transcript"].frame.height,
            240,
            "The expanded plan must not consume the transcript viewport."
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "active-plan-expanded-content-sized"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        plan.tap()
        XCTAssertEqual(plan.value as? String, "Collapsed")
        XCTAssertEqual(plan.frame.height, collapsedHeight, accuracy: 1)
    }

    func testMarkdownTablesUseNativeGridAndAccessibilityStack() {
        let gridApp = XCUIApplication()
        gridApp.launchArguments = [
            "--nile-fixture-markdown-table",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        gridApp.launch()

        let gridTranscript = gridApp.descendants(matching: .any)[
            "niles.transcript"
        ]
        XCTAssertTrue(gridTranscript.waitForExistence(timeout: 10))
        let gridTable = gridApp.descendants(matching: .any)[
            "niles.markdown.table"
        ].firstMatch
        XCTAssertTrue(gridTable.waitForExistence(timeout: 5))
        XCTAssertEqual(gridTable.label, "Table, 3 rows, 3 columns")

        let areaHeader = gridApp.descendants(matching: .any)[
            "niles.markdown.table.header.0"
        ].firstMatch
        let statusHeader = gridApp.descendants(matching: .any)[
            "niles.markdown.table.header.1"
        ].firstMatch
        let checksHeader = gridApp.descendants(matching: .any)[
            "niles.markdown.table.header.2"
        ].firstMatch
        XCTAssertTrue(areaHeader.exists)
        XCTAssertTrue(statusHeader.exists)
        XCTAssertTrue(checksHeader.exists)
        XCTAssertEqual(areaHeader.frame.minY, statusHeader.frame.minY, accuracy: 2)
        XCTAssertEqual(statusHeader.frame.minY, checksHeader.frame.minY, accuracy: 2)
        XCTAssertLessThan(areaHeader.frame.minX, statusHeader.frame.minX)
        XCTAssertLessThan(statusHeader.frame.minX, checksHeader.frame.minX)
        XCTAssertLessThanOrEqual(checksHeader.frame.maxX, gridTable.frame.maxX + 1)

        let gridFirstCell = gridApp.descendants(matching: .any)[
            "niles.markdown.table.cell.0.0"
        ].firstMatch
        let gridSecondCell = gridApp.descendants(matching: .any)[
            "niles.markdown.table.cell.0.1"
        ].firstMatch
        XCTAssertEqual(
            gridFirstCell.label,
            "Area: Gateway authentication"
        )
        XCTAssertEqual(gridSecondCell.label, "Status: Ready")
        XCTAssertLessThan(gridFirstCell.frame.minX, gridSecondCell.frame.minX)
        XCTAssertGreaterThan(
            gridFirstCell.frame.height,
            gridSecondCell.frame.height
        )
        XCTAssertFalse(gridApp.debugDescription.contains("─┼─"))

        let gridScreenshot = XCTAttachment(screenshot: gridApp.screenshot())
        gridScreenshot.name = "markdown-table-native-grid"
        gridScreenshot.lifetime = .keepAlways
        add(gridScreenshot)
        attachAccessibilityHierarchy(
            gridApp,
            name: "markdown-table-native-grid"
        )
        gridApp.terminate()

        XCUIDevice.shared.appearance = .light
        addTeardownBlock {
            XCUIDevice.shared.appearance = .dark
        }
        let stackedApp = XCUIApplication()
        stackedApp.launchArguments = [
            "--nile-fixture-markdown-table",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Light",
        ]
        stackedApp.launch()

        let stackedTranscript = stackedApp.descendants(matching: .any)[
            "niles.transcript"
        ]
        XCTAssertTrue(stackedTranscript.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            stackedTranscript.swipeDown()
        }
        let stackedFirstCell = stackedApp.descendants(matching: .any)[
            "niles.markdown.table.cell.0.0"
        ].firstMatch
        let stackedSecondCell = stackedApp.descendants(matching: .any)[
            "niles.markdown.table.cell.0.1"
        ].firstMatch
        XCTAssertTrue(stackedFirstCell.waitForExistence(timeout: 5))
        XCTAssertTrue(stackedSecondCell.exists)
        XCTAssertEqual(
            stackedFirstCell.frame.minX,
            stackedSecondCell.frame.minX,
            accuracy: 2
        )
        XCTAssertGreaterThan(
            stackedSecondCell.frame.minY,
            stackedFirstCell.frame.maxY
        )

        let stackedScreenshot = XCTAttachment(
            screenshot: stackedApp.screenshot()
        )
        stackedScreenshot.name = "markdown-table-accessibility-stack"
        stackedScreenshot.lifetime = .keepAlways
        add(stackedScreenshot)
        attachAccessibilityHierarchy(
            stackedApp,
            name: "markdown-table-accessibility-stack"
        )
    }

    func testInvalidGatewayFailsClosedWithVisibleError() {
        let app = XCUIApplication()
        app.launchArguments = ["--nile-fixture-invalid-gateway"]
        app.launch()

        XCTAssertTrue(
            app.buttons["niles.gateway.add"].waitForExistence(timeout: 10)
        )
        app.buttons["niles.gateway.add"].tap()
        let urlField = app.textFields["niles.gateway.url"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 10))

        app.buttons["niles.gateway.connect"].tap()

        XCTAssertTrue(
            app.staticTexts["niles.gateway.error"].waitForExistence(timeout: 5)
        )
    }

    func testGatewaySignInShowsOriginAndRequiresLoadedPageBeforeContinue() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-gateway-sign-in",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let signIn = app.descendants(matching: .any)[
            "niles.gateway.sign_in"
        ]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sign in to Hermes"].exists)
        XCTAssertTrue(
            app.staticTexts["Page: https://gateway.example"].exists
        )
        let continueButton = app.buttons[
            "niles.gateway.sign_in.continue"
        ]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertTrue(continueButton.isEnabled)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "gateway-dashboard-sign-in"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["niles.gateway.sign_in.cancel"].tap()
        XCTAssertTrue(
            app.scrollViews["niles.settings"].waitForExistence(timeout: 5)
        )
    }

    func testGatewaySignInEnforcesNavigationPolicyInWebKitDelegate() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-gateway-sign-in",
            "--nile-fixture-gateway-sign-in-navigation",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let continueButton = app.buttons[
            "niles.gateway.sign_in.continue"
        ]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        app.links["Continue with identity provider"].tap()
        let externalAlert = app.alerts[
            "Continue to external sign-in?"
        ]
        XCTAssertTrue(externalAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(
            externalAlert.staticTexts[
                "Hermes wants to open https://accounts.example. "
                    + "Only continue if this is the identity provider you expect."
            ].exists
        )
        externalAlert.buttons["Stay here"].tap()

        app.links["Open gateway administration"].tap()
        XCTAssertTrue(
            app.staticTexts[
                "Blocked navigation outside this gateway's configured path"
            ].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(continueButton.isEnabled)
        app.buttons["niles.gateway.sign_in.retry"].tap()
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertTrue(continueButton.isEnabled)
        app.buttons["niles.gateway.sign_in.cancel"].tap()
        XCTAssertTrue(
            app.scrollViews["niles.settings"].waitForExistence(timeout: 5)
        )
    }

    func testSessionFixtureExpandsFiltersAndSelectsWithoutCoordinateTaps() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["niles.session.pill.brand"].isSelected)
        XCTAssertEqual(
            app.staticTexts["niles.sessions.needs_input_count"].label,
            "1 session needs input"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["niles.transcript"].exists
        )
        XCTAssertTrue(
            app.staticTexts[
                "Polish the chat surface and verify the complete interaction."
            ].exists
        )
        let copyResponse = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "niles.transcript.copy."
            )
        ).firstMatch
        XCTAssertTrue(copyResponse.exists)
        let toolGroup = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "niles.transcript.tool_group."
            )
        ).firstMatch
        XCTAssertTrue(toolGroup.exists)
        let collapsed = XCTAttachment(screenshot: app.screenshot())
        collapsed.name = "session-shell-collapsed"
        collapsed.lifetime = .keepAlways
        add(collapsed)
        let collapsedToolGroupMinY = toolGroup.frame.minY

        toolGroup.tap()
        XCTAssertEqual(toolGroup.value as? String, "Expanded")

        let expandedTools = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "niles.transcript.tool."
            )
        )
        XCTAssertEqual(expandedTools.count, 2)
        let unexpectedFirstTapReset = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else {
                    return false
                }
                return element.value as? String == "Collapsed"
            },
            object: toolGroup
        )
        unexpectedFirstTapReset.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [unexpectedFirstTapReset],
                timeout: 0.6
            ),
            .completed
        )
        let expandedToolActions = XCTAttachment(screenshot: app.screenshot())
        expandedToolActions.name = "tool-actions-expanded-downward"
        expandedToolActions.lifetime = .keepAlways
        add(expandedToolActions)
        XCTAssertGreaterThanOrEqual(
            toolGroup.frame.minY,
            collapsedToolGroupMinY - 1
        )
        XCTAssertLessThanOrEqual(
            toolGroup.frame.minY,
            collapsedToolGroupMinY + 8
        )
        toolGroup.tap()
        XCTAssertEqual(toolGroup.value as? String, "Collapsed")
        XCTAssertTrue(
            expandedTools.firstMatch.waitForNonExistence(timeout: 2)
        )
        XCTAssertEqual(expandedTools.count, 0)
        let restoredToolGroupAnchor = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else {
                    return false
                }
                return abs(
                    element.frame.minY - collapsedToolGroupMinY
                ) <= 1
            },
            object: toolGroup
        )
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [restoredToolGroupAnchor],
                timeout: 2
            ),
            .completed
        )
        toolGroup.tap()
        XCTAssertEqual(toolGroup.value as? String, "Expanded")
        XCTAssertEqual(expandedTools.count, 2)
        toolGroup.tap()
        XCTAssertEqual(toolGroup.value as? String, "Collapsed")
        XCTAssertTrue(
            expandedTools.firstMatch.waitForNonExistence(timeout: 2)
        )
        XCTAssertEqual(expandedTools.count, 0)
        copyResponse.tap()
        XCTAssertEqual(copyResponse.label, "Response copied")

        let composer = app.textFields["niles.composer"]
        XCTAssertTrue(composer.exists)
        XCTAssertEqual(composer.placeholderValue, "Ask Nile")
        let send = app.buttons["niles.composer.send"]
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled)
        XCTAssertGreaterThanOrEqual(send.frame.width, 44)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        for identifier in [
            "niles.goal.button",
            "niles.composer.attach_photo",
            "niles.composer.speak_replies",
            "niles.composer.model_name",
            "niles.composer.usage",
            "niles.sessions.pull_handle",
        ] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists, identifier)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, identifier)
        }

        composer.tap()
        composer.typeText("Run the visual checks")
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(
            app.staticTexts["Run the visual checks"].waitForExistence(
                timeout: 3
            )
        )
        XCTAssertTrue(
            app.buttons["niles.composer.stop"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            (app.otherElements["niles.turn.status"].value as? String)?
                .hasPrefix("Working, ") == true
        )

        let dismissNotificationEducation = app.buttons[
            "niles.notifications.education.dismiss"
        ]
        if dismissNotificationEducation.waitForExistence(timeout: 3) {
            dismissNotificationEducation.tap()
            XCTAssertTrue(
                dismissNotificationEducation.waitForNonExistence(timeout: 3)
            )
        }
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        composer.typeText("Also check the spacing")
        let steer = app.buttons["niles.composer.send"]
        XCTAssertTrue(steer.waitForExistence(timeout: 3))
        XCTAssertTrue(steer.isEnabled)
        steer.tap()
        XCTAssertTrue(
            app.staticTexts["Also check the spacing"].waitForExistence(
                timeout: 3
            )
        )
        let stop = app.buttons["niles.composer.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(stop.frame.width, 44)
        XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
        stop.tap()
        XCTAssertTrue(
            app.staticTexts["stop requested"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.buttons["niles.composer.send"].waitForExistence(timeout: 3)
        )

        let transcriptInteractions = XCTAttachment(screenshot: app.screenshot())
        transcriptInteractions.name = "transcript-composer-interactions"
        transcriptInteractions.lifetime = .keepAlways
        add(transcriptInteractions)

        app.buttons["niles.sessions.pull_handle"].tap()
        XCTAssertTrue(
            app.buttons["niles.sessions.close"].waitForExistence(timeout: 3)
        )
        let sessionSheet = app.otherElements["niles.sessions.sheet"]
        XCTAssertTrue(sessionSheet.exists)
        XCTAssertLessThan(sessionSheet.frame.height, app.frame.height * 0.70)
        XCTAssertTrue(app.buttons["niles.session.new"].exists)
        XCTAssertTrue(app.buttons["niles.session.search.toggle"].exists)
        for identifier in [
            "niles.session.new",
            "niles.session.search.toggle",
        ] {
            let control = app.buttons[identifier]
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, identifier)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, identifier)
        }
        XCTAssertFalse(app.textFields["niles.session.search"].exists)
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "session-shell-expanded"
        expanded.lifetime = .keepAlways
        add(expanded)

        let brandRow = app.buttons["niles.session.row.brand"]
        let cliPin = app.buttons["niles.session.pin.cli"]
        XCTAssertTrue(brandRow.isSelected)
        XCTAssertTrue(cliPin.exists)
        cliPin.tap()
        XCTAssertEqual(cliPin.label, "Unpin session")
        XCTAssertTrue(app.buttons["niles.sessions.close"].exists)
        XCTAssertTrue(brandRow.isSelected)
        let movedCliPin = app.buttons["niles.session.pin.cli"]
        XCTAssertTrue(movedCliPin.exists)
        movedCliPin.tap()
        XCTAssertEqual(
            app.buttons["niles.session.pin.cli"].label,
            "Pin session"
        )

        app.buttons["niles.sessions.close"].tap()
        XCTAssertTrue(
            app.buttons["niles.sessions.pull_handle"].waitForExistence(
                timeout: 3
            )
        )
        XCTAssertFalse(sessionSheet.exists)
        app.buttons["niles.sessions.pull_handle"].tap()
        XCTAssertTrue(sessionSheet.waitForExistence(timeout: 3))

        app.buttons["niles.session.search.toggle"].tap()
        let search = app.textFields["niles.session.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("CLI")
        XCTAssertTrue(app.buttons["niles.session.row.cli"].exists)
        XCTAssertFalse(app.buttons["niles.session.row.brand"].exists)
        for control in [
            app.buttons["Clear search"],
            app.buttons["niles.session.search.cancel"],
        ] {
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }

        app.buttons["niles.session.search.cancel"].tap()
        XCTAssertFalse(search.exists)
        XCTAssertTrue(app.buttons["niles.session.row.brand"].exists)
        XCTAssertTrue(app.buttons["niles.session.row.cli"].exists)

        app.buttons["niles.session.search.toggle"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.typeText("CLI")
        app.buttons["niles.session.row.cli"].tap()
        XCTAssertTrue(
            app.buttons["niles.session.pill.cli"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["niles.session.pill.cli"].isSelected)
        XCTAssertTrue(
            app.otherElements["niles.session.read_only"].waitForExistence(
                timeout: 3
            )
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["niles.transcript"].exists
        )

        let claim = app.buttons["niles.session.claim"]
        XCTAssertTrue(claim.exists)
        claim.tap()
        XCTAssertTrue(
            app.otherElements["niles.session.claim.dialog"].waitForExistence(
                timeout: 3
            )
        )
        let confirm = app.buttons["niles.session.claim.confirm"]
        XCTAssertTrue(confirm.exists)
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertEqual(confirm.label, "Claim in Nile")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.otherElements["niles.session.claim.dialog"].exists)
    }

    func testSessionSwitchRetainsTranscriptUntilIncomingContentSettles() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-session-switching",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.staticTexts[
                "Polish the chat surface and verify the complete interaction."
            ].waitForExistence(timeout: 10)
        )
        let strip = app.scrollViews["niles.sessions.strip"]
        XCTAssertTrue(strip.exists)
        strip.swipeLeft()
        let cli = app.buttons["niles.session.pill.cli"]
        XCTAssertTrue(cli.isHittable)
        cli.tap()

        let switchStatus = app.descendants(matching: .any)[
            "niles.session.switch_status"
        ]
        XCTAssertTrue(switchStatus.waitForExistence(timeout: 2))
        XCTAssertEqual(
            switchStatus.label,
            "Switching to CLI handoff"
        )
        XCTAssertFalse(app.textFields["niles.composer"].exists)
        XCTAssertFalse(app.buttons["niles.model.controls"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "Polish the chat surface and verify the complete interaction."
            ].exists
        )

        let retained = XCTAttachment(screenshot: app.screenshot())
        retained.name = "session-switch-retained-transcript"
        retained.lifetime = .keepAlways
        add(retained)
        attachAccessibilityHierarchy(
            app,
            name: "session-switch-retained-transcript"
        )

        XCTAssertTrue(
            app.staticTexts[
                "Audit the gateway ownership boundary."
            ].waitForExistence(timeout: 4)
        )
        XCTAssertFalse(switchStatus.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["niles.transcript"].exists
        )
        XCTAssertFalse(app.textFields["niles.composer"].exists)
        XCTAssertTrue(
            app.otherElements["niles.session.read_only"].exists
        )

        let settled = XCTAttachment(screenshot: app.screenshot())
        settled.name = "session-switch-settled"
        settled.lifetime = .keepAlways
        add(settled)
    }

    func testEmptySessionSwitchUsesAccessibleSkeletonWithReducedMotion() {
        let emptyApp = XCUIApplication()
        emptyApp.launchArguments = [
            "--nile-fixture-session-switching-empty",
            "--nile-fixture-reduced-motion",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        emptyApp.launch()

        XCTAssertTrue(
            emptyApp.buttons["niles.session.pill.brand"]
                .waitForExistence(timeout: 10)
        )
        emptyApp.buttons["niles.session.pill.gateway"].tap()
        let emptySwitchStatus = emptyApp.descendants(matching: .any)[
            "niles.session.switch_status"
        ]
        XCTAssertTrue(emptySwitchStatus.waitForExistence(timeout: 2))
        XCTAssertEqual(
            emptySwitchStatus.label,
            "Switching to Gateway hardening"
        )
        let placeholder = emptyApp.descendants(matching: .any)[
            "niles.session.switch_placeholder"
        ]
        XCTAssertTrue(placeholder.exists)
        XCTAssertEqual(placeholder.label, "Loading conversation")

        let skeleton = XCTAttachment(
            screenshot: emptyApp.screenshot()
        )
        skeleton.name = "session-switch-empty-skeleton-reduced-motion"
        skeleton.lifetime = .keepAlways
        add(skeleton)
        attachAccessibilityHierarchy(
            emptyApp,
            name: "session-switch-empty-skeleton-reduced-motion"
        )
    }

    func testComposerActivityRowIsIntegratedAcrossTurnStates() {
        let states: [(argument: String, label: String?)] = [
            ("idle", nil),
            ("working", "Working"),
            ("stopping", "Stopping"),
            ("needs-input", "Needs input"),
        ]
        var surfaceFrames: [String: CGRect] = [:]
        var composerFrames: [String: CGRect] = [:]

        for state in states {
            let app = XCUIApplication()
            app.launchArguments = [
                "--nile-fixture-composer-\(state.argument)",
                "--nile-fixture-reduced-motion",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryL",
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
                "-AppleInterfaceStyle", "Dark",
            ]
            app.launch()

            let surface = app.otherElements["niles.composer.surface"]
            XCTAssertTrue(
                surface.waitForExistence(timeout: 10),
                "\(state.argument) composer surface exists"
            )
            let composer = app.textFields["niles.composer"]
            XCTAssertTrue(
                composer.exists,
                "\(state.argument) composer remains available"
            )
            surfaceFrames[state.argument] = surface.frame
            composerFrames[state.argument] = composer.frame

            let status = app.otherElements["niles.turn.status"]
            if let label = state.label {
                XCTAssertTrue(
                    status.exists,
                    "\(state.argument) activity row exists"
                )
                let value = status.value as? String
                XCTAssertTrue(
                    value?.hasPrefix("\(label), ") == true,
                    "\(state.argument) preserves the status label"
                )
                XCTAssertTrue(
                    value?.hasSuffix(" elapsed") == true,
                    "\(state.argument) exposes elapsed time"
                )
                XCTAssertTrue(
                    surface.frame.contains(status.frame),
                    "\(state.argument) activity row is inside the composer"
                )
                XCTAssertLessThanOrEqual(
                    status.frame.maxY,
                    composer.frame.minY + 0.5,
                    "\(state.argument) activity row precedes the input region"
                )
            } else {
                XCTAssertFalse(status.exists)
                XCTAssertTrue(app.buttons["niles.composer.send"].exists)
            }

            if state.argument == "stopping" {
                let stop = app.buttons["niles.composer.stop"]
                XCTAssertTrue(stop.exists)
                XCTAssertFalse(stop.isEnabled)
                XCTAssertEqual(stop.value as? String, "Stopping")
            } else if state.label != nil {
                XCTAssertTrue(app.buttons["niles.composer.stop"].exists)
            }

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "composer-activity-\(state.argument)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            attachAccessibilityHierarchy(
                app,
                name: "composer-activity-\(state.argument)"
            )
            app.terminate()
        }

        guard let idleSurface = surfaceFrames["idle"],
              let idleComposer = composerFrames["idle"] else {
            XCTFail("Idle geometry was not captured")
            return
        }
        for state in ["working", "stopping", "needs-input"] {
            guard let surface = surfaceFrames[state],
                  let composer = composerFrames[state] else {
                XCTFail("\(state) geometry was not captured")
                continue
            }
            XCTAssertEqual(surface.maxY, idleSurface.maxY, accuracy: 0.5)
            XCTAssertEqual(composer.midY, idleComposer.midY, accuracy: 0.5)
            XCTAssertGreaterThan(surface.height, idleSurface.height)
            XCTAssertLessThanOrEqual(
                surface.height - idleSurface.height,
                37
            )
        }
    }

    func testConnectedWithoutSessionOffersWorkingPrimaryAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-session-empty",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let emptyState = app.otherElements["niles.session.empty"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No sessions yet"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Create a session to start a conversation with Hermes."
            ].exists
        )
        XCTAssertFalse(app.textFields["niles.composer"].exists)
        let create = app.buttons["niles.session.empty.create"]
        XCTAssertTrue(create.exists)
        XCTAssertTrue(create.isEnabled)
        XCTAssertEqual(create.label, "Create session")
        XCTAssertGreaterThanOrEqual(create.frame.height, 47.9)

        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "session-empty"
        initial.lifetime = .keepAlways
        add(initial)
        attachAccessibilityHierarchy(app, name: "session-empty")

        create.tap()

        XCTAssertFalse(emptyState.waitForExistence(timeout: 1))
        XCTAssertTrue(
            app.buttons["niles.session.pill.fixture-created"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["New session"].exists)
        XCTAssertTrue(app.textFields["niles.composer"].exists)
    }

    func testRightwardFlingFromCollapsedStartCreatesSession() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let strip = app.scrollViews["niles.sessions.strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["niles.session.pill.brand"].isSelected)
        let start = strip.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)
        )
        let end = strip.coordinate(
            withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)
        )

        start.press(
            forDuration: 0.05,
            thenDragTo: end,
            withVelocity: .fast,
            thenHoldForDuration: 0
        )

        XCTAssertTrue(
            app.buttons["niles.session.pill.fixture-created"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["New session"].exists)
        XCTAssertTrue(app.textFields["niles.composer"].exists)
    }

    func testDownwardSwipeOnPullHandleExpandsSessionsWithoutTakingHorizontalScroll() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "--nile-fixture-reduced-motion",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let handle = app.buttons["niles.sessions.pull_handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        XCTAssertEqual(handle.label, "Show all sessions")
        XCTAssertTrue(handle.isHittable)

        let dragStart = handle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let dragDistance = min(
            app.frame.height * 0.35,
            app.frame.maxY - handle.frame.midY - 44
        )
        XCTAssertGreaterThan(dragDistance, 44)
        dragStart.press(
            forDuration: 0.05,
            thenDragTo: dragStart.withOffset(
                CGVector(dx: 0, dy: dragDistance)
            ),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )

        let close = app.buttons["niles.sessions.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["niles.session.row.brand"].isSelected)
        XCTAssertTrue(app.buttons["niles.session.row.cli"].exists)

        close.tap()
        let strip = app.scrollViews["niles.sessions.strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 3))
        strip.swipeLeft()

        let release = app.buttons["niles.session.pill.release"]
        XCTAssertTrue(release.exists)
        XCTAssertTrue(release.isHittable)
        XCTAssertFalse(close.exists)
        XCTAssertFalse(
            app.buttons["niles.session.pill.fixture-created"].exists
        )
        release.tap()
        XCTAssertTrue(release.isSelected)

        handle.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
    }

    func testCreateSwipeRejectsNonStartAndLeftwardDrags() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        var strip = app.scrollViews["niles.sessions.strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        let gateway = app.buttons["niles.session.pill.gateway"]
        XCTAssertTrue(gateway.exists)
        gateway.tap()
        XCTAssertTrue(gateway.isSelected)

        strip.coordinate(
            withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)
        ).press(
            forDuration: 0.05,
            thenDragTo: strip.coordinate(
                withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)
            ),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )

        XCTAssertFalse(
            app.buttons["niles.session.pill.fixture-created"]
                .waitForExistence(timeout: 1)
        )
        XCTAssertTrue(gateway.isSelected)

        app.terminate()
        app.launch()
        strip = app.scrollViews["niles.sessions.strip"]
        XCTAssertTrue(strip.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["niles.session.pill.brand"].isSelected)

        strip.coordinate(
            withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)
        ).press(
            forDuration: 0.05,
            thenDragTo: strip.coordinate(
                withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)
            ),
            withVelocity: .fast,
            thenHoldForDuration: 0
        )

        XCTAssertFalse(
            app.buttons["niles.session.pill.fixture-created"]
                .waitForExistence(timeout: 1)
        )
    }

    func testSessionHeaderActionRailKeepsHeaderVisibleWithPopover() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "--nile-fixture-reduced-motion",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.shell"].waitForExistence(
                timeout: 10
            )
        )
        let actions = [
            ("Session actions", app.buttons["niles.session.actions"]),
            ("Settings", app.buttons["niles.session.settings"]),
        ]
        for (label, action) in actions {
            XCTAssertTrue(action.exists, "\(label) exists")
            XCTAssertEqual(action.label, label)
            XCTAssertTrue(action.isEnabled, "\(label) is enabled")
            XCTAssertEqual(
                action.frame.width,
                48,
                accuracy: 0.5,
                "\(label) accessibility width"
            )
            XCTAssertEqual(
                action.frame.height,
                48,
                accuracy: 0.5,
                "\(label) accessibility height"
            )
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-session-header-action-rail"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "native-session-header-action-rail"
        )

        let sessionIdentity = app.buttons["niles.model.controls"]
        XCTAssertTrue(sessionIdentity.exists)
        let sessionIdentityFrame = sessionIdentity.frame
        app.buttons["niles.session.actions"].tap()
        XCTAssertTrue(
            app.otherElements["niles.session.actions.popover"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            sessionIdentity.exists,
            "Opening session actions must keep the title bar composed."
        )
        XCTAssertEqual(
            sessionIdentity.frame,
            sessionIdentityFrame,
            "Opening session actions must not move the title bar."
        )
        let menuActions = [
            ("Rename session", app.buttons["niles.session.rename"]),
            ("Usage statistics", app.buttons["niles.stats.button"]),
        ]
        for (label, action) in menuActions {
            XCTAssertTrue(
                action.waitForExistence(timeout: 3),
                "\(label) menu action exists"
            )
            XCTAssertEqual(action.label, label)
            XCTAssertTrue(action.isEnabled, "\(label) is enabled")
        }

        let menuScreenshot = XCTAttachment(screenshot: app.screenshot())
        menuScreenshot.name = "native-session-header-action-popover"
        menuScreenshot.lifetime = .keepAlways
        add(menuScreenshot)
        attachAccessibilityHierarchy(
            app,
            name: "native-session-header-action-popover"
        )
    }

    func testSessionRenameUsesSemanticControlsAndUpdatesTheHeader() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let actions = app.buttons["niles.session.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))

        func openRenameDialog() {
            actions.tap()
            let rename = app.buttons["niles.session.rename"]
            XCTAssertTrue(rename.waitForExistence(timeout: 3))
            XCTAssertTrue(rename.isEnabled)
            rename.tap()
        }

        openRenameDialog()

        let dialog = app.otherElements["niles.session.rename.dialog"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts[
                "Only the currently open Hermes session can be renamed."
            ].exists
        )
        let field = app.textFields["niles.session.rename.title"]
        let cancel = app.buttons["niles.session.rename.cancel"]
        let save = app.buttons["niles.session.rename.save"]
        XCTAssertTrue(field.exists)
        XCTAssertEqual(field.value as? String, "Brand polish")
        let initialScreenshot = XCTAttachment(screenshot: app.screenshot())
        initialScreenshot.name = "session-rename-dialog-initial"
        initialScreenshot.lifetime = .keepAlways
        add(initialScreenshot)
        attachAccessibilityHierarchy(
            app,
            name: "session-rename-dialog-initial"
        )
        XCTAssertGreaterThanOrEqual(
            cancel.frame.height,
            47.9,
            "Cancel accessibility height"
        )
        XCTAssertGreaterThanOrEqual(
            cancel.frame.width,
            47.9,
            "Cancel accessibility width"
        )
        XCTAssertGreaterThanOrEqual(
            save.frame.height,
            47.9,
            "Save accessibility height"
        )
        XCTAssertGreaterThanOrEqual(
            save.frame.width,
            47.9,
            "Save accessibility width"
        )

        replaceText(in: field, with: "  Release polish  ", app: app)
        XCTAssertTrue(save.isEnabled)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "session-rename-dialog"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(app, name: "session-rename-dialog")

        save.tap()
        XCTAssertFalse(dialog.waitForExistence(timeout: 1))
        XCTAssertTrue(
            app.staticTexts["Release polish"].waitForExistence(timeout: 3)
        )

        openRenameDialog()
        XCTAssertTrue(dialog.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "Release polish")
        replaceText(in: field, with: "Discard this edit", app: app)
        cancel.tap()
        XCTAssertFalse(dialog.waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Release polish"].exists)
        XCTAssertFalse(app.staticTexts["Discard this edit"].exists)
    }

    func testBusyTerminalMirrorExplainsWhyClaimIsDisabled() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-terminal-busy",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.read_only"].waitForExistence(
                timeout: 10
            )
        )
        XCTAssertTrue(
            app.staticTexts[
                "Stop the terminal turn before claiming."
            ].exists
        )
        let mirror = XCTAttachment(screenshot: app.screenshot())
        mirror.name = "terminal-read-only-working"
        mirror.lifetime = .keepAlways
        add(mirror)
        app.buttons["niles.session.claim"].tap()

        let confirm = app.buttons["niles.session.claim.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertEqual(confirm.label, "Terminal working")
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(
            app.staticTexts[
                "The terminal is still running this session. Stop its current turn and close that terminal before claiming it in Nile."
            ].exists
        )
        let blockedClaim = XCTAttachment(screenshot: app.screenshot())
        blockedClaim.name = "terminal-claim-blocked"
        blockedClaim.lifetime = .keepAlways
        add(blockedClaim)
    }

    func testClarificationChoiceWaitsForExplicitContinue() {
        let app = launchBlockingFixture("clarification")
        let prompt = app.otherElements[
            "niles.blocking.prompt.blocking-clarify-clarify-fixture-1"
        ]
        XCTAssertTrue(prompt.waitForExistence(timeout: 10))
        let choice = app.buttons["niles.blocking.action.Staging"]
        XCTAssertTrue(choice.exists)
        let continueButton = app.buttons["niles.blocking.continue"]
        XCTAssertTrue(continueButton.exists)
        XCTAssertFalse(continueButton.isEnabled)
        for (name, control) in [
            ("Staging", choice),
            ("Production", app.buttons["niles.blocking.action.Production"]),
            ("Continue", continueButton),
        ] {
            XCTAssertTrue(control.exists, "\(name) exists")
            XCTAssertGreaterThanOrEqual(
                control.frame.height,
                44,
                "\(name) accessibility height"
            )
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "visual-regression-blocking-clarification"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-blocking-clarification"
        )

        choice.tap()
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        XCTAssertTrue(
            app.staticTexts["Decision answered"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Answered: Staging"].exists)
    }

    func testApprovalFIFOAndPermanentConfirmationAreSelectorDriven() {
        let app = launchBlockingFixture("approvals")
        let first = app.otherElements[
            "niles.blocking.prompt.blocking-approval-1"
        ]
        let second = app.otherElements[
            "niles.blocking.prompt.blocking-approval-2"
        ]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(
            app.staticTexts[
                "Waiting for an earlier approval in this session."
            ].exists
        )

        let always = app.buttons["niles.blocking.action.always"]
        XCTAssertTrue(always.isEnabled)
        always.tap()
        let confirm = app.buttons["niles.blocking.always_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts[
                "Hermes will also allow future commands that match this approval pattern. Only continue if you trust those matching commands."
            ].exists
        )
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["Always allowed"].waitForExistence(timeout: 3)
        )
        let deny = app.buttons["niles.blocking.action.deny"]
        XCTAssertTrue(deny.isEnabled)
        deny.tap()
        XCTAssertTrue(app.staticTexts["Denied"].waitForExistence(timeout: 3))
    }

    func testSecureSudoAndSecretEntryNeverExposePlainTextSemantics() {
        for kind in ["sudo", "secret"] {
            let app = launchBlockingFixture(kind)
            let enterSecurely = app.buttons["Enter securely"]
            XCTAssertTrue(enterSecurely.waitForExistence(timeout: 10))
            enterSecurely.tap()

            let field = app.secureTextFields["niles.blocking.secure_entry"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            XCTAssertEqual(field.label, "Secure response")
            field.tap()
            field.typeText("fixture-response")
            let submit = app.buttons["niles.blocking.secure_submit"]
            XCTAssertTrue(submit.isEnabled)
            submit.tap()

            let safeStatus = kind == "sudo"
                ? "Password sent"
                : "Secret sent"
            XCTAssertTrue(
                app.staticTexts[safeStatus].waitForExistence(timeout: 3)
            )
            XCTAssertFalse(
                app.staticTexts["fixture-response"].exists
            )
            app.terminate()
        }
    }

    func testMalformedBlockingRequestIsVisibleAndNonActionable() {
        let app = launchBlockingFixture("invalid")
        XCTAssertTrue(
            app.otherElements[
                "niles.blocking.prompt.blocking-invalid-1"
            ].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Input request unavailable"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "This request cannot be answered safely."
            ].exists
        )
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@",
                    "niles.blocking.action"
                )
            ).count,
            0
        )
    }

    func testAttachmentFixtureMatchesComposerStripAndPhotoOnlySend() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-attachments",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["niles.composer.attachments"].waitForExistence(
                timeout: 10
            )
        )
        let first = app.descendants(matching: .any).matching(
            identifier: "niles.composer.attachment.fixture-photo-one"
        ).firstMatch
        let second = app.descendants(matching: .any).matching(
            identifier: "niles.composer.attachment.fixture-photo-two"
        ).firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertTrue(second.exists)
        XCTAssertTrue(app.buttons["niles.composer.attach_photo"].exists)
        XCTAssertTrue(
            app.buttons[
                "niles.transcript.attachment./tmp/reference notes.txt"
            ].exists
        )

        let fixture = XCTAttachment(screenshot: app.screenshot())
        fixture.name = "attachment-composer-and-media-cards"
        fixture.lifetime = .keepAlways
        add(fixture)

        app.buttons[
            "niles.composer.attachment.remove.fixture-photo-one"
        ].tap()
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                identifier: "niles.composer.attachment.fixture-photo-one"
            ).firstMatch.waitForExistence(timeout: 1)
        )
        XCTAssertTrue(second.exists)

        let send = app.buttons["niles.composer.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertFalse(
            app.descendants(matching: .any).matching(
                identifier: "niles.composer.attachment.fixture-photo-two"
            ).firstMatch.waitForExistence(timeout: 1)
        )
        XCTAssertTrue(
            app.images["reference.jpg"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.buttons["niles.composer.stop"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.buttons["niles.composer.attach_photo"].isEnabled)
    }

    func testModelPickerIsSearchableSessionScopedAndDismissible() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-model-picker",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.model_picker.surface"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["niles.model_picker.reasoning"].exists)
        XCTAssertTrue(app.textFields["niles.model_picker.search"].exists)
        XCTAssertTrue(
            app.buttons[
                "niles.model_picker.option.google.gemini-3-pro"
            ].exists
        )
        XCTAssertTrue(
            app.staticTexts[
                "Changes apply only to this session, from the next message."
            ].exists
        )
        XCTAssertTrue(app.staticTexts["Pinned (2)"].exists)
        let resolvedPin = app.buttons[
            "niles.model_picker.pinned_pin.6:google|14:gemini-3-flash"
        ]
        XCTAssertTrue(resolvedPin.exists)
        XCTAssertEqual(resolvedPin.value as? String, "Pinned")
        let unavailablePin = app.buttons[
            "niles.model_picker.pinned_pin.15:legacy-provider|13:retired-model"
        ]
        XCTAssertTrue(unavailablePin.exists)
        XCTAssertEqual(unavailablePin.value as? String, "Pinned")

        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "session-model-picker"
        initial.lifetime = .keepAlways
        add(initial)

        unavailablePin.tap()
        XCTAssertTrue(app.staticTexts["Pinned (1)"].waitForExistence(timeout: 3))

        let search = app.textFields["niles.model_picker.search"]
        search.tap()
        search.typeText("openai")
        XCTAssertTrue(
            app.buttons[
                "niles.model_picker.option.openai.gpt-5-mini"
            ].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(
            app.buttons[
                "niles.model_picker.option.google.gemini-3-pro"
            ].isHittable
        )
        let catalogPin = app.buttons[
            "niles.model_picker.pin.6:openai|10:gpt-5-mini"
        ]
        XCTAssertTrue(catalogPin.waitForExistence(timeout: 3))
        XCTAssertEqual(catalogPin.value as? String, "Not pinned")
        catalogPin.tap()
        let pinCommitted = expectation(
            for: NSPredicate(format: "value == %@", "Pinned"),
            evaluatedWith: catalogPin
        )
        wait(for: [pinCommitted], timeout: 3)

        app.buttons["niles.model_picker.close"].tap()
        XCTAssertFalse(
            app.otherElements["niles.model_picker.surface"]
                .waitForExistence(timeout: 1)
        )
        XCTAssertTrue(app.otherElements["niles.session.shell"].exists)
        XCTAssertTrue(app.buttons["niles.model.controls"].exists)
    }

    func testModelPickerProviderDisclosureAndModelSelectionRespondToTaps() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-model-picker",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.model_picker.surface"]
                .waitForExistence(timeout: 10)
        )
        let currentProvider = app.buttons[
            "niles.model_picker.provider.google"
        ]
        let currentModel = app.buttons[
            "niles.model_picker.option.google.gemini-3-pro"
        ]
        XCTAssertTrue(currentProvider.isEnabled)
        XCTAssertTrue(currentModel.exists)

        currentProvider.tap()
        let currentProviderCollapsed = expectation(
            for: NSPredicate(format: "value == %@", "Collapsed"),
            evaluatedWith: currentProvider
        )
        wait(for: [currentProviderCollapsed], timeout: 3)

        let targetProvider = app.buttons[
            "niles.model_picker.provider.openai"
        ]
        XCTAssertTrue(targetProvider.waitForExistence(timeout: 3))
        XCTAssertTrue(targetProvider.isEnabled)
        targetProvider.tap()
        let targetProviderExpanded = expectation(
            for: NSPredicate(format: "value == %@", "Expanded"),
            evaluatedWith: targetProvider
        )
        wait(for: [targetProviderExpanded], timeout: 3)

        let nonCurrentModel = app.buttons[
            "niles.model_picker.option.openai.gpt-5-mini"
        ]
        XCTAssertTrue(nonCurrentModel.waitForExistence(timeout: 3))
        XCTAssertTrue(nonCurrentModel.isEnabled)

        targetProvider.tap()
        let targetProviderCollapsed = expectation(
            for: NSPredicate(format: "value == %@", "Collapsed"),
            evaluatedWith: targetProvider
        )
        wait(for: [targetProviderCollapsed], timeout: 3)
        currentProvider.tap()
        let currentProviderExpanded = expectation(
            for: NSPredicate(format: "value == %@", "Expanded"),
            evaluatedWith: currentProvider
        )
        wait(for: [currentProviderExpanded], timeout: 3)

        let alternateModel = app.buttons[
            "niles.model_picker.option.google.gemini-3-flash"
        ]
        XCTAssertTrue(alternateModel.waitForExistence(timeout: 3))
        XCTAssertTrue(alternateModel.isHittable)
        alternateModel.tap()
        XCTAssertTrue(
            app.activityIndicators["niles.model_switch.progress"]
                .waitForExistence(timeout: 3)
        )
    }

    func testComposerModelMenuUsesNativeProviderHierarchyAndSelectsModel() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-model-picker",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.model_picker.surface"]
                .waitForExistence(timeout: 10)
        )
        app.buttons["niles.model_picker.close"].tap()
        XCTAssertFalse(
            app.otherElements["niles.model_picker.surface"]
                .waitForExistence(timeout: 1)
        )

        let modelMenu = app.buttons["niles.composer.model_name"]
        XCTAssertTrue(modelMenu.waitForExistence(timeout: 3))
        XCTAssertTrue(modelMenu.isEnabled)
        modelMenu.tap()

        let google = app.buttons[
            "niles.composer.model_menu.provider.google"
        ]
        let openAI = app.buttons[
            "niles.composer.model_menu.provider.openai"
        ]
        XCTAssertTrue(google.waitForExistence(timeout: 3))
        XCTAssertTrue(openAI.exists)
        google.tap()

        let current = app.buttons[
            "niles.composer.model_menu.option.google.gemini-3-pro"
        ]
        let alternate = app.buttons[
            "niles.composer.model_menu.option.google.gemini-3-flash"
        ]
        XCTAssertTrue(current.waitForExistence(timeout: 3))
        XCTAssertTrue(alternate.exists)
        let hierarchy = XCTAttachment(screenshot: app.screenshot())
        hierarchy.name = "native-composer-model-menu"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        alternate.tap()

        let switching = expectation(
            for: NSPredicate(format: "enabled == false"),
            evaluatedWith: modelMenu
        )
        wait(for: [switching], timeout: 3)
        XCTAssertEqual(
            modelMenu.value as? String,
            "gemini-3-pro, switching"
        )
        XCTAssertFalse(
            app.otherElements["niles.model_picker.surface"].exists
        )
    }

    func testVisualRegressionModelPickerVisualFixture() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-model-picker",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.model_picker.surface"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["niles.model_picker.reasoning"].exists)
        XCTAssertTrue(app.staticTexts["default"].exists)
        XCTAssertTrue(app.textFields["niles.model_picker.search"].exists)
        XCTAssertTrue(
            app.buttons[
                "niles.model_picker.option.provider.reasoning-model"
            ].exists
        )
        XCTAssertTrue(
            app.staticTexts[
                "Update Hermes to enable safe per-session reasoning changes."
            ].exists
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "visual-regression-model-picker-app-popup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-model-picker-app-popup"
        )
    }

    func testVisualRegressionRenameSessionVisualFixture() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-rename",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.otherElements["niles.session.rename.dialog"]
                .waitForExistence(timeout: 10)
        )
        let title = app.textFields["niles.session.rename.title"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.value as? String, "Blocking request fixture")
        XCTAssertTrue(
            app.staticTexts[
                "Only the currently open Hermes session can be renamed."
            ].exists
        )
        XCTAssertGreaterThanOrEqual(
            app.buttons["niles.session.rename.cancel"].frame.height,
            47.9
        )
        XCTAssertGreaterThanOrEqual(
            app.buttons["niles.session.rename.save"].frame.height,
            47.9
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "visual-regression-rename-session-dialog"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-rename-session-dialog"
        )
    }

    func testGoalQuickStartSheetPreservesComposerDraftAndBudget() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-goal-create",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["niles.goal.sheet"].waitForExistence(
                timeout: 10
            )
        )
        XCTAssertTrue(app.staticTexts["Set a standing goal"].exists)
        let objective = app.textViews["niles.goal.objective"]
        XCTAssertTrue(objective.exists)
        XCTAssertEqual(objective.value as? String, "keep my draft")
        app.buttons["Fix and verify"].tap()
        app.buttons["niles.goal.budget.10"].tap()

        XCTAssertTrue(
            (objective.value as? String)?.hasPrefix(
                "Find and fix the current problem"
            ) == true
        )
        XCTAssertTrue(
            app.staticTexts[
                "Saves 10 turns as this Hermes profile's default."
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["niles.goal.start"].isEnabled)

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "visual-regression-goal-quick-start-sheet"
        capture.lifetime = .keepAlways
        add(capture)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-goal-quick-start-sheet"
        )
    }

    func testBiometricLockCoversPresentedSheetAfterBackground() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-goal-create",
            "--nile-fixture-biometric-lock-fail-on-return",
            "--nile-fixture-reduced-motion",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let goalSheet = app.scrollViews["niles.goal.sheet"]
        XCTAssertTrue(goalSheet.waitForExistence(timeout: 10))
        XCTAssertTrue(goalSheet.isHittable)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(
            app.wait(for: .runningBackground, timeout: 5)
        )
        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 5)
        )

        let appLock = app.otherElements["niles.security.biometric_lock"]
        XCTAssertTrue(appLock.waitForExistence(timeout: 10))
        let unlock = app.buttons["niles.security.biometric_lock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        XCTAssertTrue(unlock.isHittable)
        XCTAssertFalse(goalSheet.isHittable)
        XCTAssertFalse(app.buttons["Done"].isHittable)

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "biometric-lock-over-presented-sheet"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testActiveGoalCardIsCompactAndDetailsExpand() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-goal-active",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let card = app.buttons["niles.goal.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Active  ·  7/20 turns"].exists)
        XCTAssertTrue(app.buttons["niles.goal.pause"].exists)

        let compact = XCTAttachment(screenshot: app.screenshot())
        compact.name = "visual-regression-goal-active-card"
        compact.lifetime = .keepAlways
        add(compact)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-goal-active-card"
        )

        let quickStart = app.buttons[
            "niles.session.launchpad.quick_start.0"
        ]
        XCTAssertTrue(quickStart.exists)
        quickStart.tap()
        XCTAssertEqual(
            app.textFields["niles.composer"].value as? String,
            "Help me make a clear plan for "
        )

        card.tap()
        XCTAssertTrue(
            app.scrollViews["niles.goal.sheet"].waitForExistence(
                timeout: 3
            )
        )
        let objective = app.buttons["niles.goal.details_objective"]
        XCTAssertTrue(objective.exists)
        XCTAssertEqual(objective.value as? String, "Collapsed")
        let details = XCTAttachment(screenshot: app.screenshot())
        details.name = "visual-regression-goal-active-details-sheet"
        details.lifetime = .keepAlways
        add(details)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-goal-active-details-sheet"
        )
        objective.tap()
        XCTAssertEqual(objective.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Collapse objective"].exists)
    }

    func testContextBreakdownShowsCurrentUsageComposition() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-usage-context",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["niles.context.sheet"].waitForExistence(
                timeout: 10
            )
        )
        XCTAssertTrue(app.staticTexts["Context"].exists)
        XCTAssertTrue(app.staticTexts["124.0k of 200.0k · 62%"].exists)
        XCTAssertTrue(app.staticTexts["Conversation"].exists)
        XCTAssertTrue(app.staticTexts["free"].exists)

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "visual-regression-context-breakdown-sheet"
        capture.lifetime = .keepAlways
        add(capture)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-context-breakdown-sheet"
        )
    }

    func testGatewayStatsShowsProfileActivityAndHeatmap() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-stats",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["niles.stats.sheet"].waitForExistence(
                timeout: 10
            )
        )
        XCTAssertTrue(app.staticTexts["Activity & usage"].exists)
        XCTAssertTrue(app.staticTexts["Recorded tokens"].exists)
        XCTAssertTrue(app.staticTexts["356.3k"].exists)
        XCTAssertTrue(app.otherElements["niles.stats.heatmap"].exists)
        XCTAssertTrue(
            app.buttons["niles.stats.period.30"].isSelected
        )

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "visual-regression-gateway-stats-sheet"
        capture.lifetime = .keepAlways
        add(capture)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-gateway-stats-sheet"
        )
    }

    func testActiveDelegationOverviewExpandsAgentDetailsAndControls() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-delegation-active",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let overview = app.otherElements["niles.delegation.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Delegated work"].exists)
        XCTAssertTrue(app.staticTexts["1 queued · 1 working"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Running simulator checks"
                )
            ).firstMatch.exists
        )

        let compact = XCTAttachment(screenshot: app.screenshot())
        compact.name = "delegation-active-overview"
        compact.lifetime = .keepAlways
        add(compact)

        app.staticTexts["Delegated work"].tap()
        let primary = app.descendants(matching: .any)[
            "niles.delegation.agent.id:fixture-agent-one"
        ]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        primary.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "niles.delegation.detail.id:fixture-agent-one"
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "niles.delegation.stop.id:fixture-agent-one"
            ].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "niles.delegation.open_child.id:fixture-agent-one"
            ].exists
        )

        let details = XCTAttachment(screenshot: app.screenshot())
        details.name = "delegation-active-agent-details"
        details.lifetime = .keepAlways
        add(details)
    }

    func testVisualRegressionDelegationMixedVisualFixture() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-visual-delegation-mixed",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let overview = app.otherElements["niles.delegation.overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.staticTexts["1 working · 1 failed · 1 finished"].exists
        )
        app.staticTexts["Delegated work"].tap()

        let running = app.descendants(matching: .any)[
            "niles.delegation.agent.ui-row"
        ]
        XCTAssertTrue(running.waitForExistence(timeout: 3))
        running.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "niles.delegation.detail.ui-row"
            ].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "niles.delegation.stop.ui-row"
            ].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "niles.delegation.open_child.ui-row"
            ].exists
        )

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "visual-regression-delegation-mixed"
        capture.lifetime = .keepAlways
        add(capture)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-delegation-mixed"
        )
    }

    func testSettledDelegationRendersAsTranscriptHistory() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-delegation-settled",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertFalse(
            app.otherElements["niles.delegation.overview"].exists
        )
        let group = app.otherElements.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "niles.delegation.group."
            )
        ).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 finished"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "All delegated checks matched."
                )
            ).firstMatch.exists
        )

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "delegation-settled-transcript"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testConnectedSettingsHierarchyUsesProgressiveDisclosure() {
        XCUIDevice.shared.appearance = .light
        addTeardownBlock {
            XCUIDevice.shared.appearance = .dark
        }
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-hermes-voice",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Light",
        ]
        app.launch()

        XCTAssertTrue(app.scrollViews["niles.settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["HERMES"].exists)
        XCTAssertTrue(app.staticTexts["SECURITY"].exists)
        XCTAssertFalse(app.staticTexts["https://voice-fixture.example"].exists)

        let rootCapture = XCTAttachment(screenshot: app.screenshot())
        rootCapture.name = "connected-settings-light"
        rootCapture.lifetime = .keepAlways
        add(rootCapture)

        app.buttons["niles.gateway.management"].tap()
        XCTAssertTrue(app.scrollViews["niles.gateway.list"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["https://voice-fixture.example"].exists)
        let gatewayCapture = XCTAttachment(screenshot: app.screenshot())
        gatewayCapture.name = "gateway-management-light"
        gatewayCapture.lifetime = .keepAlways
        add(gatewayCapture)
    }

    func testHermesVoiceFixtureLoadsAppliesAndUpdatesGlobalSummary() {
        XCUIDevice.shared.appearance = .dark
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-hermes-voice",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let entry = app.buttons["niles.voice.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        let settingsCapture = XCTAttachment(screenshot: app.screenshot())
        settingsCapture.name = "connected-settings-dark"
        settingsCapture.lifetime = .keepAlways
        add(settingsCapture)
        entry.tap()

        XCTAssertTrue(
            app.otherElements["niles.voice.sheet"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Edge TTS"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Current voice · en-US-AriaNeural"
            ].exists
        )
        XCTAssertTrue(
            app.staticTexts[
                "This changes the global Hermes voice for every app and client using this gateway."
            ].exists
        )
        let apply = app.buttons["niles.voice.apply"]
        XCTAssertTrue(apply.exists)
        XCTAssertFalse(apply.isEnabled)
        let dragHandle = app.buttons["niles.voice.drag_handle"]
        let selectedPreset = app.buttons["Aria · US"]
        let close = app.buttons["Close"]
        for (name, control) in [
            ("Drag handle", dragHandle),
            ("Selected voice preset", selectedPreset),
            ("Apply voice", apply),
            ("Close", close),
        ] {
            XCTAssertTrue(control.exists, "\(name) exists")
            XCTAssertGreaterThanOrEqual(
                control.frame.height,
                44,
                "\(name) accessibility height"
            )
        }

        let visualCapture = XCTAttachment(screenshot: app.screenshot())
        visualCapture.name = "visual-regression-hermes-voice-settings"
        visualCapture.lifetime = .keepAlways
        add(visualCapture)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-hermes-voice-settings"
        )

        app.buttons["Guy · US"].tap()
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        XCTAssertTrue(
            app.staticTexts[
                "Current voice · en-US-GuyNeural"
            ].waitForExistence(timeout: 3)
        )

        app.buttons["Close"].tap()
        XCTAssertFalse(
            app.otherElements["niles.voice.sheet"]
                .waitForExistence(timeout: 1)
        )
        XCTAssertTrue(
            app.staticTexts["Edge TTS · en-US-GuyNeural"].exists
        )
    }

    func testTalkFixtureKeepsTranscriptPrivateAndDrivesPauseResumeEnd() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-talk",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let entry = app.buttons["niles.talk.entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()

        XCTAssertTrue(
            app.otherElements["niles.talk.surface"]
                .waitForExistence(timeout: 5)
        )
        let status = app.staticTexts["niles.talk.status"]
        XCTAssertTrue(status.exists)
        XCTAssertEqual(status.value as? String, "Listening…")
        XCTAssertFalse(app.textFields["niles.composer"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "Polish the chat surface and verify the complete interaction."
            ].exists
        )
        XCTAssertTrue(app.otherElements["niles.talk.orb"].exists)
        for (name, control) in [
            ("Close", app.buttons["niles.talk.close"]),
            ("Transcript", app.buttons["niles.talk.view_transcript"]),
            ("Pause", app.buttons["niles.talk.pause"]),
            ("End", app.buttons["niles.talk.end"]),
        ] {
            XCTAssertTrue(control.exists, "\(name) exists")
            XCTAssertGreaterThanOrEqual(
                control.frame.width,
                44,
                "\(name) accessibility width"
            )
            XCTAssertGreaterThanOrEqual(
                control.frame.height,
                44,
                "\(name) accessibility height"
            )
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "visual-regression-talk-listening"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        attachAccessibilityHierarchy(
            app,
            name: "visual-regression-talk-listening"
        )

        app.buttons["niles.talk.pause"].tap()
        XCTAssertTrue(
            app.buttons["niles.talk.resume"].waitForExistence(timeout: 3)
        )
        XCTAssertEqual(status.value as? String, "Microphone paused")

        app.buttons["niles.talk.resume"].tap()
        XCTAssertTrue(
            app.buttons["niles.talk.pause"].waitForExistence(timeout: 3)
        )
        XCTAssertEqual(status.value as? String, "Listening…")

        app.buttons["niles.talk.end"].tap()
        XCTAssertFalse(
            app.otherElements["niles.talk.surface"]
                .waitForExistence(timeout: 1)
        )
        XCTAssertTrue(app.textFields["niles.composer"].exists)
    }

    func testSessionFixtureTogglesAutomaticSpokenReplies() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-sessions",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let toggle = app.buttons["niles.composer.speak_replies"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "Off")
        XCTAssertFalse(toggle.isSelected)

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "On")
        XCTAssertTrue(toggle.isSelected)

        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "Off")
        XCTAssertFalse(toggle.isSelected)
    }

    func testNotificationEducationUsesApprovedCopyAndDismisses() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-notification-education",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        let education = app.descendants(matching: .any)[
            "niles.notifications.education"
        ]
        XCTAssertTrue(education.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Stay in the loop"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Get notified when a long-running session finishes or needs a decision."
            ].exists
        )
        XCTAssertTrue(
            app.buttons[
                "niles.notifications.education.enable"
            ].exists
        )
        let dismiss = app.buttons[
            "niles.notifications.education.dismiss"
        ]
        XCTAssertTrue(dismiss.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "notification-education"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        dismiss.tap()
        XCTAssertFalse(education.waitForExistence(timeout: 1))
        XCTAssertTrue(app.otherElements["niles.session.shell"].exists)
    }

    private func launchBlockingFixture(_ kind: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-blocking-\(kind)",
            "--nile-fixture-reduced-motion",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryL",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()
        return app
    }

    private func attachAccessibilityHierarchy(
        _ app: XCUIApplication,
        name: String
    ) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "\(name)-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
