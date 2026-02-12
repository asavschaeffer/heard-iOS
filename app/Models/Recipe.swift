import Foundation
import SwiftData

// MARK: - Recipe Difficulty

/// How difficult the recipe is to make.
enum RecipeDifficulty: String, Codable, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .easy: return "1.circle.fill"
        case .medium: return "2.circle.fill"
        case .hard: return "3.circle.fill"
        }
    }

    /// For the LLM: all valid difficulty strings
    static var allValidStrings: [String] {
        allCases.map { $0.rawValue }
    }

    /// Parse a user/LLM string into a difficulty.
    static func parse(_ input: String) -> RecipeDifficulty? {
        let normalized = input.lowercased().trimmingCharacters(in: .whitespaces)

        if let difficulty = RecipeDifficulty(rawValue: normalized) {
            return difficulty
        }

        let mappings: [String: RecipeDifficulty] = [
            "simple": .easy,
            "beginner": .easy,
            "quick": .easy,
            "basic": .easy,
            "moderate": .medium,
            "intermediate": .medium,
            "advanced": .hard,
            "difficult": .hard,
            "complex": .hard,
            "challenging": .hard,
        ]

        return mappings[normalized]
    }
}

// MARK: - Recipe Source

/// Where the recipe came from.
enum RecipeSource: String, Codable, CaseIterable {
    case userCreated = "user_created"
    case aiDrafted = "ai_drafted"
    case imported = "imported"

    var displayName: String {
        switch self {
        case .userCreated: return "User Created"
        case .aiDrafted: return "AI Drafted"
        case .imported: return "Imported"
        }
    }

    var icon: String {
        switch self {
        case .userCreated: return "person.fill"
        case .aiDrafted: return "sparkles"
        case .imported: return "square.and.arrow.down.fill"
        }
    }

    /// For the LLM: all valid source strings
    static var allValidStrings: [String] {
        allCases.map { $0.rawValue }
    }

    /// Parse a user/LLM string into a source.
    static func parse(_ input: String) -> RecipeSource? {
        let normalized = input.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")

        if let source = RecipeSource(rawValue: normalized) {
            return source
        }

        let mappings: [String: RecipeSource] = [
            "user": .userCreated,
            "manual": .userCreated,
            "ai": .aiDrafted,
            "generated": .aiDrafted,
            "assistant": .aiDrafted,
            "import": .imported,
            "external": .imported,
        ]

        return mappings[normalized]
    }
}

// MARK: - Recipe Ingredient

/// An ingredient within a recipe.
/// Refactored to be a 1st-class citizen (Model) for relational integrity.
@Model
final class RecipeIngredient {
    @Attribute(.unique) var id: UUID
    var name: String
    
    /// Indexed for fast "Find recipes with Chicken" queries.
    @Attribute(.spotlight) var normalizedName: String
    
    var quantity: Double?
    var unitRaw: String?
    var preparation: String?  // "diced", "room temperature", "minced"
    
    // Inverse relationship (optional, but good for graph traversal)
    var recipe: Recipe?

