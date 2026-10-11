import XCTest

extension NileLaunchTests {
    func testGatewaySharingConsentShowsDestinationAndCanBeDeclined() {
        let app = XCUIApplication()
        app.launchArguments = ["--nile-fixture-reduced-motion", "-AppleLanguages", "(en)"]
        app.launch()
        let add = app.buttons["niles.gateway.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let field = app.textFields["niles.gateway.url"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: "https://privacy-review.example/hermes", app: app)
        app.buttons["niles.gateway.connect"].tap()

        let destination = app.staticTexts["niles.privacy.sharing.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertEqual(destination.label, "https://privacy-review.example/hermes")
        let allow = app.buttons["niles.privacy.sharing.approve"]
        XCTAssertTrue(allow.exists)
        XCTAssertGreaterThanOrEqual(allow.frame.height, 44)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "gateway-data-sharing-consent"
        capture.lifetime = .keepAlways
        self.add(capture)
        app.buttons["niles.privacy.sharing.cancel"].tap()
        XCTAssertTrue(app.buttons["niles.gateway.connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["niles.gateway.error"].exists)
        XCTAssertFalse(app.otherElements["niles.session.shell"].exists)
    }

    func testPrivacyAndBundledNoticesAreAccessibleBeforeConnecting() {
        let app = XCUIApplication()
        app.launchArguments = ["--nile-fixture-reduced-motion", "-AppleLanguages", "(en)"]
        app.launch()
        let privacy = app.buttons["niles.privacy.entry"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(privacy.frame.height, 44)
        privacy.tap()
        let disclosure = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "Nile connects to the Hermes gateway")
        ).firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "privacy-and-data"
        capture.lifetime = .keepAlways
        add(capture)
        let clear = app.buttons["niles.privacy.clear"]
        revealPrivacyControl(clear, in: app)
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        app.buttons["niles.privacy.clear.confirm"].firstMatch.tap()
        let cleared = app.staticTexts["niles.privacy.cleared"]
        revealPrivacyControl(cleared, in: app)
        XCTAssertTrue(cleared.waitForExistence(timeout: 10))
        let notices = app.buttons["niles.privacy.notices"]
        revealPrivacyControl(notices, in: app)
        XCTAssertTrue(notices.exists)
        notices.tap()
        let freetype = app.buttons["FreeType"]
        XCTAssertTrue(freetype.waitForExistence(timeout: 5))
        freetype.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "The FreeType Project LICENSE")).firstMatch.waitForExistence(timeout: 5))
    }

    private func revealPrivacyControl(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.waitForExistence(timeout: 0.5), element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Privacy control must be reachable by scrolling")
    }
}
