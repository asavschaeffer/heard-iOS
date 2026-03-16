import Foundation
import SwiftData
import FirebaseFirestore
import OSLog

/// Syncs Firestore documents → SwiftData models.
///
/// Firestore is the source of truth (written by the ADK backend).
/// SwiftData is a local read cache for offline support and fast UI.
@MainActor
final class FirestoreSync {

    static let shared = FirestoreSync()

    private let logger = Logger(subsystem: "com.heardchef", category: "FirestoreSync")
    private let db = Firestore.firestore()
    private var ingredientListener: ListenerRegistration?
    private var recipeListener: ListenerRegistration?

    // Hardcoded user ID until auth is added (Phase 4)
    private let userID = "default"

    // MARK: - Start / Stop

    /// Attach snapshot listeners for ingredients and recipes.
    func startListening(modelContext: ModelContext) {
        stopListening()

        let ingredientsRef = db.collection("users").document(userID).collection("ingredients")
        ingredientListener = ingredientsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.logger.error("[FirestoreSync] Ingredients listener error: \(error.localizedDescription)")
                return
            }
            guard let snapshot else { return }
            self.handleIngredientChanges(snapshot: snapshot, modelContext: modelContext)
        }

        let recipesRef = db.collection("users").document(userID).collection("recipes")
        recipeListener = recipesRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.logger.error("[FirestoreSync] Recipes listener error: \(error.localizedDescription)")
                return
            }
            guard let snapshot else { return }
            self.handleRecipeChanges(snapshot: snapshot, modelContext: modelContext)
        }

        logger.info("[FirestoreSync] Listening started for user=\(self.userID)")
    }

    func stopListening() {
        ingredientListener?.remove()
        ingredientListener = nil
        recipeListener?.remove()
        recipeListener = nil
    }

    // MARK: - Ingredient Sync

    private func handleIngredientChanges(snapshot: QuerySnapshot, modelContext: ModelContext) {
        for change in snapshot.documentChanges {
            let docID = change.document.documentID

            switch change.type {
            case .added, .modified:
                guard let dto = try? change.document.data(as: FirestoreIngredient.self) else {
                    logger.warning("[FirestoreSync] Failed to decode ingredient \(docID)")
                    continue
                }
                upsertIngredient(dto, firestoreID: docID, modelContext: modelContext)

            case .removed:
                deleteIngredient(firestoreID: docID, modelContext: modelContext)
            }
        }

        try? modelContext.save()
    }

    private func upsertIngredient(_ dto: FirestoreIngredient, firestoreID: String, modelContext: ModelContext) {
        // Find existing by normalized name
        let existing = Ingredient.find(named: dto.name, in: modelContext)

        if let existing {
            // Update
            existing.quantity = dto.quantity
            existing.unitRaw = dto.unit
            if let cat = dto.category { existing.categoryRaw = cat }
            if let loc = dto.location { existing.locationRaw = loc }
            existing.notes = dto.notes

            if let expiryStr = dto.expiryDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                existing.expiryDate = formatter.date(from: expiryStr)
            }
        } else {
            // Create
            let unit = Unit.parse(dto.unit) ?? .whole
            let category = dto.category.flatMap { IngredientCategory.parse($0) } ?? .other
            let location = dto.location.flatMap { StorageLocation.parse($0) } ?? .pantry

            var expiryDate: Date? = nil
            if let expiryStr = dto.expiryDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                expiryDate = formatter.date(from: expiryStr)
            }

            let (_, _) = Ingredient.findOrCreate(
                name: dto.name,
                quantity: dto.quantity,
                unit: unit,
                category: category,
                location: location,
                expiryDate: expiryDate,
                notes: dto.notes,
                mergeQuantity: false,
                in: modelContext
            )
        }
    }

    private func deleteIngredient(firestoreID: String, modelContext: ModelContext) {
        // We don't have a Firestore ID stored locally, so we'd need to match by other means.
        // For now, deletion happens via full snapshot reconciliation.
        // TODO: Add firestoreID to Ingredient model for precise deletion.
        logger.debug("[FirestoreSync] Ingredient deleted remotely: \(firestoreID)")
    }

    // MARK: - Recipe Sync

    private func handleRecipeChanges(snapshot: QuerySnapshot, modelContext: ModelContext) {
        for change in snapshot.documentChanges {
            let docID = change.document.documentID

            switch change.type {
            case .added, .modified:
                guard let dto = try? change.document.data(as: FirestoreRecipe.self) else {
                    logger.warning("[FirestoreSync] Failed to decode recipe \(docID)")
                    continue
                }
                upsertRecipe(dto, firestoreID: docID, modelContext: modelContext)

            case .removed:
                deleteRecipe(firestoreID: docID, modelContext: modelContext)
            }
        }

        try? modelContext.save()
    }

    private func upsertRecipe(_ dto: FirestoreRecipe, firestoreID: String, modelContext: ModelContext) {
        let existing = Recipe.find(named: dto.name, in: modelContext)

        let ingredients = dto.ingredients.map { ing in
            RecipeIngredient(
                name: ing.name,
                quantity: ing.quantity,
                unit: ing.unit.flatMap { Unit.parse($0) },
                preparation: ing.preparation
            )
        }

        let steps = dto.steps.enumerated().map { (i, step) in
            RecipeStep(
                instruction: step.instruction,
                durationMinutes: step.durationMinutes,
                orderIndex: step.orderIndex ?? i
            )
        }

        if let existing {
            // Update
            existing.descriptionText = dto.description
            existing.notes = dto.notes
            existing.cookingTemperature = dto.cookingTemperature
            existing.prepTime = dto.prepTime
            existing.cookTime = dto.cookTime
            existing.servings = dto.servings
            if let diff = dto.difficulty { existing.difficultyRaw = diff }
            existing.tags = dto.tags ?? []

            // Replace ingredients
            let oldIngredients = existing.ingredients
            existing.ingredients = ingredients
            for old in oldIngredients { modelContext.delete(old) }

            // Replace steps
            let oldSteps = existing.steps
            existing.steps = steps
            for old in oldSteps { modelContext.delete(old) }
        } else {
            // Create
            let difficulty = dto.difficulty.flatMap { RecipeDifficulty.parse($0) } ?? .medium
            let source: RecipeSource = {
                switch dto.source {
                case "user_created": return .userCreated
                case "imported": return .imported
                default: return .aiDrafted
                }
            }()

            let recipe = Recipe(
                name: dto.name,
                description: dto.description,
                notes: dto.notes,
                cookingTemperature: dto.cookingTemperature,
                ingredients: ingredients,
                steps: steps,
                prepTime: dto.prepTime,
                cookTime: dto.cookTime,
                servings: dto.servings,
                tags: dto.tags ?? [],
                difficulty: difficulty,
                source: source
            )
            modelContext.insert(recipe)
        }
    }

    private func deleteRecipe(firestoreID: String, modelContext: ModelContext) {
        logger.debug("[FirestoreSync] Recipe deleted remotely: \(firestoreID)")
    }
}
