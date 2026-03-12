import XCTest

final class SearchFilteringUITests: HeardUITestCase {
    func testInventorySearchShowsSeededIngredient() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Inventory"].tap()

        let list = element("inventory.list", in: app)
        XCTAssertTrue(list.waitForExistence(timeout: 2))

        let searchField = searchField(
            withPlaceholder: "Search ingredients",
            in: list,
            app: app
        )

        searchField.tap()
        searchField.typeText("butter")
        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: 2))
    }

    func testInventorySearchHidesNonMatchingIngredient() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Inventory"].tap()

        let list = element("inventory.list", in: app)
        XCTAssertTrue(list.waitForExistence(timeout: 2))

        let searchField = searchField(
            withPlaceholder: "Search ingredients",
            in: list,
            app: app
        )

        searchField.tap()
        searchField.typeText("cinnamon")

        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(waitForNonExistence(of: ingredientRow))
    }

    func testRecipeSearchShowsSeededRecipe() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Recipes"].tap()

        let scrollView = element("recipes.scrollView", in: app)
        XCTAssertTrue(scrollView.waitForExistence(timeout: 2))

        let searchField = searchField(
            withPlaceholder: "Search recipes",
            in: scrollView,
            app: app
        )

        searchField.tap()
        searchField.typeText("pasta")
        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
    }

    func testRecipeSearchHidesNonMatchingRecipe() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Recipes"].tap()

        let scrollView = element("recipes.scrollView", in: app)
        XCTAssertTrue(scrollView.waitForExistence(timeout: 2))

        let searchField = searchField(
            withPlaceholder: "Search recipes",
            in: scrollView,
            app: app
        )

        searchField.tap()
        searchField.typeText("omelet")

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(waitForNonExistence(of: recipeCard))
    }

    func testRecipeFilterToggleHidesAndRestoresNonMakeableRecipe() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        let filterButton = app.buttons["recipes.filterButton"]
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
        XCTAssertTrue(filterButton.waitForExistence(timeout: 2))

        filterButton.tap()
        XCTAssertTrue(waitForNonExistence(of: recipeCard))

        filterButton.tap()
        XCTAssertTrue(recipeCard.waitForExistence(timeout: 2))
    }
}
