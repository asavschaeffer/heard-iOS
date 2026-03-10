import XCTest

final class RecipeFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOpenSeededRecipeShowsDetailView() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        recipeCard.tap()

        let detailView = element("recipe.detail.view", in: app)
        let descriptionText = element("recipe.detail.descriptionText", in: app)
        XCTAssertTrue(detailView.waitForExistence(timeout: 2))
        XCTAssertTrue(descriptionText.waitForExistence(timeout: 2))
        XCTAssertEqual(descriptionText.label, "Seeded recipe for UI editor flow checks.")
    }

    func testEditSeededRecipeUpdatesDetailContent() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        recipeCard.tap()

        let detailView = element("recipe.detail.view", in: app)
        XCTAssertTrue(detailView.waitForExistence(timeout: 2))

        app.buttons["recipe.detail.editButton"].tap()

        let editForm = element("recipe.edit.form", in: app)
        let nameField = element("recipe.edit.nameField", in: app)
        let saveButton = app.buttons["recipe.edit.saveButton"]
        XCTAssertTrue(editForm.waitForExistence(timeout: 2))
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))

        replaceText(in: nameField, with: "UI Test Pasta Updated")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(waitForNonExistence(of: editForm))
        app.buttons["recipe.detail.closeButton"].tap()

        let updatedRecipeCard = element("recipes.card.ui_test_pasta_updated", in: app)
        XCTAssertTrue(updatedRecipeCard.waitForExistence(timeout: 2))
    }

    func testDeleteSeededRecipeRemovesRecipeCard() {
        let app = UIHarness.launchApp(scenario: .editorFlows)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        recipeCard.tap()

        let detailView = element("recipe.detail.view", in: app)
        XCTAssertTrue(detailView.waitForExistence(timeout: 2))

        app.buttons["recipe.detail.editButton"].tap()

        let editForm = element("recipe.edit.form", in: app)
        XCTAssertTrue(editForm.waitForExistence(timeout: 2))
        var deleteButton = recipeDeleteButton(in: app)
        if !deleteButton.exists {
            editForm.swipeUp()
            deleteButton = recipeDeleteButton(in: app)
        }
        if !deleteButton.exists {
            editForm.swipeUp()
            deleteButton = recipeDeleteButton(in: app)
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.tap()

        let confirmDeleteButton = confirmDeleteButton(in: app)
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 2))
        confirmDeleteButton.tap()

        XCTAssertTrue(waitForNonExistence(of: editForm))
        XCTAssertTrue(waitForNonExistence(of: recipeCard))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func recipeDeleteButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["recipe.edit.deleteButton"].firstMatch
        return identifiedButton.exists ? identifiedButton : app.buttons["Delete Recipe"].firstMatch
    }

    private func confirmDeleteButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["recipe.edit.confirmDeleteButton"].firstMatch
        return identifiedButton.exists ? identifiedButton : app.buttons["Delete"].firstMatch
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
