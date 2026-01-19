import Foundation
import SwiftData

struct RecipeIngredient: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var quantity: Double?
    var unit: String?
    var notes: String?

    init(id: UUID = UUID(), name: String, quantity: Double? = nil, unit: String? = nil, notes: String? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
    }

    var displayText: String {
        var parts: [String] = []

        if let qty = quantity {
            if qty == floor(qty) {
                parts.append("\(Int(qty))")
            } else {
                parts.append(String(format: "%.1f", qty))
            }
        }

        if let u = unit, !u.isEmpty {
            parts.append(u)
        }

        parts.append(name)

        if let n = notes, !n.isEmpty {
            parts.append("(\(n))")
        }

        return parts.joined(separator: " ")
    }
}

enum RecipeSource: String, Codable, CaseIterable {
    case userCreated = "User Created"
    case aiDrafted = "AI Drafted"
    case imported = "Imported"

    var icon: String {
        switch self {
        case .userCreated: return "person.fill"
        case .aiDrafted: return "sparkles"
        case .imported: return "square.and.arrow.down.fill"
        }
    }
}

@Model
final class Recipe {
    var id: UUID
    var name: String
    var descriptionText: String?
    var ingredientsData: Data
    var steps: [String]
    var prepTime: Int?
    var cookTime: Int?
    var servings: Int?
    var tags: [String]
    var sourceRaw: String
    var imageData: Data?
    var createdAt: Date
    var updatedAt: Date

    var source: RecipeSource {
        get { RecipeSource(rawValue: sourceRaw) ?? .userCreated }
        set { sourceRaw = newValue.rawValue }
    }

    var ingredients: [RecipeIngredient] {
        get {
            (try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData)) ?? []
        }
        set {
            ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var totalTime: Int? {
        switch (prepTime, cookTime) {
        case let (prep?, cook?):
            return prep + cook
        case let (prep?, nil):
            return prep
        case let (nil, cook?):
            return cook
        case (nil, nil):
            return nil
        }
    }

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

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        ingredients: [RecipeIngredient] = [],
        steps: [String] = [],
        prepTime: Int? = nil,
        cookTime: Int? = nil,
        servings: Int? = nil,
        tags: [String] = [],
        source: RecipeSource = .userCreated,
        imageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.descriptionText = description
        self.ingredientsData = (try? JSONEncoder().encode(ingredients)) ?? Data()
        self.steps = steps
        self.prepTime = prepTime
        self.cookTime = cookTime
        self.servings = servings
        self.tags = tags
        self.sourceRaw = source.rawValue
        self.imageData = imageData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension Recipe {
    func canMake(with inventory: [Ingredient]) -> Bool {
        let inventoryNames = Set(inventory.map { $0.name.lowercased() })
        return ingredients.allSatisfy { ingredient in
            inventoryNames.contains(ingredient.name.lowercased())
        }
    }

    func missingIngredients(from inventory: [Ingredient]) -> [RecipeIngredient] {
        let inventoryNames = Set(inventory.map { $0.name.lowercased() })
        return ingredients.filter { ingredient in
            !inventoryNames.contains(ingredient.name.lowercased())
        }
    }
}
