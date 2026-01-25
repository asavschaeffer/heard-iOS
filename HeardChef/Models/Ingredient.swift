import Foundation
import SwiftData

// MARK: - Update Parameters

/// structured parameters for updating an ingredient.
/// Eliminates "Stringly Typed" dictionary passing.
struct IngredientUpdateParams {
    var name: String?
    var quantity: Double?
    var unit: String?
    var category: String?
    var location: String?
    var expiryDate: Date?
    var notes: String?
    
    init(
        name: String? = nil,
        quantity: Double? = nil,
        unit: String? = nil,
        category: String? = nil,
        location: String? = nil,
        expiryDate: Date? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.location = location
        self.expiryDate = expiryDate
        self.notes = notes
    }
}

// MARK: - Unit

/// Standardized units for ingredients.
/// The LLM should map user input to one of these values.
enum Unit: String, Codable, CaseIterable {
    // Count
    case whole = "whole"
    case piece = "piece"

    // Volume - Cooking (US)
    case cups = "cups"
    case tablespoons = "tbsp"
    case teaspoons = "tsp"

    // Volume - Metric
    case milliliters = "ml"
    case liters = "L"

    // Weight - US
    case ounces = "oz"
    case pounds = "lbs"

    // Weight - Metric
    case grams = "g"
    case kilograms = "kg"

    // Produce-specific
    case bunch = "bunch"
    case head = "head"
    case cloves = "cloves"
    case stalks = "stalks"

    // Portions
    case slices = "slices"
    case strips = "strips"
    case cubes = "cubes"

    // Packaging
    case cans = "cans"
    case bottles = "bottles"
    case packages = "packages"
    case bags = "bags"
    case boxes = "boxes"
    case cartons = "cartons"
    case jars = "jars"
    case dozen = "dozen"

    /// Display name for UI
    var displayName: String {
        rawValue
    }

    /// For the LLM: all valid unit strings it can use
    static var allValidStrings: [String] {
        allCases.map { $0.rawValue }
    }

    /// Attempt to parse a user/LLM string into a Unit.
    static func parse(_ input: String) -> Unit? {
        let normalized = input.lowercased().trimmingCharacters(in: .whitespaces)

        // Direct match
        if let unit = Unit(rawValue: normalized) {
            return unit
        }

        // Common variations
        let mappings: [String: Unit] = [
            // Singular -> Plural
            "cup": .cups,
            "tablespoon": .tablespoons,
            "teaspoon": .teaspoons,
            "ounce": .ounces,
            "pound": .pounds, "lb": .pounds,
            "gram": .grams,
            "kilogram": .kilograms,
            "milliliter": .milliliters,
            "liter": .liters,
            "clove": .cloves,
            "stalk": .stalks,
            "slice": .slices,
            "strip": .strips,
            "cube": .cubes,
            "can": .cans,
            "bottle": .bottles,
            "package": .packages, "pkg": .packages,
            "bag": .bags,
            "box": .boxes,
            "carton": .cartons,
            "jar": .jars,

            // Abbreviations
            "tbsps": .tablespoons, "tbs": .tablespoons,
            "tsps": .teaspoons, "ts": .teaspoons,
            "ozs": .ounces,
            "lbs": .pounds,
            "ml": .milliliters, "mls": .milliliters,
            "l": .liters,
            "g": .grams, "gs": .grams,
            "kg": .kilograms, "kgs": .kilograms,

            // Other
            "item": .piece, "items": .piece,
            "count": .piece,
            "ea": .piece, "each": .piece,
        ]

        return mappings[normalized]
    }
}

// MARK: - Storage Location

/// Where the ingredient is physically stored.
enum StorageLocation: String, Codable, CaseIterable {
    case fridge = "fridge"
    case freezer = "freezer"
    case pantry = "pantry"
    case counter = "counter"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .fridge: return "refrigerator.fill"
        case .freezer: return "snowflake"
        case .pantry: return "cabinet.fill"
        case .counter: return "table.furniture.fill"
        }
    }

    static var allValidStrings: [String] {
        allCases.map { $0.rawValue }
    }

    static func parse(_ input: String) -> StorageLocation? {
        let normalized = input.lowercased().trimmingCharacters(in: .whitespaces)

        if let location = StorageLocation(rawValue: normalized) {
            return location
        }

        let mappings: [String: StorageLocation] = [
            "refrigerator": .fridge,
            "icebox": .fridge,
            "cooler": .fridge,
            "deep freeze": .freezer,
            "cupboard": .pantry,
            "cabinet": .pantry,
            "shelf": .pantry,
            "countertop": .counter,
            "bench": .counter,
        ]

        return mappings[normalized]
    }
}

// MARK: - Ingredient Category

