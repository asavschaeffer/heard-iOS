import XCTest

final class NavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInventoryDetailDismissReturnsToInventoryList() {
        let app = UIHarness.launchApp()

        app.tabBars.buttons["Inventory"].tap()

        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: 2))
        ingredientRow.tap()

        let editForm = element("inventory.edit.form", in: app)
        let cancelButton = app.buttons["inventory.edit.cancelButton"]
        XCTAssertTrue(editForm.waitForExistence(timeout: 2))
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))

        cancelButton.tap()

        XCTAssertTrue(waitForNonExistence(of: editForm))
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: 2))
        XCTAssertTrue(app.tabBars.buttons["Inventory"].isSelected)
    }

    func testRecipeDetailAndEditDismissReturnToRecipesList() {
        let app = UIHarness.launchApp()

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        recipeCard.tap()

        let detailView = element("recipe.detail.view", in: app)
        let closeButton = app.buttons["recipe.detail.closeButton"]
        XCTAssertTrue(detailView.waitForExistence(timeout: 2))
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2))

        app.buttons["recipe.detail.editButton"].tap()

        let editForm = element("recipe.edit.form", in: app)
        let cancelButton = app.buttons["recipe.edit.cancelButton"]
        XCTAssertTrue(editForm.waitForExistence(timeout: 2))
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))

        cancelButton.tap()

        XCTAssertTrue(waitForNonExistence(of: editForm))
        XCTAssertTrue(detailView.waitForExistence(timeout: 2))

        closeButton.tap()

        XCTAssertTrue(waitForNonExistence(of: detailView))
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        XCTAssertTrue(app.tabBars.buttons["Recipes"].isSelected)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
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
