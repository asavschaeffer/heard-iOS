import Foundation
import Testing
@testable import heard

@Suite(.tags(.hosted, .configuration))
struct GeminiToolSchemaTests {
    @Test
    func recipeToolSchemasSerializeNativeArraysRecursively() throws {
        let declarations = GeminiTools.toAPIFormat()

        let createRecipe = try #require(
            declarations.first { $0["name"] as? String == "create_recipe" }
        )
        let createParameters = try #require(createRecipe["parameters"] as? [String: Any])
        let createProperties = try #require(createParameters["properties"] as? [String: Any])

        let ingredients = try #require(createProperties["ingredients"] as? [String: Any])
        #expect(ingredients["type"] as? String == "array")

        let ingredientItems = try #require(ingredients["items"] as? [String: Any])
        #expect(ingredientItems["type"] as? String == "object")
        #expect(ingredientItems["required"] as? [String] == ["name"])

        let ingredientProperties = try #require(ingredientItems["properties"] as? [String: Any])
        #expect((ingredientProperties["name"] as? [String: Any])?["type"] as? String == "string")
        #expect((ingredientProperties["unit"] as? [String: Any])?["type"] as? String == "string")

        let steps = try #require(createProperties["steps"] as? [String: Any])
        #expect(steps["type"] as? String == "array")

        let stepItems = try #require(steps["items"] as? [String: Any])
        #expect(stepItems["type"] as? String == "object")
        #expect(stepItems["required"] as? [String] == ["instruction"])

        let tags = try #require(createProperties["tags"] as? [String: Any])
        #expect(tags["type"] as? String == "array")
        #expect((tags["items"] as? [String: Any])?["type"] as? String == "string")

        let updateRecipe = try #require(
            declarations.first { $0["name"] as? String == "update_recipe" }
        )
        let updateParameters = try #require(updateRecipe["parameters"] as? [String: Any])
        let updateProperties = try #require(updateParameters["properties"] as? [String: Any])

        #expect((updateProperties["ingredients"] as? [String: Any])?["type"] as? String == "array")
        #expect((updateProperties["steps"] as? [String: Any])?["type"] as? String == "array")
        #expect((updateProperties["tags"] as? [String: Any])?["type"] as? String == "array")
    }

    @Test
    func toolDeclarationsRemainJSONCompatible() {
        #expect(
            JSONSerialization.isValidJSONObject(GeminiTools.toAPIFormat()),
            "Function declarations should stay serializable for Gemini setup payloads."
        )
    }
}

@Suite(.tags(.hosted, .configuration))
struct GeminiFunctionCallParsingTests {
    @Test
    func parsedRecipeArraysHandleNativeArrays() throws {
        let call = FunctionCall(
            id: "native",
            name: "create_recipe",
            arguments: [
                "ingredients": [
                    [
                        "name": "pasta",
                        "quantity": 8,
                        "unit": "oz"
                    ],
                    [
                        "name": "salt"
                    ]
                ],
                "steps": [
                    [
                        "instruction": "Boil salted water",
                        "durationMinutes": 10
                    ],
                    "Cook pasta until al dente"
                ],
                "tags": ["weeknight", "vegetarian"]
            ]
        )

        let ingredients = try #require(call.parsedArrayOfDicts("ingredients"))
        #expect(ingredients.count == 2)
        #expect(ingredients.compactMap(RecipeIngredient.fromArguments).count == 2)

        let steps = try #require(call.parsedAnyArray("steps"))
        #expect(steps.count == 2)
        let mappedSteps = steps.enumerated().compactMap { index, step in
            if let instruction = step as? String {
                return RecipeStep(instruction: instruction, orderIndex: index)
            }

            guard let rawStep = step as? [String: Any] else {
                return nil
            }

            return RecipeStep.fromArguments(rawStep, index: index)
        }
        #expect(mappedSteps.count == 2)
        #expect(mappedSteps.first?.durationMinutes == 10)

        #expect(call.parsedStringArray("tags") == ["weeknight", "vegetarian"])
    }

    @Test
    func parsedRecipeArraysFallbackToJSONStrings() throws {
        let call = FunctionCall(
            id: "json",
            name: "create_recipe",
            arguments: [
                "ingredients": try jsonString([
                    [
                        "name": "stock",
                        "quantity": 4,
                        "unit": "cups"
                    ]
                ]),
                "steps": try jsonString([
                    [
                        "instruction": "Simmer",
                        "durationMinutes": 20
                    ]
                ]),
                "tags": try jsonString(["soup", "fallback"])
            ]
        )

        let ingredients = try #require(call.parsedArrayOfDicts("ingredients"))
        #expect(ingredients.count == 1)
        #expect(ingredients.compactMap(RecipeIngredient.fromArguments).count == 1)

        let steps = try #require(call.parsedAnyArray("steps"))
        #expect(steps.count == 1)
        let firstStep = try #require(steps.first as? [String: Any])
        #expect(RecipeStep.fromArguments(firstStep, index: 0)?.durationMinutes == 20)

        #expect(call.parsedStringArray("tags") == ["soup", "fallback"])
    }

    @Test
    func parsedRecipeArraysRejectInvalidJSONStrings() {
        let call = FunctionCall(
            id: "invalid",
            name: "create_recipe",
            arguments: [
                "ingredients": "{bad json",
                "steps": "{\"instruction\":\"not an array\"}",
                "tags": "[1,2]"
            ]
        )

        #expect(call.parsedArrayOfDicts("ingredients") == nil)
        #expect(call.parsedAnyArray("steps") == nil)
        #expect(call.parsedStringArray("tags") == nil)
    }

    private func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        return try #require(
            String(data: data, encoding: .utf8),
            "JSON fixture should encode to UTF-8."
        )
    }
}
