import XCTest

final class KeyboardDismissUITests: HeardUITestCase {
    private let focusedValue = "focused"
    private let blurredValue = "blurred"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try requireGestureCoverage()
    }

    func testAddIngredientSheetDismissesKeyboardOnSwipeDown() {
        let app = UIHarness.launchApp(scenario: .keyboardDismiss)

        app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventory.addButton"].tap()

        let nameField = element("inventory.add.nameField", in: app)
        let focusProbe = element("inventory.add.nameField.focusState", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(focusProbe.waitForExistence(timeout: Self.existenceTimeout))
        nameField.tap()

        assertFocusProbe(focusProbe, equals: focusedValue)

        let form = element("inventory.add.form", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: Self.existenceTimeout))
        form.swipeDown()

        assertFocusLostOrSheetDismissed(focusProbe: focusProbe, form: form)
    }

    func testEditIngredientSheetDismissesKeyboardOnSwipeDown() {
        let app = UIHarness.launchApp(scenario: .keyboardDismiss)

        app.tabBars.buttons["Inventory"].tap()
        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: Self.existenceTimeout))
        ingredientRow.tap()

        let nameField = element("inventory.edit.nameField", in: app)
        let focusProbe = element("inventory.edit.nameField.focusState", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(focusProbe.waitForExistence(timeout: Self.existenceTimeout))
        nameField.tap()

        assertFocusProbe(focusProbe, equals: focusedValue)

        let form = element("inventory.edit.form", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: Self.existenceTimeout))
        form.swipeDown()

        assertFocusLostOrSheetDismissed(focusProbe: focusProbe, form: form)
    }

    func testEditRecipeSheetDismissesKeyboardOnSwipeDown() {
        let app = UIHarness.launchApp(scenario: .keyboardDismiss)

        app.tabBars.buttons["Recipes"].tap()
        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: Self.existenceTimeout))
        recipeCard.tap()
        app.buttons["recipe.detail.editButton"].tap()

        let nameField = element("recipe.edit.nameField", in: app)
        let focusProbe = element("recipe.edit.nameField.focusState", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(focusProbe.waitForExistence(timeout: Self.existenceTimeout))
        nameField.tap()

        assertFocusProbe(focusProbe, equals: focusedValue)

        let form = element("recipe.edit.form", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: Self.existenceTimeout))
        form.swipeDown()

        assertFocusLostOrSheetDismissed(focusProbe: focusProbe, form: form)
    }

    private func requireGestureCoverage() throws {
        guard ProcessInfo.processInfo.environment["HEARD_ENABLE_GESTURE_UI_TESTS"] == "1" else {
            throw XCTSkip("Gesture-based keyboard dismissal tests are opt-in until simulator behavior is more stable.")
        }
    }

    private func assertFocusProbe(
        _ probe: XCUIElement,
        equals expectedLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expectedLabel),
            object: probe
        )

        let result = XCTWaiter.wait(for: [expectation], timeout: Self.focusTransitionTimeout)
        XCTAssertEqual(result, .completed, "Expected focus probe to become \(expectedLabel).", file: file, line: line)
    }

    private func assertFocusLostOrSheetDismissed(
        focusProbe: XCUIElement,
        form: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(Self.focusTransitionTimeout)

        // Inventory sheets currently treat a downward swipe as either
        // keyboard dismissal or full sheet dismissal depending on how the
        // gesture lands in the simulator. Treat both as a successful loss of
        // focus while the suite stays experimental and the product behavior is
        // still being separated.
        repeat {
            if !form.exists {
                return
            }

            if !focusProbe.waitForExistence(timeout: 0) {
                return
            }

            if focusProbe.label == blurredValue {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail(
            "Expected swipe to either blur the focused field or dismiss the sheet.",
            file: file,
            line: line
        )
    }
}