/// What TYPE of ingredient this is.
enum IngredientCategory: String, Codable, CaseIterable {
    case produce = "produce"
    case protein = "protein"
    case dairy = "dairy"
    case grains = "grains"
    case spices = "spices"
    case condiments = "condiments"
    case beverages = "beverages"
    case snacks = "snacks"
    case baking = "baking"
    case canned = "canned"
    case other = "other"

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .produce: return "leaf.fill"
        case .protein: return "fish.fill"
        case .dairy: return "cup.and.saucer.fill"
        case .grains: return "wheat"
        case .spices: return "laurel.leading"
        case .condiments: return "drop.fill"
        case .beverages: return "mug.fill"
        case .snacks: return "popcorn.fill"
        case .baking: return "birthday.cake.fill"
        case .canned: return "cylinder.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    static var allValidStrings: [String] {
        allCases.map { $0.rawValue }
    }

    static func parse(_ input: String) -> IngredientCategory? {
        let normalized = input.lowercased().trimmingCharacters(in: .whitespaces)

        if let category = IngredientCategory(rawValue: normalized) {
            return category
        }

        let mappings: [String: IngredientCategory] = [
            "vegetables": .produce, "vegetable": .produce,
            "fruits": .produce, "fruit": .produce,
            "veggies": .produce,
            "meat": .protein, "meats": .protein,
            "fish": .protein, "seafood": .protein,
            "poultry": .protein,
            "eggs": .protein,
            "milk": .dairy, "cheese": .dairy,
            "bread": .grains, "pasta": .grains, "rice": .grains,
            "carbs": .grains,
            "spice": .spices, "herb": .spices, "herbs": .spices,
            "seasoning": .spices, "seasonings": .spices,
            "sauce": .condiments, "sauces": .condiments,
            "oil": .condiments, "oils": .condiments,
            "drinks": .beverages, "drink": .beverages,
            "snack": .snacks,
            "sugar": .baking, "flour": .baking,
            "cans": .canned, "tinned": .canned,
        ]

        return mappings[normalized]
    }
}

// MARK: - Ingredient Model

@Model
final class Ingredient {
    // MARK: - Persisted Properties

    @Attribute(.unique) var id: UUID
    var name: String
    @Attribute(.unique, .spotlight) var normalizedName: String
    var quantity: Double
    var unitRaw: String
    var categoryRaw: String
    var locationRaw: String
    var expiryDate: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var unit: Unit {
        get { Unit(rawValue: unitRaw) ?? .piece }
        set { unitRaw = newValue.rawValue }
    }

    var category: IngredientCategory {
        get { IngredientCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var location: StorageLocation {
        get { StorageLocation(rawValue: locationRaw) ?? .pantry }
        set { locationRaw = newValue.rawValue }
    }

    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        return expiry < Date.now
    }

    var isExpiringSoon: Bool {
        guard let expiry = expiryDate else { return false }
        guard !isExpired else { return false }
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
        return expiry <= threeDaysFromNow
    }

    var daysUntilExpiry: Int? {
        guard let expiry = expiryDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.startOfDay(for: expiry)
        return calendar.dateComponents([.day], from: start, to: end).day
    }

    var displayQuantity: String {
        let qty: String
        if quantity == floor(quantity) {
            qty = String(Int(quantity))
        } else if quantity * 4 == floor(quantity * 4) {
            let fractions: [Double: String] = [0.25: "¼", 0.5: "½", 0.75: "¾"]
            let whole = Int(quantity)
            let frac = quantity - Double(whole)
            if whole > 0 {
                qty = "\(whole)\(fractions[frac] ?? String(format: "%.2f", frac))"
            } else {
                qty = fractions[frac] ?? String(format: "%.2f", quantity)
            }
        } else {
            qty = String(format: "%.1f", quantity)
        }
        return "\(qty) \(unitRaw)"
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double,
        unit: Unit,
        category: IngredientCategory = .other,
        location: StorageLocation = .pantry,
        expiryDate: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespaces)
        self.normalizedName = Ingredient.normalize(name)
        self.quantity = max(0, quantity)
        self.unitRaw = unit.rawValue
        self.categoryRaw = category.rawValue
        self.locationRaw = location.rawValue
        self.expiryDate = expiryDate
        self.notes = notes?.trimmingCharacters(in: .whitespaces)
        self.createdAt = .now
        self.updatedAt = .now
    }

    // MARK: - Normalization

    static func normalize(_ name: String) -> String {
        var result = name.lowercased().trimmingCharacters(in: .whitespaces)
        // Basic stemming
        if result.hasSuffix("ies") {
            result = String(result.dropLast(3)) + "y"
        } else if result.hasSuffix("es") && result.count > 3 {
            let withoutEs = String(result.dropLast(2))
            if withoutEs.hasSuffix("o") || withoutEs.hasSuffix("ch") || withoutEs.hasSuffix("sh") {
                result = withoutEs
            } else {
                result = String(result.dropLast())
            }
        } else if result.hasSuffix("s") && result.count > 2 {
            result = String(result.dropLast())
        }
        return result
    }

    // MARK: - Mutation

    func addQuantity(_ amount: Double) {
        quantity = max(0, quantity + amount)
        updatedAt = .now
    }

