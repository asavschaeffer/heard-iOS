import Foundation

// MARK: - Gemini Function Declarations

/// Represents a function that can be called by Gemini during a conversation
struct GeminiFunctionDeclaration: Codable {
    let name: String
    let description: String
    let parameters: GeminiFunctionParameters
}

struct GeminiFunctionParameters: Codable {
    let type: String
    let properties: [String: GeminiPropertySchema]
    let required: [String]
}

struct GeminiPropertySchema: Codable {
    let type: String
    let description: String
    let enumValues: [String]?

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
}

// MARK: - Function Call Request/Response

struct GeminiFunctionCall: Codable {
    let name: String
    let args: [String: AnyCodable]
}

struct GeminiFunctionResponse: Codable {
    let name: String
    let response: [String: AnyCodable]
}

// MARK: - AnyCodable Helper for dynamic JSON values

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
    var arrayValue: [Any]? { value as? [Any] }
    var dictValue: [String: Any]? { value as? [String: Any] }
}

// MARK: - Tool Definitions

struct GeminiTools {

    // MARK: - Inventory Management Tools

    static let inventoryAdd = GeminiFunctionDeclaration(
        name: "inventory_add",
        description: "Add a new ingredient to the user's inventory",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "name": GeminiPropertySchema(type: "string", description: "Name of the ingredient", enumValues: nil),
                "quantity": GeminiPropertySchema(type: "number", description: "Amount of the ingredient", enumValues: nil),
                "unit": GeminiPropertySchema(type: "string", description: "Unit of measurement (e.g., cups, lbs, count)", enumValues: nil),
                "category": GeminiPropertySchema(type: "string", description: "Category of the ingredient", enumValues: IngredientCategory.allCases.map { $0.rawValue }),
                "location": GeminiPropertySchema(type: "string", description: "Storage location", enumValues: StorageLocation.allCases.map { $0.rawValue }),
                "expiry": GeminiPropertySchema(type: "string", description: "Expiry date in ISO 8601 format (optional)", enumValues: nil)
            ],
            required: ["name", "quantity", "unit"]
        )
    )

    static let inventoryRemove = GeminiFunctionDeclaration(
        name: "inventory_remove",
        description: "Remove an ingredient from inventory or reduce its quantity",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "name": GeminiPropertySchema(type: "string", description: "Name of the ingredient to remove", enumValues: nil),
                "quantity": GeminiPropertySchema(type: "number", description: "Amount to remove (if not specified, removes entirely)", enumValues: nil)
            ],
            required: ["name"]
        )
    )

    static let inventoryUpdate = GeminiFunctionDeclaration(
        name: "inventory_update",
        description: "Update properties of an existing ingredient",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "name": GeminiPropertySchema(type: "string", description: "Name of the ingredient to update", enumValues: nil),
                "newName": GeminiPropertySchema(type: "string", description: "New name for the ingredient", enumValues: nil),
                "quantity": GeminiPropertySchema(type: "number", description: "New quantity", enumValues: nil),
                "unit": GeminiPropertySchema(type: "string", description: "New unit", enumValues: nil),
                "category": GeminiPropertySchema(type: "string", description: "New category", enumValues: IngredientCategory.allCases.map { $0.rawValue }),
                "location": GeminiPropertySchema(type: "string", description: "New storage location", enumValues: StorageLocation.allCases.map { $0.rawValue }),
                "expiry": GeminiPropertySchema(type: "string", description: "New expiry date in ISO 8601 format", enumValues: nil)
            ],
            required: ["name"]
        )
    )

    static let inventoryList = GeminiFunctionDeclaration(
        name: "inventory_list",
        description: "List ingredients in the inventory, optionally filtered by category or location",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "category": GeminiPropertySchema(type: "string", description: "Filter by category", enumValues: IngredientCategory.allCases.map { $0.rawValue }),
                "location": GeminiPropertySchema(type: "string", description: "Filter by storage location", enumValues: StorageLocation.allCases.map { $0.rawValue })
            ],
            required: []
        )
    )

    static let inventorySearch = GeminiFunctionDeclaration(
        name: "inventory_search",
        description: "Search for ingredients by name",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "query": GeminiPropertySchema(type: "string", description: "Search query", enumValues: nil)
            ],
            required: ["query"]
        )
    )

    static let inventoryCheck = GeminiFunctionDeclaration(
        name: "inventory_check",
        description: "Check if a specific ingredient exists in inventory and get its details",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "name": GeminiPropertySchema(type: "string", description: "Name of the ingredient to check", enumValues: nil)
            ],
            required: ["name"]
        )
    )

    // MARK: - Recipe Management Tools

    static let recipeCreate = GeminiFunctionDeclaration(
        name: "recipe_create",
        description: "Create a new recipe",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "name": GeminiPropertySchema(type: "string", description: "Name of the recipe", enumValues: nil),
                "description": GeminiPropertySchema(type: "string", description: "Brief description of the recipe", enumValues: nil),
                "ingredients": GeminiPropertySchema(type: "string", description: "JSON array of ingredients with name, quantity, unit, and notes", enumValues: nil),
                "steps": GeminiPropertySchema(type: "string", description: "JSON array of step strings", enumValues: nil),
                "prepTime": GeminiPropertySchema(type: "number", description: "Preparation time in minutes", enumValues: nil),
                "cookTime": GeminiPropertySchema(type: "number", description: "Cooking time in minutes", enumValues: nil),
                "servings": GeminiPropertySchema(type: "number", description: "Number of servings", enumValues: nil),
                "tags": GeminiPropertySchema(type: "string", description: "JSON array of tag strings", enumValues: nil)
            ],
            required: ["name", "ingredients", "steps"]
        )
    )

    static let recipeUpdate = GeminiFunctionDeclaration(
        name: "recipe_update",
        description: "Update an existing recipe",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "id": GeminiPropertySchema(type: "string", description: "UUID of the recipe to update", enumValues: nil),
                "name": GeminiPropertySchema(type: "string", description: "New name", enumValues: nil),
                "description": GeminiPropertySchema(type: "string", description: "New description", enumValues: nil),
                "ingredients": GeminiPropertySchema(type: "string", description: "New ingredients JSON array", enumValues: nil),
                "steps": GeminiPropertySchema(type: "string", description: "New steps JSON array", enumValues: nil),
                "prepTime": GeminiPropertySchema(type: "number", description: "New prep time in minutes", enumValues: nil),
                "cookTime": GeminiPropertySchema(type: "number", description: "New cook time in minutes", enumValues: nil),
                "servings": GeminiPropertySchema(type: "number", description: "New servings count", enumValues: nil),
                "tags": GeminiPropertySchema(type: "string", description: "New tags JSON array", enumValues: nil)
            ],
            required: ["id"]
        )
    )

    static let recipeDelete = GeminiFunctionDeclaration(
        name: "recipe_delete",
        description: "Delete a recipe",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "id": GeminiPropertySchema(type: "string", description: "UUID of the recipe to delete", enumValues: nil)
            ],
            required: ["id"]
        )
    )

    static let recipeList = GeminiFunctionDeclaration(
        name: "recipe_list",
        description: "List all recipes, optionally filtered by tags",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "tags": GeminiPropertySchema(type: "string", description: "JSON array of tags to filter by", enumValues: nil)
            ],
            required: []
        )
    )

    static let recipeSearch = GeminiFunctionDeclaration(
        name: "recipe_search",
        description: "Search for recipes by name or ingredients",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "query": GeminiPropertySchema(type: "string", description: "Search query", enumValues: nil)
            ],
            required: ["query"]
        )
    )

    static let recipeSuggest = GeminiFunctionDeclaration(
        name: "recipe_suggest",
        description: "Get recipe suggestions based on available inventory and constraints",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "constraints": GeminiPropertySchema(type: "string", description: "Optional constraints like 'quick', 'vegetarian', 'uses chicken'", enumValues: nil),
                "useInventory": GeminiPropertySchema(type: "boolean", description: "Whether to only suggest recipes that can be made with current inventory", enumValues: nil)
            ],
            required: []
        )
    )

    // MARK: - Photo Processing Tools

    static let parseReceipt = GeminiFunctionDeclaration(
        name: "parse_receipt",
        description: "Parse a receipt image to extract purchased grocery items",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "imageBase64": GeminiPropertySchema(type: "string", description: "Base64 encoded image data", enumValues: nil)
            ],
            required: ["imageBase64"]
        )
    )

    static let parseGroceries = GeminiFunctionDeclaration(
        name: "parse_groceries",
        description: "Identify grocery items visible in a photo",
        parameters: GeminiFunctionParameters(
            type: "object",
            properties: [
                "imageBase64": GeminiPropertySchema(type: "string", description: "Base64 encoded image data", enumValues: nil)
            ],
            required: ["imageBase64"]
        )
    )

    // MARK: - All Tools

    static var allTools: [GeminiFunctionDeclaration] {
        [
            // Inventory
            inventoryAdd,
            inventoryRemove,
            inventoryUpdate,
            inventoryList,
            inventorySearch,
            inventoryCheck,
            // Recipes
            recipeCreate,
            recipeUpdate,
            recipeDelete,
            recipeList,
            recipeSearch,
            recipeSuggest,
            // Photo
            parseReceipt,
            parseGroceries
        ]
    }

    /// Convert tools to Gemini API format
    static func toAPIFormat() -> [[String: Any]] {
        allTools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "parameters": [
                    "type": tool.parameters.type,
                    "properties": tool.parameters.properties.mapValues { prop in
                        var propDict: [String: Any] = [
                            "type": prop.type,
                            "description": prop.description
                        ]
                        if let enumValues = prop.enumValues {
                            propDict["enum"] = enumValues
                        }
                        return propDict
                    },
                    "required": tool.parameters.required
                ]
            ]
        }
    }
}
