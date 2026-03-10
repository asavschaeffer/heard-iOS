import Foundation
import SwiftData

struct UITestSeedBuilder {
    let context: ModelContext

    func reset() {
        deleteAll(Recipe.self)
        deleteAll(Ingredient.self)
        save()
    }

    @discardableResult
    func ingredient(
        name: String,
        quantity: Double,
        unit: Unit,
        category: IngredientCategory,
        location: StorageLocation
    ) -> Ingredient {
        let ingredient = Ingredient(
            name: name,
            quantity: quantity,
            unit: unit,
            category: category,
            location: location
        )
        context.insert(ingredient)
        return ingredient
    }

    @discardableResult
    func recipe(
        name: String,
        description: String,
        ingredients: [RecipeIngredient],
        steps: [RecipeStep],
        prepTime: Int? = 5,
        cookTime: Int? = 10,
        servings: Int? = 2,
        tags: [String] = ["ui-test"],
        difficulty: RecipeDifficulty = .easy,
        source: RecipeSource = .userCreated
    ) -> Recipe {
        let recipe = Recipe(
            name: name,
            description: description,
            ingredients: ingredients,
            steps: steps,
            prepTime: prepTime,
            cookTime: cookTime,
            servings: servings,
            tags: tags,
            difficulty: difficulty,
            source: source
        )
        context.insert(recipe)
        return recipe
    }

    func save() {
        try? context.save()
    }

    private func deleteAll<Model: PersistentModel>(_ modelType: Model.Type) {
        let descriptor = FetchDescriptor<Model>()
        guard let existingModels = try? context.fetch(descriptor) else { return }
        for model in existingModels {
            context.delete(model)
        }
    }
}
