import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var inventory: [Ingredient]

    let recipe: Recipe

    @State private var showingEditSheet = false
    @State private var currentStep = 0
    @State private var showingCookingMode = false
    @State private var notesExpanded = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Image
                    if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipped()
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        // Title and description
                        headerSection

                        // Quick stats
                        statsSection

                        if let notes = recipe.notes, !notes.isEmpty {
                            Divider()
                            notesSection(notes)
                        }

                        Divider()

                        // Ingredients
                        ingredientsSection

                        Divider()

                        // Steps
                        stepsSection
                    }
                    .padding()
                }
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }

                    Button {
                        showingCookingMode = true
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .disabled(recipe.orderedSteps.isEmpty)
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                RecipeEditView(recipe: recipe)
            }
            .fullScreenCover(isPresented: $showingCookingMode) {
                CookingModeView(recipe: recipe)
            }
        }
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: recipe.source.icon)
                        .foregroundStyle(.secondary)
                    Text(recipe.source.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Image(systemName: recipe.difficulty.icon)
                        .foregroundStyle(.orange)
                    Text(recipe.difficulty.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let description = recipe.descriptionText, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stats Section

    @ViewBuilder
    private var statsSection: some View {
        HStack(spacing: 20) {
            if let prep = recipe.prepTime {
                StatBadge(title: "Prep", value: "\(prep) min", icon: "clock")
            }

            if let cook = recipe.cookTime {
                StatBadge(title: "Cook", value: "\(cook) min", icon: "flame")
            }

            if let servings = recipe.servings {
                StatBadge(title: "Serves", value: "\(servings)", icon: "person.2")
            }

            if let temp = recipe.cookingTemperature, !temp.isEmpty {
                StatBadge(title: "Temp", value: temp, icon: "thermometer.medium")
            }

            Spacer()
        }
    }

    // MARK: - Ingredients Section

    @ViewBuilder
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ingredients")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                // Availability summary
                let missing = recipe.missingIngredients(from: inventory)
                if missing.isEmpty {
                    Label("All available", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Missing \(missing.count)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ForEach(recipe.ingredients) { ingredient in
                IngredientCheckRow(
                    ingredient: ingredient,
                    isAvailable: isIngredientAvailable(ingredient)
                )
            }
        }
    }

    private func isIngredientAvailable(_ ingredient: RecipeIngredient) -> Bool {
        inventory.contains { $0.normalizedName == ingredient.normalizedName }
    }

    @ViewBuilder
    private func notesSection(_ notes: String) -> some View {
        DisclosureGroup(isExpanded: $notesExpanded) {
            Text(notes)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Label("Chef's Notes", systemImage: "note.text")
                .font(.title3)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Steps Section

    @ViewBuilder
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.title3)
                .fontWeight(.semibold)

            let steps = recipe.orderedSteps
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.orange)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.instruction)
                            .font(.body)

                        if let duration = step.durationMinutes {
                            Label("\(duration) min", systemImage: "timer")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.orange)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Ingredient Check Row

struct IngredientCheckRow: View {
    let ingredient: RecipeIngredient
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isAvailable ? .green : .gray)

            Text(ingredient.displayText)
                .font(.body)
                .foregroundStyle(isAvailable ? .primary : .secondary)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Cooking Mode View

struct CookingModeView: View {
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe
    @State private var currentStepIndex = 0

    var body: some View {
        let steps = recipe.orderedSteps
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding()

                Spacer()

                if steps.isEmpty {
                    Text("No steps available.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    let safeIndex = min(currentStepIndex, steps.count - 1)

                    // Step number
                    Text("Step \(safeIndex + 1) of \(steps.count)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    // Step content
                    VStack(spacing: 16) {
                        Text(steps[safeIndex].instruction)
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        if let duration = steps[safeIndex].durationMinutes {
                            Label("\(duration) min", systemImage: "timer")
                                .font(.headline)
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer()

                    // Navigation buttons
                    HStack(spacing: 40) {
                        Button {
                            withAnimation {
                                if currentStepIndex > 0 {
                                    currentStepIndex -= 1
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(currentStepIndex > 0 ? .white : .white.opacity(0.3))
                        }
                        .disabled(currentStepIndex == 0)

                        Button {
                            withAnimation {
                                if currentStepIndex < steps.count - 1 {
                                    currentStepIndex += 1
                                } else {
                                    dismiss()
                                }
                            }
                        } label: {
                            Image(systemName: currentStepIndex < steps.count - 1 ? "chevron.right.circle.fill" : "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.bottom, 50)

                    // Progress dots
                    HStack(spacing: 8) {
                        ForEach(0..<steps.count, id: \.self) { index in
                            Circle()
                                .fill(index <= currentStepIndex ? Color.orange : Color.white.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
        }
    }
}

#Preview {
    RecipeDetailView(
        recipe: Recipe(
            name: "Pasta Carbonara",
            description: "Classic Italian pasta dish",
            ingredients: [
                RecipeIngredient(name: "Spaghetti", quantity: 400, unit: .grams),
                RecipeIngredient(name: "Eggs", quantity: 4, unit: .piece),
                RecipeIngredient(name: "Pancetta", quantity: 200, unit: .grams)
            ],
            steps: [
                RecipeStep(instruction: "Bring a large pot of salted water to boil", orderIndex: 0),
                RecipeStep(instruction: "Cook pasta according to package directions", durationMinutes: 10, orderIndex: 1),
                RecipeStep(instruction: "Meanwhile, cook pancetta until crispy", durationMinutes: 5, orderIndex: 2)
            ],
            prepTime: 10,
            cookTime: 20,
            servings: 4,
            tags: ["italian", "pasta", "quick"],
            difficulty: .easy
        )
    )
    .modelContainer(for: [Recipe.self, Ingredient.self, RecipeIngredient.self, RecipeStep.self], inMemory: true)
}
