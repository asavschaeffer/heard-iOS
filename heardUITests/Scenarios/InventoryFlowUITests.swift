import XCTest

final class InventoryFlowUITests: HeardUITestCase {
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
}
