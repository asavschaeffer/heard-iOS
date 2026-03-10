import XCTest

final class InventoryFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateIngredientAddsRowToInventoryList() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventory.addButton"].tap()

        let form = element("inventory.add.form", in: app)
        let nameField = element("inventory.add.nameField", in: app)
        let saveButton = app.buttons["inventory.add.saveButton"]
        XCTAssertTrue(form.waitForExistence(timeout: 2))
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))

        replaceText(in: nameField, with: "UI Test Cinnamon")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(waitForNonExistence(of: form))

        let createdRow = element("inventory.row.ui_test_cinnamon", in: app)
        XCTAssertTrue(createdRow.waitForExistence(timeout: 2))
    }

    func testEditSeededIngredientUpdatesInventoryRow() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()

        let originalRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(originalRow.waitForExistence(timeout: 2))
        originalRow.tap()

        let form = element("inventory.edit.form", in: app)
        let nameField = element("inventory.edit.nameField", in: app)
        let saveButton = app.buttons["inventory.edit.saveButton"]
        XCTAssertTrue(form.waitForExistence(timeout: 2))
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))

        replaceText(in: nameField, with: "UI Test Butter Updated")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(waitForNonExistence(of: form))

        let updatedRow = element("inventory.row.ui_test_butter_updated", in: app)
        XCTAssertTrue(updatedRow.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForNonExistence(of: originalRow))
    }

    func testDeleteSeededIngredientRemovesInventoryRow() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()

        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: 2))
        ingredientRow.tap()

        let form = element("inventory.edit.form", in: app)
        let deleteButton = app.buttons["inventory.edit.deleteButton"]
        XCTAssertTrue(form.waitForExistence(timeout: 2))
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))

        deleteButton.tap()

        XCTAssertTrue(waitForNonExistence(of: form))
        XCTAssertTrue(waitForNonExistence(of: ingredientRow))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func replaceText(in element: XCUIElement, with text: String) {
        element.tap()

        let currentValue = (element.value as? String) ?? ""
        if !currentValue.isEmpty, currentValue != element.placeholderValue {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }

        element.typeText(text)
    }

    private func waitForNonExistence(
        of element: XCUIElement,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        let didDisappear = result == .completed
        XCTAssertTrue(didDisappear, "Expected element to disappear.", file: file, line: line)
        return didDisappear
    }
}