    /// Parsed unit enum (optional since some ingredients are "to taste")
    var unit: Unit? {
        get {
            guard let raw = unitRaw else { return nil }
            return Unit(rawValue: raw)
        }
        set {
            unitRaw = newValue?.rawValue
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double? = nil,
        unit: Unit? = nil,
        preparation: String? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.normalizedName = Recipe.normalizeIngredientName(name)
        self.quantity = quantity
        self.unitRaw = unit?.rawValue
        self.preparation = preparation?.trimmingCharacters(in: .whitespaces)
    }

    /// Human-readable display text
    var displayText: String {
        var parts: [String] = []

        if let qty = quantity {
            if qty == floor(qty) {
                parts.append("\(Int(qty))")
            } else if qty * 4 == floor(qty * 4) {
                // Handle common fractions
                let fractions: [Double: String] = [0.25: "¼", 0.5: "½", 0.75: "¾"]
                let whole = Int(qty)
                let frac = qty - Double(whole)
                if whole > 0 {
                    parts.append("\(whole)\(fractions[frac] ?? String(format: "%.2f", frac))")
                } else {
                    parts.append(fractions[frac] ?? String(format: "%.2f", qty))
                }
            } else {
                parts.append(String(format: "%.1f", qty))
            }
        }

        if let u = unit {
            parts.append(u.displayName)
        }

        parts.append(name)

        if let prep = preparation, !prep.isEmpty {
            parts.append("(\(prep))")
        }

        return parts.joined(separator: " ")
    }

    /// Create from LLM function call arguments
    static func fromArguments(_ args: [String: Any]) -> RecipeIngredient? {
        guard let name = args["name"] as? String, !name.isEmpty else {
            return nil
        }

        let quantity: Double? = {
            if let raw = args["quantity"] {
                if let qty = raw as? Double {
                    return qty
                }
                if let qty = raw as? Int {
                    return Double(qty)
                }
                if let qtyStr = raw as? String {
                    let trimmed = qtyStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        return nil
                    }
                    return Double(trimmed)
                }
            }
            return nil
        }()

        var unit: Unit? = nil
        if let unitStr = args["unit"] as? String {
            unit = Unit.parse(unitStr)
        }

        let preparation = args["preparation"] as? String
            ?? args["notes"] as? String  // Legacy support

        return RecipeIngredient(
            name: name,
            quantity: quantity,
            unit: unit,
            preparation: preparation
        )
    }
}

// MARK: - Recipe Step

/// A step in a recipe.
/// Refactored to be a 1st-class citizen (Model).
@Model
final class RecipeStep {
    @Attribute(.unique) var id: UUID
    var instruction: String
    var durationMinutes: Int?  // Optional timer for this step
    var orderIndex: Int        // For maintaining order
    
    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        instruction: String,
        durationMinutes: Int? = nil,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.instruction = instruction.trimmingCharacters(in: .whitespaces)
        self.durationMinutes = durationMinutes
        self.orderIndex = orderIndex
    }

    /// Create from LLM function call arguments
    static func fromArguments(_ args: [String: Any], index: Int) -> RecipeStep? {
        guard let instruction = args["instruction"] as? String else {
            return nil
        }

        let duration = args["duration"] as? Int
            ?? args["durationMinutes"] as? Int
            ?? args["timer"] as? Int

        return RecipeStep(
            instruction: instruction,
            durationMinutes: duration,
            orderIndex: index
        )
    }
}
// MARK: - Recipe Model

@Model
final class Recipe {
    // MARK: - Persisted Properties

    /// Unique identifier
    @Attribute(.unique) var id: UUID

    /// Display name
    var name: String

    /// Lowercase, trimmed name for matching
    @Attribute(.spotlight) var normalizedName: String

    /// Optional description
    var descriptionText: String?

    /// Freeform notes for variations, tips, pairings, and chef context.
    var notes: String?

    /// Optional cooking temperature (e.g. "350F", "180C", "medium-high").
    var cookingTemperature: String?

    /// Proper Relational Storage. NO JSON BLOBS.
    @Relationship(deleteRule: .cascade, inverse: \RecipeIngredient.recipe)
    var ingredients: [RecipeIngredient]

    @Relationship(deleteRule: .cascade, inverse: \RecipeStep.recipe)
    var steps: [RecipeStep]

    /// Prep time in minutes
    var prepTime: Int?

    /// Cook time in minutes
    var cookTime: Int?

    /// Number of servings
    var servings: Int?

    /// Recipe tags (cuisine, diet, etc.) - stored as comma-separated string for SwiftData compatibility
    private var tagsData: String = ""
    
    var tags: [String] {
        get {
            tagsData.isEmpty ? [] : tagsData.components(separatedBy: ",").filter { !$0.isEmpty }
        }
        set {
            tagsData = newValue.joined(separator: ",")
        }
    }

    /// Difficulty level (stored as raw string)
    var difficultyRaw: String

    /// Where this recipe came from (stored as raw string)
    var sourceRaw: String

    /// Optional image data
    @Attribute(.externalStorage) // Store images externally if possible to keep DB light
    var imageData: Data?

    /// When created
    var createdAt: Date

    /// When last modified
    var updatedAt: Date

    // MARK: - Computed Properties

