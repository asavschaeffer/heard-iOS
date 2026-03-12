import XCTest

final class RecipeFlowUITests: HeardUITestCase {
    func testOpenSeededRecipeShowsDetailView() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: Self.existenceTimeout))
        recipeCard.tap()

        let detailView = element("recipe.detail.view", in: app)
        let descriptionText = element("recipe.detail.descriptionText", in: app)
        XCTAssertTrue(detailView.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(descriptionText.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertEqual(descriptionText.label, "Seeded recipe for UI editor flow checks.")
    }

    func testEditSeededRecipeUpdatesDetailContent() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: Self.existenceTimeout))
        recipeCard.tap()

        let detailView = element("recipe.detail.view", in: app)
        XCTAssertTrue(detailView.waitForExistence(timeout: Self.existenceTimeout))

        app.buttons["recipe.detail.editButton"].tap()

        let editForm = element("recipe.edit.form", in: app)
        let nameField = element("recipe.edit.nameField", in: app)
        let saveButton = app.buttons["recipe.edit.saveButton"]
        XCTAssertTrue(editForm.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(nameField.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(saveButton.waitForExistence(timeout: Self.existenceTimeout))

        replaceText(in: nameField, with: "UI Test Pasta Updated")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(waitForNonExistence(of: "recipe.edit.form", in: app))
        app.buttons["recipe.detail.closeButton"].tap()

        let updatedRecipeCard = element("recipes.card.ui_test_pasta_updated", in: app)
        XCTAssertTrue(updatedRecipeCard.waitForExistence(timeout: 2))
    }

    func testDeleteSeededRecipeRemovesRecipeCard() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: Self.existenceTimeout))
        recipeCard.tap()

        let detailView = element("recipe.detail.view", in: app)
        XCTAssertTrue(detailView.waitForExistence(timeout: Self.existenceTimeout))

        app.buttons["recipe.detail.editButton"].tap()

        let editForm = element("recipe.edit.form", in: app)
        XCTAssertTrue(editForm.waitForExistence(timeout: Self.existenceTimeout))
        var deleteButton = recipeDeleteButton(in: app)
        if !deleteButton.exists {
            editForm.swipeUp()
            deleteButton = recipeDeleteButton(in: app)
        }
        if !deleteButton.exists {
            editForm.swipeUp()
            deleteButton = recipeDeleteButton(in: app)
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: Self.existenceTimeout))
        deleteButton.tap()

        let confirmDeleteButton = confirmDeleteButton(in: app)
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: Self.existenceTimeout))
        confirmDeleteButton.tap()

        XCTAssertTrue(waitForNonExistence(of: "recipe.edit.form", in: app))
        XCTAssertTrue(waitForNonExistence(of: "recipes.card.ui_test_pasta", in: app))
    }

    private func recipeDeleteButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["recipe.edit.deleteButton"].firstMatch
        return identifiedButton.exists ? identifiedButton : app.buttons["Delete Recipe"].firstMatch
    }

    private func confirmDeleteButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["recipe.edit.confirmDeleteButton"].firstMatch
        return identifiedButton.exists ? identifiedButton : app.buttons["Delete"].firstMatch
    }
}
