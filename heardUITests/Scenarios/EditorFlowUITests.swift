import XCTest

final class EditorFlowUITests: HeardUITestCase {
    func testAddIngredientSheetOpensNameField() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()
        app.buttons["inventory.addButton"].tap()

        let nameField = element("inventory.add.nameField", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
    }

    func testEditIngredientSheetOpensNameField() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()

        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: 2))
        ingredientRow.tap()

        let nameField = element("inventory.edit.nameField", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
    }

    func testEditRecipeSheetOpensNameField() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        recipeCard.tap()
        app.buttons["recipe.detail.editButton"].tap()

        let nameField = element("recipe.edit.nameField", in: app)
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
    }
}
