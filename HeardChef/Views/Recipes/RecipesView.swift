import SwiftUI
import SwiftData

struct RecipesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query private var ingredients: [Ingredient]

    @State private var searchText = ""
    @State private var showingAddRecipe = false
    @State private var selectedRecipe: Recipe?
    @State private var showMakeableOnly = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if filteredRecipes.isEmpty {
                        emptyStateView
                    } else {
                        // "What Can I Make?" Section
                        if showMakeableOnly {
                            makeableRecipesSection
                        } else {
                            allRecipesSection
                        }
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search recipes")
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            showMakeableOnly.toggle()
                        }
                    } label: {
                        Label(
                            showMakeableOnly ? "Show All" : "Can Make",
                            systemImage: showMakeableOnly ? "list.bullet" : "checkmark.circle"
                        )
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddRecipe = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddRecipe) {
                RecipeEditView(recipe: nil)
            }
            .sheet(item: $selectedRecipe) { recipe in
                RecipeDetailView(recipe: recipe)
            }
        }
    }

    // MARK: - Filtered Recipes

    private var filteredRecipes: [Recipe] {
        var result = recipes

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.ingredients.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
        }

        if showMakeableOnly {
            result = result.filter { $0.canMake(with: ingredients) }
        }

        return result
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: showMakeableOnly ? "basket" : "book.closed")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(showMakeableOnly ? "No Recipes Available" : "No Recipes")
                .font(.title2)
                .fontWeight(.semibold)

            Text(showMakeableOnly
                 ? "Add more ingredients to your inventory or create new recipes."
                 : "Create your first recipe to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if !showMakeableOnly {
                Button("Add Recipe") {
                    showingAddRecipe = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(.vertical, 60)
    }

    // MARK: - Makeable Recipes Section

    @ViewBuilder
    private var makeableRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ready to Cook")
                    .font(.headline)
            }

            ForEach(filteredRecipes) { recipe in
                RecipeCard(recipe: recipe, inventory: ingredients)
                    .onTapGesture {
                        selectedRecipe = recipe
                    }
            }
        }
    }

    // MARK: - All Recipes Section

    @ViewBuilder
    private var allRecipesSection: some View {
        let makeable = filteredRecipes.filter { $0.canMake(with: ingredients) }
        let needIngredients = filteredRecipes.filter { !$0.canMake(with: ingredients) }

        if !makeable.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Ready to Cook")
                        .font(.headline)
                }

                ForEach(makeable) { recipe in
                    RecipeCard(recipe: recipe, inventory: ingredients)
                        .onTapGesture {
                            selectedRecipe = recipe
                        }
                }
            }
        }

        if !needIngredients.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "basket")
                        .foregroundStyle(.orange)
                    Text("Need Ingredients")
                        .font(.headline)
                }
                .padding(.top, makeable.isEmpty ? 0 : 20)

                ForEach(needIngredients) { recipe in
                    RecipeCard(recipe: recipe, inventory: ingredients)
                        .onTapGesture {
                            selectedRecipe = recipe
                        }
                }
            }
        }
    }
}

// MARK: - Recipe Card

struct RecipeCard: View {
    let recipe: Recipe
    let inventory: [Ingredient]

    private var canMake: Bool {
        recipe.canMake(with: inventory)
    }

    private var missingCount: Int {
        recipe.missingIngredients(from: inventory).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.headline)

                    if let description = recipe.descriptionText, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Stats row
            HStack(spacing: 16) {
                if let time = recipe.formattedTotalTime {
                    Label(time, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let servings = recipe.servings {
                    Label("\(servings) servings", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Availability indicator
                if canMake {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Missing \(missingCount)", systemImage: "basket")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Tags
            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 2)
    }
}

#Preview {
    RecipesView()
        .modelContainer(for: [Recipe.self, Ingredient.self], inMemory: true)
}
