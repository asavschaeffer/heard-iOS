import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigationState: AppNavigationState
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingCameraCapture = false
    @State private var attachmentErrorMessage: String?
    @State private var groupBy: GroupBy = .location
    @State private var selectedIngredient: Ingredient?

    enum GroupBy: String, CaseIterable {
        case location = "Location"
        case category = "Category"
    }

    var body: some View {
        NavigationStack {
            List {
                scanWithChefSection

                if filteredIngredients.isEmpty {
                    emptyStateView
                } else {
                    groupedSections
                }
            }
            .accessibilityIdentifier("inventory.list")
            .searchable(text: $searchText, prompt: "Search ingredients")
            .navigationTitle("Inventory")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Group By", selection: $groupBy) {
                            ForEach(GroupBy.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        openInventoryCamera()
                    } label: {
                        Image(systemName: "camera")
                    }
                    .accessibilityIdentifier("inventory.cameraButton")

                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("inventory.addButton")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddInventoryView()
            }
            .sheet(isPresented: $showingCameraCapture) {
                inventoryCameraCaptureView
            }
            .sheet(item: $selectedIngredient) { ingredient in
                InventoryDetailView(ingredient: ingredient)
            }
            .alert("Attachment Error", isPresented: attachmentErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(attachmentErrorMessage ?? "Unable to prepare attachment.")
            }
        }
    }

    private var attachmentErrorPresented: Binding<Bool> {
        Binding(
            get: { attachmentErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    attachmentErrorMessage = nil
                }
            }
        )
    }

    // MARK: - Filtered Ingredients

    private var filteredIngredients: [Ingredient] {
        if searchText.isEmpty {
            return ingredients
        }
        return ingredients.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Grouped Sections

    @ViewBuilder
    private var groupedSections: some View {
        switch groupBy {
        case .location:
            ForEach(StorageLocation.allCases, id: \.self) { location in
                let items = filteredIngredients.filter { $0.location == location }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { ingredient in
                            Button {
                                selectedIngredient = ingredient
                            } label: {
                                IngredientRow(ingredient: ingredient)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("inventory.row.\(UITestSupport.identifierSlug(ingredient.name))")
                            .accessibilityLabel("Open \(ingredient.name)")
                            .accessibilityHint("Shows ingredient details")
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteIngredient(ingredient)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Label(location.displayName, systemImage: location.icon)
                    }
                }
            }

        case .category:
            ForEach(IngredientCategory.allCases, id: \.self) { category in
                let items = filteredIngredients.filter { $0.category == category }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { ingredient in
                            Button {
                                selectedIngredient = ingredient
                            } label: {
                                IngredientRow(ingredient: ingredient)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("inventory.row.\(UITestSupport.identifierSlug(ingredient.name))")
                            .accessibilityLabel("Open \(ingredient.name)")
                            .accessibilityHint("Shows ingredient details")
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteIngredient(ingredient)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Label(category.displayName, systemImage: category.icon)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Ingredients", systemImage: "refrigerator")
        } description: {
            Text("Add ingredients to your inventory to get started.")
        } actions: {
            Button("Add Ingredient") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button("Add From Photo") {
                openInventoryCamera()
            }
            .buttonStyle(.bordered)
        }
    }

    private var scanWithChefSection: some View {
        Section {
            Button(action: openInventoryCamera) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 40, height: 40)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add From Photo")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Snap a picture, then Chef adds those ingredients in chat.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("inventory.scanWithChatButton")
        }
    }

    // MARK: - Actions

    private func deleteIngredient(_ ingredient: Ingredient) {
        modelContext.delete(ingredient)
    }

    private var inventoryCameraCaptureView: some View {
        CameraCaptureFlowView(
            allowVideo: false,
            onPick: handleInventoryCapture,
            onError: { attachmentErrorMessage = $0 }
        )
    }

    private func openInventoryCamera() {
        showingCameraCapture = true
    }

    private func handleInventoryCapture(_ image: UIImage?, _ videoURL: URL?) {
        if let image {
            showingCameraCapture = false
            routeAcceptedAttachmentToChat(ChatAttachmentService.loadFromCameraImage(image))
        } else {
            showingCameraCapture = false
        }
    }

    private func routeAcceptedAttachmentToChat(_ attachment: ChatAttachment) {
        navigationState.openChatSubmission(
            from: .inventory,
            draftText: "Add these ingredients to my inventory.",
            attachment: attachment,
            shouldAutoSend: true
        )
    }
}

// MARK: - Ingredient Row

struct IngredientRow: View {
    let ingredient: Ingredient

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(ingredient.displayQuantity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let expiry = ingredient.expiryDate {
                        ExpiryBadge(date: expiry, isExpired: ingredient.isExpired, isExpiringSoon: ingredient.isExpiringSoon)
                    }
                }
            }

            Spacer()

            Image(systemName: ingredient.category.icon)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Expiry Badge

struct ExpiryBadge: View {
    let date: Date
    let isExpired: Bool
    let isExpiringSoon: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "clock")
                .font(.caption2)

            Text(formattedDate)
                .font(.caption)
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.15), in: Capsule())
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private var badgeColor: Color {
        if isExpired {
            return .red
        } else if isExpiringSoon {
            return .orange
        }
        return .green
    }
}

