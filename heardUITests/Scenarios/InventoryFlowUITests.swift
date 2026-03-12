import XCTest

final class InventoryFlowUITests: HeardUITestCase {
    func testCreateIngredientAddsRowToInventoryList() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventory.addButton"].tap()

        let form = element("inventory.add.form", in: app)
        let nameField = element("inventory.add.nameField", in: app)
        let saveButton = app.buttons["inventory.add.saveButton"]
        XCTAssertTrue(form.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(saveButton.waitForExistence(timeout: Self.existenceTimeout))

        replaceText(in: nameField, with: "UI Test Cinnamon")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(waitForNonExistence(of: "inventory.add.form", in: app))

        let createdRow = element("inventory.row.ui_test_cinnamon", in: app)
        XCTAssertTrue(createdRow.waitForExistence(timeout: 2))
    }

    func testEditSeededIngredientUpdatesInventoryRow() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()

        let originalRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(originalRow.waitForExistence(timeout: Self.existenceTimeout))
        originalRow.tap()

        let form = element("inventory.edit.form", in: app)
        let nameField = element("inventory.edit.nameField", in: app)
        let saveButton = app.buttons["inventory.edit.saveButton"]
        XCTAssertTrue(form.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(saveButton.waitForExistence(timeout: Self.existenceTimeout))

        replaceText(in: nameField, with: "UI Test Butter Updated")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(
            waitForTransition(
                from: "inventory.row.ui_test_butter",
                to: "inventory.row.ui_test_butter_updated",
                in: app
            )
        )
    }

    func testDeleteSeededIngredientRemovesInventoryRow() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()

        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: Self.existenceTimeout))
        ingredientRow.tap()

        let form = element("inventory.edit.form", in: app)
        let deleteButton = app.buttons["inventory.edit.deleteButton"]
        XCTAssertTrue(form.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(deleteButton.waitForExistence(timeout: Self.existenceTimeout))

        deleteButton.tap()

        XCTAssertTrue(waitForNonExistence(of: "inventory.edit.form", in: app))
        XCTAssertTrue(waitForNonExistence(of: "inventory.row.ui_test_butter", in: app))
    }
}