    /// Parsed difficulty enum
    var difficulty: RecipeDifficulty {
        get { RecipeDifficulty(rawValue: difficultyRaw) ?? .medium }
        set { difficultyRaw = newValue.rawValue }
    }

    /// Parsed source enum
    var source: RecipeSource {
        get { RecipeSource(rawValue: sourceRaw) ?? .userCreated }
        set { sourceRaw = newValue.rawValue }
    }

    /// Total time (prep + cook)
    var totalTime: Int? {
        switch (prepTime, cookTime) {
        case let (prep?, cook?): return prep + cook
        case let (prep?, nil): return prep
        case let (nil, cook?): return cook
        case (nil, nil): return nil
        }
    }

    /// Formatted total time string
    var formattedTotalTime: String? {
        guard let total = totalTime else { return nil }
        if total < 60 {
            return "\(total) min"
        }
        let hours = total / 60
        let minutes = total % 60
        if minutes == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(minutes) min"
    }

    /// Formatted prep time
    var formattedPrepTime: String? {
        guard let prep = prepTime else { return nil }
        return prep < 60 ? "\(prep) min" : "\(prep / 60) hr \(prep % 60) min"
    }

    /// Formatted cook time
    var formattedCookTime: String? {
        guard let cook = cookTime else { return nil }
        return cook < 60 ? "\(cook) min" : "\(cook / 60) hr \(cook % 60) min"
    }
    
    // Sort steps by orderIndex
    var orderedSteps: [RecipeStep] {
        steps.sorted { $0.orderIndex < $1.orderIndex }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        notes: String? = nil,
        cookingTemperature: String? = nil,
        ingredients: [RecipeIngredient] = [],
        steps: [RecipeStep] = [],
        prepTime: Int? = nil,
        cookTime: Int? = nil,
        servings: Int? = nil,
        tags: [String] = [],
        difficulty: RecipeDifficulty = .medium,
        source: RecipeSource = .userCreated,
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.normalizedName = Recipe.normalize(name)
        self.descriptionText = description?.trimmingCharacters(in: .whitespaces)
        if let notes {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            self.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        } else {
            self.notes = nil
        }
        if let cookingTemperature {
            let trimmedTemperature = cookingTemperature.trimmingCharacters(in: .whitespacesAndNewlines)
            self.cookingTemperature = trimmedTemperature.isEmpty ? nil : trimmedTemperature
        } else {
            self.cookingTemperature = nil
        }
        self.ingredients = ingredients
        self.steps = steps
        self.prepTime = prepTime.map { max(0, $0) }
        self.cookTime = cookTime.map { max(0, $0) }
        self.servings = servings.map { max(1, $0) }
        self.tagsData = tags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
        self.difficultyRaw = difficulty.rawValue
        self.sourceRaw = source.rawValue
        self.imageData = imageData
        self.createdAt = .now
        self.updatedAt = .now
    }

    // MARK: - Normalization

