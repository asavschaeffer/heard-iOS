import Foundation
import FirebaseFirestore

// MARK: - Firestore Ingredient DTO

/// Codable mirror of the Firestore `users/{uid}/ingredients/{id}` document.
/// Used by `FirestoreSync` to decode snapshot changes and map to SwiftData `Ingredient`.
struct FirestoreIngredient: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var normalizedName: String
    var quantity: Double
    var unit: String
    var category: String?
    var location: String?
    var expiryDate: String?
    var notes: String?
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

// MARK: - Firestore Recipe DTO

/// Codable mirror of the Firestore `users/{uid}/recipes/{id}` document.
struct FirestoreRecipe: Codable, Identifiable {
    @DocumentID var id: String?
    var name: String
    var normalizedName: String
    var description: String?
    var notes: String?
    var cookingTemperature: String?
    var ingredients: [FirestoreRecipeIngredient]
    var steps: [FirestoreRecipeStep]
    var prepTime: Int?
    var cookTime: Int?
    var servings: Int?
    var difficulty: String?
    var tags: [String]?
    var source: String?
    @ServerTimestamp var createdAt: Date?
    @ServerTimestamp var updatedAt: Date?
}

struct FirestoreRecipeIngredient: Codable {
    var name: String
    var normalizedName: String?
    var quantity: Double?
    var unit: String?
    var preparation: String?
}

struct FirestoreRecipeStep: Codable {
    var instruction: String
    var orderIndex: Int?
    var durationMinutes: Int?
}
