import SwiftUI
import SwiftData

struct RecipeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let recipe: Recipe?

    @State private var name = ""
    @State private var description = ""
    @State private var notes = ""
    @State private var cookingTemperature = ""
    @State private var ingredients: [RecipeIngredient] = []
    @State private var steps: [RecipeStep] = []
    @State private var prepTime: Int?
    @State private var cookTime: Int?
    @State private var servings: Int?
    @State private var tags: [String] = []
    @State private var tagInput = ""
    @State private var difficulty: RecipeDifficulty = .medium

    @State private var showingAddIngredient = false
    @State private var showingDeleteConfirmation = false
    @FocusState private var isNameFocused: Bool

    private var isEditing: Bool { recipe != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var validSteps: [RecipeStep] {
        steps.filter { !$0.instruction.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                basicInfoSection

                // Timing
                timingSection

                // Ingredients
                ingredientsSection

                // Steps
                stepsSection

                // Tags
                tagsSection

                // Delete button (only for existing recipes)
                if isEditing {
                    Section {
                        Button("Delete Recipe", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .accessibilityIdentifier("recipe.edit.deleteButton")
                    }
                }
            }
            .accessibilityIdentifier(isEditing ? "recipe.edit.form" : "recipe.add.form")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Recipe" : "New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier(isEditing ? "recipe.edit.cancelButton" : "recipe.add.cancelButton")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Create") {
                        saveRecipe()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmedName.isEmpty || ingredients.isEmpty || validSteps.isEmpty)
                    .accessibilityIdentifier(isEditing ? "recipe.edit.saveButton" : "recipe.add.saveButton")
                }
            }
            .sheet(isPresented: $showingAddIngredient) {
                AddRecipeIngredientView { ingredient in
                    ingredients.append(ingredient)
                }
            }
            .alert("Delete Recipe?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let recipe = recipe {
                        modelContext.delete(recipe)
                    }
                    dismiss()
                }
                .accessibilityIdentifier("recipe.edit.confirmDeleteButton")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("recipe.edit.cancelDeleteButton")
            } message: {
                Text("This action cannot be undone.")
            }
            .onAppear {
                loadRecipeData()
            }
        }
    }

    // MARK: - Basic Info Section

    @ViewBuilder
    private var basicInfoSection: some View {
        Section("Details") {
            TextField("Recipe name", text: $name)
                .focused($isNameFocused)
                .accessibilityIdentifier(isEditing ? "recipe.edit.nameField" : "recipe.add.nameField")

            UITestFocusProbe(
                identifier: isEditing ? "recipe.edit.nameField.focusState" : "recipe.add.nameField.focusState",
                isFocused: isNameFocused
            )

            TextField("Description (optional)", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityIdentifier(isEditing ? "recipe.edit.descriptionField" : "recipe.add.descriptionField")

            VStack(alignment: .leading, spacing: 8) {
                Text("Chef's Notes (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add variations, tips, wine pairings...")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }

                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
        }
    }

    // MARK: - Timing Section

    @ViewBuilder
    private var timingSection: some View {
        Section("Timing & Difficulty") {
            HStack {
                Text("Prep Time")
                Spacer()
                TextField("min", value: $prepTime, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("min")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Cook Time")
                Spacer()
                TextField("min", value: $cookTime, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("min")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Cooking Temp")
                Spacer()
                TextField("e.g. 350F", text: $cookingTemperature)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 140)
            }

            HStack {
                Text("Servings")
                Spacer()
                TextField("", value: $servings, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
            }

            Picker("Difficulty", selection: $difficulty) {
                ForEach(RecipeDifficulty.allCases, id: \.self) { level in
                    Label(level.displayName, systemImage: level.icon).tag(level)
                }
            }
        }
    }

    // MARK: - Ingredients Section

    @ViewBuilder
    private var ingredientsSection: some View {
        Section {
            ForEach(ingredients) { ingredient in
                Text(ingredient.displayText)
            }
            .onDelete { indexSet in
                ingredients.remove(atOffsets: indexSet)
            }
            .onMove { from, to in
                ingredients.move(fromOffsets: from, toOffset: to)
            }

            Button {
                showingAddIngredient = true
            } label: {
                Label("Add Ingredient", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Ingredients")
                Spacer()
                EditButton()
                    .font(.caption)
            }
        }
    }

    // MARK: - Steps Section

    @ViewBuilder
    private var stepsSection: some View {
        Section {
            ForEach(steps) { step in
                @Bindable var step = step

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text("\(step.orderIndex + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        TextField("Step \(step.orderIndex + 1)", text: $step.instruction, axis: .vertical)
                        .lineLimit(1...5)
                    }

                    HStack {
                        Text("Timer (optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("min", value: $step.durationMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                }
            }
            .onDelete { indexSet in
                steps.remove(atOffsets: indexSet)
                reindexSteps()
            }
            .onMove { from, to in
                steps.move(fromOffsets: from, toOffset: to)
                reindexSteps()
            }

            Button {
                steps.append(RecipeStep(instruction: "", orderIndex: steps.count))
            } label: {
                Label("Add Step", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Instructions")
                Spacer()
                EditButton()
                    .font(.caption)
            }
        }
    }

    private func reindexSteps() {
        for i in 0..<steps.count {
            steps[i].orderIndex = i
        }
    }

    // MARK: - Tags Section

    @ViewBuilder
    private var tagsSection: some View {
        Section("Tags") {
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(tag: tag) {
                        tags.removeAll { $0 == tag }
                    }
                }

                // Quick add common tags
                ForEach(suggestedTags, id: \.self) { tag in
                    if !tags.contains(tag) {
                        Button {
                            tags.append(tag)
                        } label: {
                            Text("+ \(tag)")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.gray.opacity(0.15))
                                .foregroundStyle(.secondary)
                                .clipShape(.rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("Add tag", text: $tagInput)
                    .textInputAutocapitalization(.never)

                Button {
                    addTag()
                } label: {
                    Text("Add")
                }
                .disabled(tagInput.isEmpty)
            }
        }
    }

    private var suggestedTags: [String] {
        ["Quick", "Vegetarian", "Vegan", "Gluten-Free", "Dairy-Free", "Healthy", "Comfort Food", "Italian", "Asian", "Mexican"]
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
            tagInput = ""
        }
    }

    // MARK: - Data Loading

    private func loadRecipeData() {
        guard let recipe = recipe else { return }

        name = recipe.name
        description = recipe.descriptionText ?? ""
        notes = recipe.notes ?? ""
        cookingTemperature = recipe.cookingTemperature ?? ""
        ingredients = recipe.ingredients
        steps = recipe.steps
        prepTime = recipe.prepTime
        cookTime = recipe.cookTime
        servings = recipe.servings
        tags = recipe.tags
        difficulty = recipe.difficulty
    }

    // MARK: - Save

    private func saveRecipe() {
        // Filter out empty steps and reindex
        let filteredSteps = validSteps
        for i in 0..<filteredSteps.count {
            filteredSteps[i].orderIndex = i
        }

        guard !trimmedName.isEmpty, !ingredients.isEmpty, !filteredSteps.isEmpty else { return }

        if let recipe = recipe {
            // Update existing
            recipe.name = trimmedName
            recipe.normalizedName = Recipe.normalize(trimmedName)
            recipe.descriptionText = description.isEmpty ? nil : description
            recipe.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : notes.trimmingCharacters(in: .whitespacesAndNewlines)
            recipe.cookingTemperature = cookingTemperature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : cookingTemperature.trimmingCharacters(in: .whitespacesAndNewlines)
            recipe.ingredients = ingredients
            recipe.steps = filteredSteps
            recipe.prepTime = prepTime
            recipe.cookTime = cookTime
            recipe.servings = servings
            recipe.tags = tags.map { $0.lowercased() }
            recipe.difficulty = difficulty
            recipe.updatedAt = Date()
        } else {
            // Create new
            let newRecipe = Recipe(
                name: trimmedName,
                description: description.isEmpty ? nil : description,
                notes: notes,
                cookingTemperature: cookingTemperature,
                ingredients: ingredients,
                steps: filteredSteps,
                prepTime: prepTime,
                cookTime: cookTime,
                servings: servings,
                tags: tags,
                difficulty: difficulty,
                source: .userCreated
            )
            modelContext.insert(newRecipe)
        }

        dismiss()
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.15))
        .foregroundStyle(.orange)
        .clipShape(.rect(cornerRadius: 6))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing

                self.size.width = max(self.size.width, x)
            }

            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Add Recipe Ingredient View

struct AddRecipeIngredientView: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (RecipeIngredient) -> Void

    @State private var name = ""
    @State private var quantity: Double?
    @State private var unit: Unit? = nil
    @State private var preparation = ""

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ingredient name", text: $name)
                        .focused($isNameFocused)
                }

                Section("Amount (Optional)") {
                    HStack {
                        TextField("Qty", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)

                        Picker("Unit", selection: $unit) {
                            Text("None").tag(Unit?.none)
                            ForEach(Unit.allCases, id: \.self) { u in
                                Text(u.displayName).tag(Unit?.some(u))
                            }
                        }
                    }
                }

                Section("Preparation (Optional)") {
                    TextField("e.g., diced, room temperature", text: $preparation)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let ingredient = RecipeIngredient(
                            name: name,
                            quantity: quantity,
                            unit: unit,
                            preparation: preparation.isEmpty ? nil : preparation
                        )
                        onAdd(ingredient)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
    }
}

#Preview {
    RecipeEditView(recipe: nil)
        .modelContainer(for: [Recipe.self], inMemory: true)
}
