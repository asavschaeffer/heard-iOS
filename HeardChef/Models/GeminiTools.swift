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

    static func string(_ description: String) -> PropertySchema {
        PropertySchema(type: "string", description: description, enumValues: nil, properties: nil, required: nil)
    }

    static func number(_ description: String) -> PropertySchema {
        PropertySchema(type: "number", description: description, enumValues: nil, properties: nil, required: nil)
    }

    static func boolean(_ description: String) -> PropertySchema {
        PropertySchema(type: "boolean", description: description, enumValues: nil, properties: nil, required: nil)
    }

    static func stringEnum(_ description: String, values: [String]) -> PropertySchema {
        PropertySchema(type: "string", description: description, enumValues: values, properties: nil, required: nil)
    }

    static func object(_ description: String, properties: [String: PropertySchema], required: [String] = []) -> PropertySchema {
        PropertySchema(
            type: "object",
            description: description,
            enumValues: nil,
            properties: properties,
            required: required.isEmpty ? nil : required
        )
    }
}

// MARK: - Inventory Tool Declarations

enum InventoryTools {

    static let add = FunctionDeclaration(
        name: "add_ingredient",
        description: "Add an ingredient. Merges quantities if exists.",
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
        description: "Remove ingredient or reduce quantity.",
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
        description: "Update existing ingredient properties. Only include fields to change.",
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
        description: "List ingredients, optionally filtered.",
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
        description: "Search ingredients by name (partial match).",
        parameters: ParameterSchema(
            properties: [
                "query": .string("Search term")
            ],
            required: ["query"]
        )
    )

    static let check = FunctionDeclaration(
        name: "get_ingredient",
        description: "Check specifics of one ingredient.",
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
        description: "Create a new recipe.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Recipe name"),
                "description": .string("Description"),
                "ingredients": .string("JSON array: [{name, quantity?, unit?, preparation?}]"),
                "steps": .string("JSON array: [string] or [{instruction, durationMinutes?}]"),
                "prepTime": .number("Minutes"),
                "cookTime": .number("Minutes"),
                "servings": .number("Servings"),
                "difficulty": .stringEnum("Difficulty", values: RecipeDifficulty.allValidStrings),
                "tags": .string("JSON array of tags")
            ],
            required: ["name", "ingredients", "steps"]
        )
    )
    
    // MARK: - Update (Missing Piece)
    
    static let update = FunctionDeclaration(
        name: "update_recipe",
        description: "Update an existing recipe. Only provide fields to change.",
        parameters: ParameterSchema(
            properties: [
                "name": .string("Name of recipe to update"),
                "newName": .string("New name"),
                "description": .string("New description"),
                "ingredients": .string("New JSON array (replaces old list)"),
                "steps": .string("New JSON array (replaces old list)"),
                "prepTime": .number("New prep time"),
                "cookTime": .number("New cook time"),
                "servings": .number("New servings"),
                "difficulty": .stringEnum("New difficulty", values: RecipeDifficulty.allValidStrings),
                "tags": .string("New tags JSON")
            ],
            required: ["name"]
        )
    )

    static let list = FunctionDeclaration(
        name: "list_recipes",
        description: "List recipes summary.",
        parameters: ParameterSchema(
            properties: [
                "tag": .string("Filter by tag")
            ],
            required: []
        )
    )

    static let search = FunctionDeclaration(
        name: "search_recipes",
        description: "Search recipes by name/tag.",
        parameters: ParameterSchema(
            properties: [
                "query": .string("Search term")
            ],
            required: ["query"]
        )
    )

    static let suggest = FunctionDeclaration(
        name: "suggest_recipes",
        description: "Suggest recipes from inventory.",
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
        description: "Get the full recipe including ingredients and steps.",
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
        description: "Delete a recipe.",
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
                        var propDict: [String: Any] = [
                            "type": pair.value.type,
                            "description": pair.value.description
                        ]
                        if let enumVals = pair.value.enumValues {
                            propDict["enum"] = enumVals
                        }
                        if let nestedProperties = pair.value.properties {
                            propDict["properties"] = nestedProperties.reduce(into: [String: Any]()) { nestedResult, nestedPair in
                                var nestedDict: [String: Any] = [
                                    "type": nestedPair.value.type,
                                    "description": nestedPair.value.description
                                ]
                                if let nestedEnum = nestedPair.value.enumValues {
                                    nestedDict["enum"] = nestedEnum
                                }
                                nestedResult[nestedPair.key] = nestedDict
                            }
                        }
                        if let nestedRequired = pair.value.required {
                            propDict["required"] = nestedRequired
                        }
                        result[pair.key] = propDict
                    },
                    "required": decl.parameters.required
                ] as [String: Any]
            ]
        }
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