    /// Normalize a recipe name for matching.
    static func normalize(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespaces)
    }

    /// Normalize an ingredient name for matching against inventory.
    static func normalizeIngredientName(_ name: String) -> String {
        Ingredient.normalize(name)
    }

    // MARK: - Mutation

    /// Update fields from a dictionary (used by LLM function calls).
    func update(from changes: [String: Any]) {
        if let newName = changes["name"] as? String {
            self.name = newName.trimmingCharacters(in: .whitespaces)
            self.normalizedName = Recipe.normalize(newName)
        }
        if let newDesc = changes["description"] as? String {
            let trimmedDesc = newDesc.trimmingCharacters(in: .whitespacesAndNewlines)
            self.descriptionText = trimmedDesc.isEmpty ? nil : trimmedDesc
        }
        if let newNotes = changes["notes"] as? String {
            let trimmedNotes = newNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            self.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        }
        if let newCookingTemperature = changes["cookingTemperature"] as? String {
            let trimmedTemperature = newCookingTemperature.trimmingCharacters(in: .whitespacesAndNewlines)
            self.cookingTemperature = trimmedTemperature.isEmpty ? nil : trimmedTemperature
        }
        if let newPrepTime = changes["prepTime"] as? Int {
            self.prepTime = max(0, newPrepTime)
        }
        if let newCookTime = changes["cookTime"] as? Int {
            self.cookTime = max(0, newCookTime)
        }
        if let newServings = changes["servings"] as? Int {
            self.servings = max(1, newServings)
        }
        if let newTags = changes["tags"] as? [String] {
            self.tagsData = newTags.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.joined(separator: ",")
        }
        if let newDifficultyStr = changes["difficulty"] as? String,
           let newDifficulty = RecipeDifficulty.parse(newDifficultyStr) {
            self.difficulty = newDifficulty
        }

        self.updatedAt = .now
    }

    /// Add or update an ingredient in the recipe.
    func addIngredient(_ ingredient: RecipeIngredient) {
        // Check if ingredient already exists (by normalized name)
        if let existing = ingredients.first(where: { $0.normalizedName == ingredient.normalizedName }) {
            // Update existing
            existing.quantity = ingredient.quantity
            existing.unitRaw = ingredient.unitRaw
            existing.preparation = ingredient.preparation
        } else {
            ingredients.append(ingredient)
        }
        updatedAt = .now
    }

    /// Remove an ingredient from the recipe.
    func removeIngredient(named name: String) {
        let normalized = Recipe.normalizeIngredientName(name)
        if let index = ingredients.firstIndex(where: { $0.normalizedName == normalized }) {
            ingredients.remove(at: index)
            updatedAt = .now
        }
    }

    /// Add a step to the recipe.
    func addStep(_ step: RecipeStep) {
        step.orderIndex = steps.count
        steps.append(step)
        updatedAt = .now
    }

    /// Remove a step by index.
    func removeStep(at index: Int) {
        let sorted = orderedSteps
        guard index >= 0 && index < sorted.count else { return }
        
        let stepToRemove = sorted[index]
        steps.removeAll { $0.id == stepToRemove.id } // SwiftData remove
        
        // Reindex remaining steps
        let remaining = orderedSteps // Re-fetch or use local logic
        for (i, step) in remaining.enumerated() {
            step.orderIndex = i
        }
        updatedAt = .now
    }
}

// MARK: - Inventory Matching

extension Recipe {

    /// Check if this recipe can be made with the given inventory.
    /// Uses normalized name matching to handle "egg" vs "eggs".
    func canMake(with inventory: [Ingredient]) -> Bool {
        let inventoryNames = Set(inventory.map { $0.normalizedName })
        return ingredients.allSatisfy { ingredient in
            inventoryNames.contains(ingredient.normalizedName)
        }
    }

    /// Get ingredients that are missing from inventory.
    func missingIngredients(from inventory: [Ingredient]) -> [RecipeIngredient] {
        let inventoryNames = Set(inventory.map { $0.normalizedName })
        return ingredients.filter { ingredient in
            !inventoryNames.contains(ingredient.normalizedName)
        }
    }

    /// Get ingredients that are available in inventory.
    func availableIngredients(from inventory: [Ingredient]) -> [RecipeIngredient] {
        let inventoryNames = Set(inventory.map { $0.normalizedName })
        return ingredients.filter { ingredient in
            inventoryNames.contains(ingredient.normalizedName)
        }
    }

    /// Calculate match percentage with inventory (0.0 to 1.0).
    func inventoryMatchPercentage(from inventory: [Ingredient]) -> Double {
        guard !ingredients.isEmpty else { return 1.0 }
        let available = availableIngredients(from: inventory).count
        return Double(available) / Double(ingredients.count)
    }
}

// MARK: - Static Helpers for LLM Operations

extension Recipe {

