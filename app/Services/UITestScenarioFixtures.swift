import Foundation
import SwiftData

enum UITestScenarioFixtures {
    static func seed(_ scenario: UITestScenario, into context: ModelContext) {
        let builder = UITestSeedBuilder(context: context)
        builder.reset()

        switch scenario {
        case .editorFlows:
            seedEditorFlows(using: builder)
        case .keyboardDismiss:
            seedKeyboardDismiss(using: builder)
        case .searchFiltering:
            seedSearchFiltering(using: builder)
        case .emptyState:
            break
        case .attachmentsBasic:
            seedAttachmentsBasic(using: builder)
        }

        builder.save()
    }

    private static func seedEditorFlows(using builder: UITestSeedBuilder) {
        seedCoreEditorData(
            using: builder,
            recipeDescription: "Seeded recipe for UI editor flow checks."
        )
    }

    private static func seedKeyboardDismiss(using builder: UITestSeedBuilder) {
        seedCoreEditorData(
            using: builder,
            recipeDescription: "Seeded recipe for UI keyboard dismissal checks."
        )
    }

    private static func seedSearchFiltering(using builder: UITestSeedBuilder) {
        seedCoreEditorData(
            using: builder,
            recipeDescription: "Seeded recipe for UI search and filtering checks."
        )
    }

    private static func seedAttachmentsBasic(using builder: UITestSeedBuilder) {
        seedCoreEditorData(
            using: builder,
            recipeDescription: "Seeded recipe for future UI attachment coverage."
        )
    }

    private static func seedCoreEditorData(
        using builder: UITestSeedBuilder,
        recipeDescription: String
    ) {
        _ = builder.ingredient(
            name: "UI Test Butter",
            quantity: 1,
            unit: .piece,
            category: .dairy,
            location: .fridge
        )

        _ = builder.recipe(
            name: "UI Test Pasta",
            description: recipeDescription,
            ingredients: [
                RecipeIngredient(name: "Pasta", quantity: 1, unit: .boxes),
                RecipeIngredient(name: "Butter", quantity: 2, unit: .tablespoons)
            ],
            steps: [
                RecipeStep(instruction: "Boil pasta.", orderIndex: 0),
                RecipeStep(instruction: "Toss with butter.", orderIndex: 1)
            ]
        )
    }
}
