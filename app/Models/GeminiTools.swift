import Foundation

// MARK: - Gemini Function Schema Types

/// Represents a function that Gemini can call during a conversation.
struct FunctionDeclaration {
    let name: String
    let description: String
    let parameters: ParameterSchema
}

struct ParameterSchema {
    let type: String
    let properties: [String: PropertySchema]
    let required: [String]

    init(properties: [String: PropertySchema], required: [String] = []) {
        self.type = "object"
        self.properties = properties
        self.required = required
    }
}

struct PropertySchema {
    let type: String
    let description: String
    let enumValues: [String]?
    let properties: [String: PropertySchema]?
    let required: [String]?
    private let _items: Box<PropertySchema>?

    var items: PropertySchema? { _items?.value }

    /// Reference wrapper to allow recursive value types.
    private final class Box<T> {
        let value: T
        init(_ value: T) { self.value = value }
    }

    static func string(_ description: String) -> PropertySchema {
        PropertySchema(type: "string", description: description, enumValues: nil, properties: nil, required: nil, _items: nil)
    }

    static func number(_ description: String) -> PropertySchema {
        PropertySchema(type: "number", description: description, enumValues: nil, properties: nil, required: nil, _items: nil)
    }

    static func boolean(_ description: String) -> PropertySchema {
        PropertySchema(type: "boolean", description: description, enumValues: nil, properties: nil, required: nil, _items: nil)
    }

    static func stringEnum(_ description: String, values: [String]) -> PropertySchema {
        PropertySchema(type: "string", description: description, enumValues: values, properties: nil, required: nil, _items: nil)
    }

    static func object(_ description: String, properties: [String: PropertySchema], required: [String] = []) -> PropertySchema {
        PropertySchema(
            type: "object",
            description: description,
            enumValues: nil,
            properties: properties,
            required: required.isEmpty ? nil : required,
            _items: nil
        )
    }

    static func array(_ description: String, items: PropertySchema) -> PropertySchema {
        PropertySchema(
            type: "array",
            description: description,
            enumValues: nil,
            properties: nil,
            required: nil,
            _items: Box(items)
        )
    }
}

// MARK: - Inventory Tool Declarations

enum InventoryTools {

    static let add = FunctionDeclaration(
        name: "add_ingredient",
        description: "Add an ingredient to the pantry. Merges quantity if one with the same name already exists (matched case-insensitively, singular/plural).",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Ingredient name"),
                "quantity": .number("Amount (> 0)"),
                "unit": .stringEnum("Unit", values: Unit.allValidStrings),
                "category": .stringEnum("Category", values: IngredientCategory.allValidStrings),
                "location": .stringEnum("Location", values: StorageLocation.allValidStrings),
                "expiryDate": .string("YYYY-MM-DD (Optional)"),
                "notes": .string("Notes (Optional)")
            ],
            required: ["name", "quantity", "unit"]
        )
    )

    static let remove = FunctionDeclaration(
        name: "remove_ingredient",
        description: "Remove an ingredient from the pantry, or reduce its quantity. Omit quantity to remove entirely.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Name to remove"),
                "quantity": .number("Amount to remove. Omit to remove all.")
            ],
            required: ["name"]
        )
    )

    static let update = FunctionDeclaration(
        name: "update_ingredient",
        description: "Update properties of an existing pantry ingredient. Only include fields to change.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Current name"),
                "patch": .object(
                    "Fields to update",
                    properties: [
                        "name": .string("New name"),
                        "quantity": .number("New quantity"),
                        "unit": .stringEnum("New unit", values: Unit.allValidStrings),
                        "category": .stringEnum("New category", values: IngredientCategory.allValidStrings),
                        "location": .stringEnum("New location", values: StorageLocation.allValidStrings),
                        "expiryDate": .string("New expiry (YYYY-MM-DD)"),
                        "notes": .string("New notes")
                    ]
                )
            ],
            required: ["name", "patch"]
        )
    )

    static let list = FunctionDeclaration(
        name: "list_ingredients",
        description: "List all pantry ingredients, optionally filtered by category or location.",
        parameters: ParameterSchema(
            properties: [
                "category": .stringEnum("Filter category", values: IngredientCategory.allValidStrings),
                "location": .stringEnum("Filter location", values: StorageLocation.allValidStrings)
            ],
            required: []
        )
    )

    static let search = FunctionDeclaration(
        name: "search_ingredients",
        description: "Search pantry ingredients by name (partial match).",
        parameters: ParameterSchema(
            properties: [
                "query": .string("Search term")
            ],
            required: ["query"]
        )
    )

    static let check = FunctionDeclaration(
        name: "get_ingredient",
        description: "Get full details of a single pantry ingredient by name.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Name to check")
            ],
            required: ["name"]
        )
    )

    static var all: [FunctionDeclaration] {
        [add, remove, update, list, search, check]
    }
}

