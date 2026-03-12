import XCTest

final class SearchFilteringUITests: HeardUITestCase {
    func testInventorySearchShowsSeededIngredient() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Inventory"].tap()

        let list = element("inventory.list", in: app)
        XCTAssertTrue(list.waitForExistence(timeout: Self.existenceTimeout))

        let searchField = searchField(
            withPlaceholder: "Search ingredients",
            in: list,
            app: app
        )

        searchField.tap()
        searchField.typeText("butter")
        let ingredientRow = element("inventory.row.ui_test_butter", in: app)
        XCTAssertTrue(ingredientRow.waitForExistence(timeout: Self.existenceTimeout))
    }

    func testInventorySearchHidesNonMatchingIngredient() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Inventory"].tap()

        let list = element("inventory.list", in: app)
        XCTAssertTrue(list.waitForExistence(timeout: Self.existenceTimeout))

        let searchField = searchField(
            withPlaceholder: "Search ingredients",
            in: list,
            app: app
        )

        searchField.tap()
        searchField.typeText("cinnamon")

        XCTAssertTrue(waitForNonExistence(of: "inventory.row.ui_test_butter", in: app))
    }

    func testRecipeSearchShowsSeededRecipe() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Recipes"].tap()

        let scrollView = element("recipes.scrollView", in: app)
        XCTAssertTrue(scrollView.waitForExistence(timeout: Self.existenceTimeout))

        let searchField = searchField(
            withPlaceholder: "Search recipes",
            in: scrollView,
            app: app
        )

        searchField.tap()
        searchField.typeText("pasta")
        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        XCTAssertTrue(recipeCard.waitForExistence(timeout: Self.existenceTimeout))
    }

    func testRecipeSearchHidesNonMatchingRecipe() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Recipes"].tap()

        let scrollView = element("recipes.scrollView", in: app)
        XCTAssertTrue(scrollView.waitForExistence(timeout: Self.existenceTimeout))

        let searchField = searchField(
            withPlaceholder: "Search recipes",
            in: scrollView,
            app: app
        )

        searchField.tap()
        searchField.typeText("omelet")

        XCTAssertTrue(waitForNonExistence(of: "recipes.card.ui_test_pasta", in: app))
    }

    func testRecipeFilterToggleHidesAndRestoresNonMakeableRecipe() {
        let app = UIHarness.launchApp(scenario: .searchFiltering)

        app.tabBars.buttons["Recipes"].tap()

        let recipeCard = element("recipes.card.ui_test_pasta", in: app)
        let filterButton = app.buttons["recipes.filterButton"]
        XCTAssertTrue(recipeCard.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(filterButton.waitForExistence(timeout: Self.existenceTimeout))

        filterButton.tap()
        XCTAssertTrue(
            waitForNonExistence(
                of: "recipes.card.ui_test_pasta",
                in: app,
                timeout: Self.disappearanceTimeout * 2
            )
        )

        filterButton.tap()
        XCTAssertTrue(recipeCard.waitForExistence(timeout: Self.existenceTimeout))
    }
}
