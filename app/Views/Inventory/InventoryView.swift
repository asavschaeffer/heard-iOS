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
    @State private var persistenceErrorMessage: String?
    @State private var groupBy: GroupBy = .location
    @State private var selectedIngredient: Ingredient?

    enum GroupBy: String, CaseIterable {
        case location = "Location"
        case category = "Category"
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredIngredients.isEmpty {
                    ScrollView {
                        emptyStateView
                            .padding()
                    }
                } else {
                    List {
                        groupedSections
                    }
                }
            }
            .accessibilityIdentifier("inventory.list")
            .searchable(text: $searchText, prompt: "Search ingredients")
            .navigationTitle("Inventory")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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

                ToolbarItemGroup(placement: .topBarTrailing) {
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
            .alert("Save Error", isPresented: persistenceErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(persistenceErrorMessage ?? "Unable to save your changes.")
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

    private var persistenceErrorPresented: Binding<Bool> {
        Binding(
            get: { persistenceErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    persistenceErrorMessage = nil
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
        VStack(spacing: 24) {
            Image(systemName: "refrigerator")
                .font(.system(size: 70))
                .foregroundStyle(.secondary)

            Text("No Ingredients")
                .font(.title)
                .fontWeight(.semibold)

            Text("Scan a receipt or grocery haul to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                Button { openInventoryCamera() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48))
                        Text("Scan")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    navigationState.requestCall()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 48))
                        Text("Talk")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                }

                Button { showingAddSheet = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .font(.system(size: 48))
                        Text("Add manually")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.orange)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func deleteIngredient(_ ingredient: Ingredient) {
        modelContext.delete(ingredient)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            persistenceErrorMessage = error.localizedDescription
        }
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
    @State private var persistenceErrorMessage: String?
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
                        deleteIngredient()
                    }
                    .accessibilityIdentifier("inventory.edit.deleteButton")
                }
            }
            .accessibilityIdentifier("inventory.edit.form")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Save Error", isPresented: persistenceErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(persistenceErrorMessage ?? "Unable to save your changes.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("inventory.edit.cancelButton")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if saveChanges() {
                            dismiss()
                        }
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

    private var persistenceErrorPresented: Binding<Bool> {
        Binding(
            get: { persistenceErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    persistenceErrorMessage = nil
                }
            }
        )
    }

    private func saveChanges() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }

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

        return persistChanges()
    }

    private func deleteIngredient() {
        modelContext.delete(ingredient)
        if persistChanges() {
            dismiss()
        }
    }

    private func persistChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            persistenceErrorMessage = error.localizedDescription
            return false
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
