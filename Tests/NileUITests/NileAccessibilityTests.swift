import XCTest

@MainActor
final class NileAccessibilityTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLargeTextReducedMotionAndKeyboardJourneyRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--nile-fixture-reduced-motion",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-AppleInterfaceStyle", "Dark",
        ]
        app.launch()

        XCTAssertTrue(
            app.scrollViews["niles.settings"].waitForExistence(timeout: 10)
        )
        let reducedMotion = app.descendants(matching: .any)[
            "niles.accessibility.reduced_motion"
        ]
        XCTAssertTrue(reducedMotion.exists)
        XCTAssertEqual(reducedMotion.value as? String, "Enabled")

        let title = app.staticTexts["Connect Nile to Hermes"]
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThan(
            title.frame.height,
            30,
            "The accessibility lane must run at a scaled content size."
        )

        let addGateway = app.buttons["niles.gateway.add"]
        XCTAssertTrue(addGateway.exists)
        XCTAssertGreaterThanOrEqual(addGateway.frame.height, 44)
        addGateway.tap()

        let name = app.textFields["niles.gateway.name"]
        let url = app.textFields["niles.gateway.url"]
        let token = app.secureTextFields["niles.gateway.token"]
        let cancel = app.buttons["Cancel"]
        let connect = app.buttons["niles.gateway.connect"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertTrue(url.exists)
        XCTAssertTrue(token.exists)
        XCTAssertTrue(cancel.exists)
        XCTAssertTrue(connect.exists)

        let formScreenshot = XCTAttachment(screenshot: app.screenshot())
        formScreenshot.name = "accessibility-large-text-form"
        formScreenshot.lifetime = .keepAlways
        add(formScreenshot)

        for (label, field) in [
            ("gateway name", name),
            ("dashboard URL", url),
            ("session token", token),
        ] {
            XCTAssertGreaterThanOrEqual(
                field.frame.height,
                44,
                "\(label) must preserve a 44-point touch target."
            )
        }
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        XCTAssertGreaterThanOrEqual(connect.frame.height, 44)

        name.tap()
        name.typeText("Accessible gateway")
        let next = app.keyboards.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH[c] %@ OR label ==[c] %@",
                "next",
                "next"
            )
        ).firstMatch
        XCTAssertTrue(
            next.waitForExistence(timeout: 2),
            "The name field must expose the Next keyboard action."
        )
        name.typeText("\n")
        url.typeText("/accessibility")
        XCTAssertTrue((url.value as? String)?.hasSuffix("/accessibility") == true)
        XCTAssertTrue(
            next.waitForExistence(timeout: 2),
            "The URL field must expose the Next keyboard action."
        )
        url.typeText("\n")
        token.typeText("fixture-private-input")
        let done = app.keyboards.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH[c] %@ OR label ==[c] %@",
                "done",
                "done"
            )
        ).firstMatch
        XCTAssertTrue(
            done.exists,
            "The secure token field must expose the Done keyboard action."
        )
        XCTAssertFalse(
            app.debugDescription.contains("fixture-private-input"),
            "Secure input must not appear in accessibility output."
        )
        token.typeText("\n")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 2),
            "Done must dismiss the keyboard without submitting a blocked form."
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "accessibility-large-text-keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "accessibility-large-text-keyboard-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