    @discardableResult
    func removeQuantity(_ amount: Double) -> Double {
        let toRemove = min(quantity, max(0, amount))
        quantity -= toRemove
        updatedAt = .now
        return toRemove
    }

    /// Update using strongly-typed parameters.
    func update(with params: IngredientUpdateParams) {
        if let newName = params.name {
            self.name = newName.trimmingCharacters(in: .whitespaces)
            self.normalizedName = Ingredient.normalize(newName)
        }
        if let newQuantity = params.quantity {
            self.quantity = max(0, newQuantity)
        }
        if let newUnitStr = params.unit, let newUnit = Unit.parse(newUnitStr) {
            self.unit = newUnit
        }
        if let newCategoryStr = params.category, let newCategory = IngredientCategory.parse(newCategoryStr) {
            self.category = newCategory
        }
        if let newLocationStr = params.location, let newLocation = StorageLocation.parse(newLocationStr) {
            self.location = newLocation
        }
        if let newExpiry = params.expiryDate {
            self.expiryDate = newExpiry
        }
        if let newNotes = params.notes {
            self.notes = newNotes.isEmpty ? nil : newNotes.trimmingCharacters(in: .whitespaces)
        }
        self.updatedAt = .now
    }
}

// MARK: - Static Helpers for LLM Operations

extension Ingredient {

    static func find(named name: String, in context: ModelContext) -> Ingredient? {
        let normalized = normalize(name)
        let descriptor = FetchDescriptor<Ingredient>(
            predicate: #Predicate { $0.normalizedName == normalized }
        )
        return try? context.fetch(descriptor).first
    }

    static func search(query: String, in context: ModelContext) -> [Ingredient] {
        let normalized = normalize(query)
        let descriptor = FetchDescriptor<Ingredient>(
            predicate: #Predicate { $0.normalizedName.contains(normalized) },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @discardableResult
    static func findOrCreate(
        name: String,
        quantity: Double,
        unit: Unit,
        category: IngredientCategory = .other,
        location: StorageLocation = .pantry,
        expiryDate: Date? = nil,
        notes: String? = nil,
        mergeQuantity: Bool = true,
        in context: ModelContext
    ) -> (ingredient: Ingredient, wasCreated: Bool) {

        if let existing = find(named: name, in: context) {
            if mergeQuantity {
                existing.addQuantity(quantity)
                existing.location = location
                if let newExpiry = expiryDate {
                    if let existingExpiry = existing.expiryDate {
                        if newExpiry < existingExpiry { existing.expiryDate = newExpiry }
                    } else {
                        existing.expiryDate = newExpiry
                    }
                }
            }
            return (existing, false)
        }

        let new = Ingredient(
            name: name,
            quantity: quantity,
            unit: unit,
            category: category,
            location: location,
            expiryDate: expiryDate,
            notes: notes
        )
        context.insert(new)
        return (new, true)
    }

    static func list(
        category: IngredientCategory? = nil,
        location: StorageLocation? = nil,
        in context: ModelContext
    ) -> [Ingredient] {
        var descriptor = FetchDescriptor<Ingredient>(
            sortBy: [SortDescriptor(\.name)]
        )
        
        // Note: Multi-field predicates in SwiftData can be tricky depending on version.
        // We use if/else to be safe and explicit.
        if let cat = category, let loc = location {
            let catRaw = cat.rawValue
            let locRaw = loc.rawValue
            descriptor.predicate = #Predicate {
                $0.categoryRaw == catRaw && $0.locationRaw == locRaw
            }
        } else if let cat = category {
            let catRaw = cat.rawValue
            descriptor.predicate = #Predicate { $0.categoryRaw == catRaw }
        } else if let loc = location {
            let locRaw = loc.rawValue
            descriptor.predicate = #Predicate { $0.locationRaw == locRaw }
        }

        return (try? context.fetch(descriptor)) ?? []
    }

    static func expiringItems(in context: ModelContext) -> [Ingredient] {
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
        let descriptor = FetchDescriptor<Ingredient>(
            predicate: #Predicate {
                $0.expiryDate != nil && $0.expiryDate! <= threeDaysFromNow
            },
            sortBy: [SortDescriptor(\.expiryDate)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - LLM Schema Description

extension Ingredient {
    static var schemaDescription: String {
        """
        Ingredient schema:
        - name: String (required) - The ingredient name, e.g. "Eggs", "Chicken breast"
        - quantity: Number (required) - Amount, must be > 0
        - unit: String (required) - One of: \(Unit.allValidStrings.joined(separator: ", "))
        - category: String (optional) - One of: \(IngredientCategory.allValidStrings.joined(separator: ", "))
        - location: String (optional) - One of: \(StorageLocation.allValidStrings.joined(separator: ", "))
        - expiryDate: ISO8601 date string (optional) - When the ingredient expires
        - notes: String (optional) - Additional notes

        When adding ingredients:
        - If an ingredient with the same name exists, quantities will be merged
        - Names are matched case-insensitively ("eggs" matches "Eggs")
        - Singular/plural forms are matched ("egg" matches "eggs")
        """
    }
}