// MARK: - Recipe Tool Declarations

enum RecipeTools {

    static let create = FunctionDeclaration(
        name: "create_recipe",
        description: "Create a new recipe. Ingredient names are matched to pantry inventory by normalized name.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Recipe name"),
                "description": .string("Brief description of the dish"),
                "notes": .string("Freeform notes: variations, tips, pairings, substitutions"),
                "cookingTemperature": .string("Cooking temperature, e.g. 350F, 180C, medium-high"),
                "ingredients": .array("List of ingredients", items: .object(
                    "An ingredient",
                    properties: [
                        "name": .string("Ingredient name"),
                        "quantity": .number("Amount needed"),
                        "unit": .stringEnum("Unit", values: Unit.allValidStrings),
                        "preparation": .string("How to prepare, e.g. diced, minced")
                    ],
                    required: ["name"]
                )),
                "steps": .array("Cooking steps in order", items: .object(
                    "A step",
                    properties: [
                        "instruction": .string("What to do"),
                        "durationMinutes": .number("Timer for this step")
                    ],
                    required: ["instruction"]
                )),
                "prepTime": .number("Prep time in minutes"),
                "cookTime": .number("Cook time in minutes"),
                "servings": .number("Number of servings"),
                "difficulty": .stringEnum("Difficulty", values: RecipeDifficulty.allValidStrings),
                "tags": .array("Lowercase tags, e.g. italian, vegetarian, quick", items: .string("A tag"))
            ],
            required: ["name", "ingredients", "steps"]
        )
    )
    
    // MARK: - Update (Missing Piece)
    
    static let update = FunctionDeclaration(
        name: "update_recipe",
        description: "Update an existing recipe. Only provide fields to change. Ingredients and steps replace the full list when provided.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Name of recipe to update"),
                "newName": .string("New name"),
                "description": .string("New description"),
                "notes": .string("New notes. Use empty string to clear."),
                "cookingTemperature": .string("New cooking temperature. Use empty string to clear."),
                "ingredients": .array("New ingredients (replaces full list)", items: .object(
                    "An ingredient",
                    properties: [
                        "name": .string("Ingredient name"),
                        "quantity": .number("Amount needed"),
                        "unit": .stringEnum("Unit", values: Unit.allValidStrings),
                        "preparation": .string("How to prepare, e.g. diced, minced")
                    ],
                    required: ["name"]
                )),
                "steps": .array("New steps (replaces full list)", items: .object(
                    "A step",
                    properties: [
                        "instruction": .string("What to do"),
                        "durationMinutes": .number("Timer for this step")
                    ],
                    required: ["instruction"]
                )),
                "prepTime": .number("New prep time in minutes"),
                "cookTime": .number("New cook time in minutes"),
                "servings": .number("New servings"),
                "difficulty": .stringEnum("New difficulty", values: RecipeDifficulty.allValidStrings),
                "tags": .array("New lowercase tags", items: .string("A tag"))
            ],
            required: ["name"]
        )
    )

    static let list = FunctionDeclaration(
        name: "list_recipes",
        description: "List all saved recipes (name, tags, total time). Optionally filter by tag.",
        parameters: ParameterSchema(
            properties: [
                "tag": .string("Filter by tag")
            ],
            required: []
        )
    )

    static let search = FunctionDeclaration(
        name: "search_recipes",
        description: "Search recipes by name or tag (partial match).",
        parameters: ParameterSchema(
            properties: [
                "query": .string("Search term")
            ],
            required: ["query"]
        )
    )

    static let suggest = FunctionDeclaration(
        name: "suggest_recipes",
        description: "Suggest recipes that can be made with current pantry inventory, ranked by ingredient match.",
        parameters: ParameterSchema(
            properties: [
                "maxMissingIngredients": .number("Max missing (default 3)"),
                "onlyFullyMakeable": .boolean("Only complete matches")
            ],
            required: []
        )
    )
    static let get = FunctionDeclaration(
        name: "get_recipe",
        description: "Get full recipe details including ingredients, steps, and notes.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Exact recipe name")
            ],
            required: ["name"]
        )
    )

    static let checkAvailability = FunctionDeclaration(
        name: "check_recipe_availability",
        description: "Check if a recipe can be made with current inventory, and list missing items.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Exact recipe name")
            ],
            required: ["name"]
        )
    )

    static let delete = FunctionDeclaration(
        name: "delete_recipe",
        description: "Permanently delete a recipe by name.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Name to delete")
            ],
            required: ["name"]
        )
    )

    static var all: [FunctionDeclaration] {
        [create, update, delete, get, list, search, suggest, checkAvailability]
    }
}

