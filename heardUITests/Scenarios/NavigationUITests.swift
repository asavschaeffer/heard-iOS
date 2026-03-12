import XCTest

final class NavigationUITests: HeardUITestCase {
    func testInventoryDetailDismissReturnsToInventoryList() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Inventory"].tap()

        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: 2))
        ingredientRow.tap()

        let editForm = element("inventory.edit.form", in: app)
        let cancelButton = app.buttons["inventory.edit.cancelButton"]
        XCTAssertTrue(editForm.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(cancelButton.waitForExistence(timeout: Self.existenceTimeout))

        cancelButton.tap()

        XCTAssertTrue(
            waitForTransition(
                from: "inventory.edit.form",
                to: "inventory.row.ui_test_butter",
                in: app
            )
        )
        XCTAssertTrue(app.tabBars.buttons["Inventory"].isSelected)
    }

    func testRecipeDetailAndEditDismissReturnToRecipesList() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        recipeCard.tap()

        let detailView = element("recipe.detail.view", in: app)
        let closeButton = app.buttons["recipe.detail.closeButton"]
        XCTAssertTrue(detailView.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(closeButton.waitForExistence(timeout: Self.existenceTimeout))

        app.buttons["recipe.detail.editButton"].tap()

        let editForm = element("recipe.edit.form", in: app)
        let cancelButton = app.buttons["recipe.edit.cancelButton"]
        XCTAssertTrue(editForm.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(cancelButton.waitForExistence(timeout: Self.existenceTimeout))

        cancelButton.tap()

        XCTAssertTrue(
            waitForTransition(
                from: "recipe.edit.form",
                to: "recipe.detail.view",
                in: app
            )
        )

        closeButton.tap()

        XCTAssertTrue(
            waitForTransition(
                from: "recipe.detail.view",
                to: "recipes.card.ui_test_pasta",
                in: app
            )
        )
        XCTAssertTrue(app.tabBars.buttons["Recipes"].isSelected)
    }
}
