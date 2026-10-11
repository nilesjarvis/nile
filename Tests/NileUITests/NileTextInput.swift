import XCTest

@MainActor
extension XCTestCase {
    /// Uses native selection so software-keyboard runs do not depend on
    /// simulated hardware Command-A delivery. Never print field contents.
    func replaceText(
        in element: XCUIElement,
        with text: String,
        app: XCUIApplication
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        element.tap()
        let existing = element.value as? String ?? ""
        if !existing.isEmpty, existing != element.placeholderValue {
            element.press(forDuration: 1)
            let selectAll = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "Select All"))
                .firstMatch
            if !selectAll.waitForExistence(timeout: 1) {
                // At accessibility text sizes a long press may only position
                // the caret. Tapping that caret exposes the editing actions.
                element.tap()
            }
            if selectAll.waitForExistence(timeout: 2) {
                selectAll.tap()
            } else {
                // Native triple-tap selects a paragraph. It is a safe fallback
                // only for a single-line field, verified empty before typing.
                guard element.elementType != .textView,
                      !existing.contains("\n"), !existing.contains("\r") else {
                    XCTFail("The native text selection action must be available")
                    return
                }
                element.tap(withNumberOfTaps: 3, numberOfTouches: 1)
            }
            element.typeText(XCUIKeyboardKey.delete.rawValue)
            let cleared = element.value as? String ?? ""
            guard cleared.isEmpty || cleared == element.placeholderValue else {
                XCTFail("The field must be empty before replacement input")
                return
            }
        }
        element.typeText(text)
        let actual = element.value as? String ?? ""
        if element.elementType == .secureTextField {
            XCTAssertTrue(!actual.isEmpty && actual != element.placeholderValue, "The secure field must contain input")
        } else {
            XCTAssertTrue(actual == text, "The field must contain only the replacement text")
        }
    }
}
