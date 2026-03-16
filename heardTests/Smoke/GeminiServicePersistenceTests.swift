import Foundation
import SwiftData
import Testing
@testable import heard

@Suite(.tags(.hosted, .smoke))
@MainActor
struct GeminiServicePersistenceTests {
    @Test
    func addIngredientToolCallPersistsIngredientAcrossContexts() throws {
        let container = try makeTestContainer()
        let service = GeminiService(modelContext: container.mainContext)

        try deliverToolCall(
            service,
            name: "add_ingredient",
            arguments: [
                "name": "Mushrooms",
                "quantity": 2,
                "unit": "boxes",
                "category": "produce",
                "location": "fridge"
            ]
        )

        let verificationContext = ModelContext(container)
        let ingredient = try #require(Ingredient.find(named: "Mushrooms", in: verificationContext))

        #expect(ingredient.quantity == 2)
        #expect(ingredient.unit == Unit.boxes)
        #expect(ingredient.location == StorageLocation.fridge)
    }

    @Test
    func updateIngredientToolCallPersistsUpdatedFieldsAcrossContexts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = GeminiService(modelContext: context)
        context.insert(
            Ingredient(
                name: "Mushrooms",
                quantity: 1,
                unit: .boxes,
                category: .produce,
                location: .fridge
            )
        )
        try context.save()

        try deliverToolCall(
            service,
            name: "update_ingredient",
            arguments: [
                "name": "Mushrooms",
                "patch": [
                    "quantity": 3,
                    "location": "pantry",
                    "notes": "Use first"
                ]
            ]
        )

        let verificationContext = ModelContext(container)
        let ingredient = try #require(Ingredient.find(named: "Mushrooms", in: verificationContext))

        #expect(ingredient.quantity == 3)
        #expect(ingredient.location == StorageLocation.pantry)
        #expect(ingredient.notes == "Use first")
    }

    @Test
    func removeIngredientToolCallPersistsDeletionAcrossContexts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = GeminiService(modelContext: context)
        context.insert(
            Ingredient(
                name: "Mushrooms",
                quantity: 1,
                unit: .boxes,
                category: .produce,
                location: .fridge
            )
        )
        try context.save()

        try deliverToolCall(
            service,
            name: "remove_ingredient",
            arguments: ["name": "Mushrooms"]
        )

        let verificationContext = ModelContext(container)
        #expect(Ingredient.find(named: "Mushrooms", in: verificationContext) == nil)
    }

    @Test
    func createRecipeToolCallPersistsRecipeAcrossContexts() throws {
        let container = try makeTestContainer()
        let service = GeminiService(modelContext: container.mainContext)

        try deliverToolCall(
            service,
            name: "create_recipe",
            arguments: [
                "name": "Mushroom Risotto",
                "ingredients": [
                    [
                        "name": "Mushrooms",
                        "quantity": 2,
                        "unit": "boxes"
                    ],
                    [
                        "name": "Rice",
                        "quantity": 1,
                        "unit": "cups"
                    ]
                ],
                "steps": [
                    ["instruction": "Saute mushrooms"],
                    ["instruction": "Stir in rice"]
                ],
                "servings": 2,
                "tags": ["dinner", "vegetarian"]
            ]
        )

        let verificationContext = ModelContext(container)
        let recipe = try #require(Recipe.find(named: "Mushroom Risotto", in: verificationContext))

        #expect(recipe.ingredients.count == 2)
        #expect(recipe.steps.count == 2)
        #expect(recipe.servings == 2)
        #expect(recipe.tags == ["dinner", "vegetarian"])
    }

    @Test
    func updateRecipeToolCallPersistsUpdatedRecipeAcrossContexts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = GeminiService(modelContext: context)
        context.insert(
            Recipe(
                name: "Mushroom Risotto",
                ingredients: [RecipeIngredient(name: "Mushrooms", quantity: 2, unit: .boxes)],
                steps: [RecipeStep(instruction: "Saute mushrooms")],
                servings: 2,
                source: .userCreated
            )
        )
        try context.save()

        try deliverToolCall(
            service,
            name: "update_recipe",
            arguments: [
                "name": "Mushroom Risotto",
                "servings": 4,
                "notes": "Finish with butter",
                "steps": [
                    ["instruction": "Saute mushrooms"],
                    ["instruction": "Finish with butter"]
                ]
            ]
        )

        let verificationContext = ModelContext(container)
        let recipe = try #require(Recipe.find(named: "Mushroom Risotto", in: verificationContext))

        #expect(recipe.servings == 4)
        #expect(recipe.notes == "Finish with butter")
        #expect(recipe.steps.count == 2)
        #expect(recipe.orderedSteps.last?.instruction == "Finish with butter")
    }

    @Test
    func deleteRecipeToolCallPersistsDeletionAcrossContexts() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let service = GeminiService(modelContext: context)
        context.insert(
            Recipe(
                name: "Mushroom Risotto",
                ingredients: [RecipeIngredient(name: "Mushrooms", quantity: 2, unit: .boxes)],
                steps: [RecipeStep(instruction: "Saute mushrooms")],
                servings: 2,
                source: .userCreated
            )
        )
        try context.save()

        try deliverToolCall(
            service,
            name: "delete_recipe",
            arguments: ["name": "Mushroom Risotto"]
        )

        let verificationContext = ModelContext(container)
        #expect(Recipe.find(named: "Mushroom Risotto", in: verificationContext) == nil)
    }

    private func deliverToolCall(
        _ service: GeminiService,
        id: String = UUID().uuidString,
        name: String,
        arguments: [String: Any]
    ) throws {
        let payload: [String: Any] = [
            "toolCall": [
                "functionCalls": [
                    [
                        "id": id,
                        "name": name,
                        "args": arguments
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: payload)
        let message = try #require(String(data: data, encoding: .utf8))
        service.handleReceiveResult(.success(.string(message)))
    }
}

private func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Ingredient.self,
        Recipe.self,
        RecipeIngredient.self,
        RecipeStep.self,
        ChatThread.self,
        ChatMessage.self,
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
