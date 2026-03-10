import Foundation
import SwiftData

enum UITestScenario: String {
    case keyboardDismiss = "keyboard_dismiss"
}

enum UITestSupport {
    static var isEnabled: Bool { TestSupport.isRunningUITests }

    static var scenario: UITestScenario? {
        guard isEnabled else { return nil }
        guard let rawValue = ProcessInfo.processInfo.environment["UITEST_SCENARIO"] else {
            return nil
        }
        return UITestScenario(rawValue: rawValue)
    }

    static func configure(container: ModelContainer) {
        guard isEnabled else { return }

        switch scenario {
        case .keyboardDismiss, .none:
            seedKeyboardDismissScenario(into: container.mainContext)
        }
    }

    static func identifierSlug(_ value: String) -> String {
        let slug = value.lowercased().unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
        let collapsed = slug.replacingOccurrences(
            of: "_+",
            with: "_",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func seedKeyboardDismissScenario(into context: ModelContext) {
        let butter = Ingredient(
            name: "UI Test Butter",
            quantity: 1,
            unit: .piece,
            category: .dairy,
            location: .fridge
        )

        let recipe = Recipe(
            name: "UI Test Pasta",
            description: "Seeded recipe for UI keyboard dismissal checks.",
            ingredients: [
                RecipeIngredient(name: "Pasta", quantity: 1, unit: .boxes),
                RecipeIngredient(name: "Butter", quantity: 2, unit: .tablespoons)
            ],
            steps: [
                RecipeStep(instruction: "Boil pasta.", orderIndex: 0),
                RecipeStep(instruction: "Toss with butter.", orderIndex: 1)
            ],
            prepTime: 5,
            cookTime: 10,
            servings: 2,
            tags: ["ui-test"],
            difficulty: .easy,
            source: .userCreated
        )

        context.insert(butter)
        context.insert(recipe)

        try? context.save()
    }
}