// MARK: - Inventory Detail View

struct InventoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var ingredient: Ingredient

    @State private var name: String = ""
    @State private var quantity: Double = 1.0
    @State private var unit: Unit = .piece
    @State private var category: IngredientCategory = .other
    @State private var location: StorageLocation = .pantry
    @State private var expiryDate: Date = Date()
    @State private var hasExpiry: Bool = false
    @State private var notes: String = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)
                        .accessibilityIdentifier("inventory.edit.nameField")

                    UITestFocusProbe(
                        identifier: "inventory.edit.nameField.focusState",
                        isFocused: isNameFocused
                    )

                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("Qty", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Picker("Unit", selection: $unit) {
                        ForEach(Unit.allCases, id: \.self) { u in
                            Text(u.displayName).tag(u)
                        }
                    }
                }

                Section("Organization") {
                    Picker("Category", selection: $category) {
                        ForEach(IngredientCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.icon).tag(cat)
                        }
                    }

                    Picker("Location", selection: $location) {
                        ForEach(StorageLocation.allCases, id: \.self) { loc in
                            Label(loc.displayName, systemImage: loc.icon).tag(loc)
                        }
                    }
                }

                Section("Expiry") {
                    Toggle("Has Expiry Date", isOn: $hasExpiry)

                    if hasExpiry {
                        DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Delete Ingredient", role: .destructive) {
                        modelContext.delete(ingredient)
                        dismiss()
                    }
                    .accessibilityIdentifier("inventory.edit.deleteButton")
                }
            }
            .accessibilityIdentifier("inventory.edit.form")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("inventory.edit.cancelButton")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                    .accessibilityIdentifier("inventory.edit.saveButton")
                }
            }
            .onAppear {
                loadIngredientData()
                isNameFocused = true
            }
        }
    }

    private func loadIngredientData() {
        name = ingredient.name
        quantity = ingredient.quantity
        unit = ingredient.unit
        category = ingredient.category
        location = ingredient.location
        hasExpiry = ingredient.expiryDate != nil
        expiryDate = ingredient.expiryDate ?? Date()
        notes = ingredient.notes ?? ""
    }

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let params = IngredientUpdateParams(
            name: trimmedName,
            quantity: max(0, quantity),
            unit: unit.rawValue,
            category: category.rawValue,
            location: location.rawValue,
            expiryDate: hasExpiry ? expiryDate : nil,
            notes: notes
        )

        ingredient.update(with: params)
        if !hasExpiry {
            ingredient.expiryDate = nil
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && quantity > 0
    }
}

#Preview {
    InventoryView()
        .environmentObject(AppNavigationState())
        .modelContainer(for: [Ingredient.self, Recipe.self], inMemory: true)
}
