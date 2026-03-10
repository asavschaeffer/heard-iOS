import XCTest

final class KeyboardDismissUITests: XCTestCase {
    private let focusedValue = "focused"
    private let blurredValue = "blurred"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try requireGestureCoverage()
    }

    func testAddIngredientSheetDismissesKeyboardOnSwipeDown() {
        let app = UIHarness.launchApp()

        app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventory.addButton"].tap()

        let nameField = element("inventory.add.nameField", in: app)
        let focusProbe = element("inventory.add.nameField.focusState", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertTrue(focusProbe.waitForExistence(timeout: 2))
        nameField.tap()

        assertFocusProbe(focusProbe, equals: focusedValue)

        let form = element("inventory.add.form", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 2))
        form.swipeDown()

        assertFocusProbe(focusProbe, equals: blurredValue)
    }

    func testEditIngredientSheetDismissesKeyboardOnSwipeDown() {
        let app = UIHarness.launchApp()

        app.tabBars.buttons["Inventory"].tap()
        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: 2))
        ingredientRow.tap()

        let nameField = element("inventory.edit.nameField", in: app)
        let focusProbe = element("inventory.edit.nameField.focusState", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertTrue(focusProbe.waitForExistence(timeout: 2))
        nameField.tap()

        assertFocusProbe(focusProbe, equals: focusedValue)

        let form = element("inventory.edit.form", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 2))
        form.swipeDown()

        assertFocusProbe(focusProbe, equals: blurredValue)
    }

    func testEditRecipeSheetDismissesKeyboardOnSwipeDown() {
        let app = UIHarness.launchApp()

        app.tabBars.buttons["Recipes"].tap()
        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        recipeCard.tap()
        app.buttons["recipe.detail.editButton"].tap()

        let nameField = element("recipe.edit.nameField", in: app)
        let focusProbe = element("recipe.edit.nameField.focusState", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertTrue(focusProbe.waitForExistence(timeout: 2))
        nameField.tap()

        assertFocusProbe(focusProbe, equals: focusedValue)

        let form = element("recipe.edit.form", in: app)
        XCTAssertTrue(form.waitForExistence(timeout: 2))
        form.swipeDown()

        assertFocusProbe(focusProbe, equals: blurredValue)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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

        let result = XCTWaiter.wait(for: [expectation], timeout: 4)
        XCTAssertEqual(result, .completed, "Expected focus probe to become \(expectedLabel).", file: file, line: line)
    }
}
