import Foundation
import SwiftData

enum IngredientCategory: String, Codable, CaseIterable {
    case produce = "Produce"
    case dairy = "Dairy"
    case meat = "Meat"
    case seafood = "Seafood"
    case pantry = "Pantry"
    case frozen = "Frozen"
    case condiments = "Condiments"
    case beverages = "Beverages"
    case other = "Other"

    var icon: String {
        switch self {
        case .produce: return "leaf.fill"
        case .dairy: return "cup.and.saucer.fill"
        case .meat: return "fork.knife"
        case .seafood: return "fish.fill"
        case .pantry: return "cabinet.fill"
        case .frozen: return "snowflake"
        case .condiments: return "drop.fill"
        case .beverages: return "mug.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum StorageLocation: String, Codable, CaseIterable {
    case fridge = "Fridge"
    case freezer = "Freezer"
    case pantry = "Pantry"
    case counter = "Counter"

    var icon: String {
        switch self {
        case .fridge: return "refrigerator.fill"
        case .freezer: return "snowflake"
        case .pantry: return "cabinet.fill"
        case .counter: return "table.furniture.fill"
        }
    }
}

@Model
final class Ingredient {
    var id: UUID
    var name: String
    var quantity: Double
    var unit: String
    var categoryRaw: String
    var locationRaw: String
    var expiryDate: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

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
        return expiry < Date()
    }

    var isExpiringSoon: Bool {
        guard let expiry = expiryDate else { return false }
        let threeDaysFromNow = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return expiry <= threeDaysFromNow && expiry >= Date()
    }

    var displayQuantity: String {
        if quantity == floor(quantity) {
            return "\(Int(quantity)) \(unit)"
        }
        return String(format: "%.1f %@", quantity, unit)
    }

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double = 1.0,
        unit: String = "count",
        category: IngredientCategory = .other,
        location: StorageLocation = .pantry,
        expiryDate: Date? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.categoryRaw = category.rawValue
        self.locationRaw = location.rawValue
        self.expiryDate = expiryDate
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension Ingredient {
    static var commonUnits: [String] {
        ["count", "cups", "tbsp", "tsp", "oz", "lbs", "g", "kg", "ml", "L", "bunch", "cloves", "slices"]
    }
}