// MARK: - All Tools

struct GeminiTools {

    static var allDeclarations: [FunctionDeclaration] {
        InventoryTools.all + RecipeTools.all
    }

    static func toAPIFormat() -> [[String: Any]] {
        allDeclarations.map { decl in
            [
                "name": decl.name,
                "description": decl.description,
                "parameters": [
                    "type": decl.parameters.type,
                    "properties": decl.parameters.properties.reduce(into: [String: Any]()) { result, pair in
                        result[pair.key] = serializeProperty(pair.value)
                    },
                    "required": decl.parameters.required
                ] as [String: Any]
            ]
        }
    }

    private static func serializeProperty(_ schema: PropertySchema) -> [String: Any] {
        var dict: [String: Any] = [
            "type": schema.type,
            "description": schema.description
        ]
        if let enumVals = schema.enumValues {
            dict["enum"] = enumVals
        }
        if let nestedProperties = schema.properties {
            dict["properties"] = nestedProperties.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = serializeProperty(pair.value)
            }
        }
        if let nestedRequired = schema.required {
            dict["required"] = nestedRequired
        }
        if let items = schema.items {
            dict["items"] = serializeProperty(items)
        }
        return dict
    }

    static func tool(named name: String) -> FunctionDeclaration? {
        allDeclarations.first { $0.name == name }
    }

    static var allNames: Set<String> {
        Set(allDeclarations.map { $0.name })
    }
    
    static func validate(call: FunctionCall) -> String? {
        guard let tool = tool(named: call.name) else {
            return "Unknown function: \(call.name)"
        }

        for required in tool.parameters.required {
            if call.arguments[required] == nil {
                return "Missing required parameter: \(required)"
            }
        }

        return nil
    }
}

// MARK: - Function Call Types

struct FunctionCall {
    let id: String
    let name: String
    let arguments: [String: Any]

    func string(_ key: String) -> String? {
        arguments[key] as? String
    }

    func double(_ key: String) -> Double? {
        if let d = arguments[key] as? Double { return d }
        if let i = arguments[key] as? Int { return Double(i) }
        if let s = arguments[key] as? String { return Double(s) }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let i = arguments[key] as? Int { return i }
        if let d = arguments[key] as? Double { return Int(d) }
        if let s = arguments[key] as? String { return Int(s) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        arguments[key] as? Bool
    }

    func arrayOfDicts(_ key: String) -> [[String: Any]]? {
        arguments[key] as? [[String: Any]]
    }

    func parsedArrayOfDicts(_ key: String) -> [[String: Any]]? {
        if let native = arrayOfDicts(key) {
            return native
        }

        guard let jsonString = string(key),
              let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return parsed
    }

    func stringArray(_ key: String) -> [String]? {
        arguments[key] as? [String]
    }

    func parsedStringArray(_ key: String) -> [String]? {
        if let native = stringArray(key) {
            return native
        }

        guard let jsonString = string(key),
              let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return nil
        }

        return parsed
    }

    func anyArray(_ key: String) -> [Any]? {
        arguments[key] as? [Any]
    }

    func parsedAnyArray(_ key: String) -> [Any]? {
        if let native = anyArray(key) {
            return native
        }

        guard let jsonString = string(key),
              let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return nil
        }

        return parsed
    }

    func date(_ key: String) -> Date? {
        guard let str = string(key) else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: str) { return date }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        return dateFormatter.date(from: str)
    }
}

struct FunctionResult {
    let id: String
    let name: String
    let response: [String: Any]

    static func success(
        id: String,
        name: String,
        message: String,
        data: [String: Any] = [:]
    ) -> FunctionResult {
        var response = data
        response["success"] = true
        response["message"] = message
        return FunctionResult(id: id, name: name, response: response)
    }

    static func error(id: String, name: String, message: String) -> FunctionResult {
        FunctionResult(
            id: id,
            name: name,
            response: ["success": false, "error": message]
        )
    }

    func toAPIFormat() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "response": response
        ]
    }
}