    /// Find a recipe by name (case-insensitive).
    static func find(
        named name: String,
        in context: ModelContext
    ) -> Recipe? {
        let normalized = normalize(name)

        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.normalizedName == normalized }
        )

        return try? context.fetch(descriptor).first
    }

    /// Search recipes by name or tags.
    static func search(
        query: String,
        in context: ModelContext
    ) -> [Recipe] {
        let normalized = normalize(query)

        // Search by name
        let nameDescriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.normalizedName.contains(normalized) },
            sortBy: [SortDescriptor(\.name)]
        )
        var results = (try? context.fetch(nameDescriptor)) ?? []
        
        // Search by tags (this is still a bit inefficient in SwiftData predicates for array contains, 
        // but better than fetching all. If SwiftData fails here, we fallback).
        // Note: Predicate for array contains string: $0.tags.contains(normalized) matches EXACT tag.
        // We want partial match. SwiftData predicates on arrays are... tricky. 
        // For now, let's keep the memory filter for tags but ONLY for tags, and merge.
        // Ideally we'd have a separate Tag entity. 
        
        let allRecipes = list(in: context)
        let tagMatches = allRecipes.filter { recipe in
            recipe.tags.contains { $0.contains(normalized) }
        }

        // Merge results, avoiding duplicates
        let existingIds = Set(results.map { $0.id })
        for recipe in tagMatches where !existingIds.contains(recipe.id) {
            results.append(recipe)
        }

        return results
    }

    /// List all recipes, optionally filtered by tag.
    static func list(
        tag: String? = nil,
        in context: ModelContext
    ) -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(
            sortBy: [SortDescriptor(\.name)]
        )

        var results = (try? context.fetch(descriptor)) ?? []

        if let tagFilter = tag?.lowercased() {
            results = results.filter { $0.tags.contains(tagFilter) }
        }

        return results
    }

    /// Suggest recipes that can be made with available inventory.
    /// Returns recipes sorted by match percentage (best matches first).
    /// Optimized to use SQL-like logic where possible, though SwiftData makes cross-entity counting hard.
    static func suggestFromInventory(
        inventory: [Ingredient],
        maxMissingIngredients: Int = 3,
        in context: ModelContext
    ) -> [(recipe: Recipe, matchPercentage: Double, missing: [RecipeIngredient])] {
        
        // Optimization: First find recipes that contain AT LEAST ONE of our inventory items.
        // This drastically reduces the search space compared to fetching all recipes.
        // However, SwiftData predicate for "ingredients.normalizedName IN [list]" can be slow if list is huge.
        // If inventory is > 100 items, we might just fetch all.
        
        let inventoryNames = inventory.map { $0.normalizedName }
        let allRecipes: [Recipe]
        
        if inventoryNames.isEmpty {
            return []
        }
        
        // For now, fetch all is safer than a complex predicate that might crash SwiftData beta.
        // But in a real "Steve Jobs" review, we'd demand a raw SQL query or a better schema (RecipeIngredients -> Recipe).
        // Since we are limited to SwiftData:
        allRecipes = list(in: context)

        return allRecipes
            .map { recipe in
                let missing = recipe.missingIngredients(from: inventory)
                let matchPercentage = recipe.inventoryMatchPercentage(from: inventory)
                return (recipe, matchPercentage, missing)
            }
            .filter { $0.missing.count <= maxMissingIngredients }
            .sorted { $0.matchPercentage > $1.matchPercentage }
    }
}

// MARK: - LLM Schema Description

extension Recipe {
    /// A description of the data model for LLM system prompts.
    static var schemaDescription: String {
        """
        Recipe schema:
        - name: String (required) - Recipe name
        - description: String (optional) - Brief description of the dish
        - notes: String (optional) - Freeform text for variations, tips, pairings, substitutions, or chef's notes
        - cookingTemperature: String (optional) - Target cooking temperature like "350F", "180C", or "medium-high"
        - prepTime: Number (optional) - Preparation time in minutes
        - cookTime: Number (optional) - Cooking time in minutes
        - servings: Number (optional) - Number of servings
        - difficulty: String (optional) - One of: \(RecipeDifficulty.allValidStrings.joined(separator: ", "))
        - tags: Array of strings (optional) - Tags like "italian", "vegetarian", "quick"

        RecipeIngredient schema:
        - name: String (required) - Ingredient name
        - quantity: Number (optional) - Amount needed
        - unit: String (optional) - One of: \(Unit.allValidStrings.joined(separator: ", "))
        - preparation: String (optional) - How to prepare, e.g. "diced", "minced"

        RecipeStep schema:
        - instruction: String (required) - What to do
        - durationMinutes: Number (optional) - Timer for this step

        When creating recipes:
        - Names are matched case-insensitively
        - Ingredients are matched to inventory using normalized names
        - Tags should be lowercase
        - Use notes for useful freeform context that doesn't fit structured fields
        """
    }
}
