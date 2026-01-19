import SwiftUI
import SwiftData

struct InventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ingredient.name) private var ingredients: [Ingredient]

    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingCamera = false
    @State private var groupBy: GroupBy = .location
    @State private var selectedIngredient: Ingredient?

    enum GroupBy: String, CaseIterable {
        case location = "Location"
        case category = "Category"
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredIngredients.isEmpty {
                    emptyStateView
                } else {
                    groupedSections
                }
            }
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
                        showingCamera = true
                    } label: {
                        Image(systemName: "camera")
                    }

                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddInventoryView()
            }
            .sheet(isPresented: $showingCamera) {
                CameraCaptureView()
            }
            .sheet(item: $selectedIngredient) { ingredient in
                InventoryDetailView(ingredient: ingredient)
            }
        }
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
                            IngredientRow(ingredient: ingredient)
                                .onTapGesture {
                                    selectedIngredient = ingredient
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteIngredient(ingredient)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Label(location.rawValue, systemImage: location.icon)
                    }
                }
            }

        case .category:
            ForEach(IngredientCategory.allCases, id: \.self) { category in
                let items = filteredIngredients.filter { $0.category == category }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { ingredient in
                            IngredientRow(ingredient: ingredient)
                                .onTapGesture {
                                    selectedIngredient = ingredient
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteIngredient(ingredient)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Label(category.rawValue, systemImage: category.icon)
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
        }
    }

    // MARK: - Actions

    private func deleteIngredient(_ ingredient: Ingredient) {
        modelContext.delete(ingredient)
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
    @State private var unit: String = "count"
    @State private var category: IngredientCategory = .other
    @State private var location: StorageLocation = .pantry
    @State private var expiryDate: Date = Date()
    @State private var hasExpiry: Bool = false
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)

                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("Qty", value: $quantity, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    Picker("Unit", selection: $unit) {
                        ForEach(Ingredient.commonUnits, id: \.self) { unit in
                            Text(unit).tag(unit)
                        }
                    }
                }

                Section("Organization") {
                    Picker("Category", selection: $category) {
                        ForEach(IngredientCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }

                    Picker("Location", selection: $location) {
                        ForEach(StorageLocation.allCases, id: \.self) { loc in
                            Label(loc.rawValue, systemImage: loc.icon).tag(loc)
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
                }
            }
            .navigationTitle("Edit Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadIngredientData()
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
        ingredient.name = name
        ingredient.quantity = quantity
        ingredient.unit = unit
        ingredient.category = category
        ingredient.location = location
        ingredient.expiryDate = hasExpiry ? expiryDate : nil
        ingredient.notes = notes.isEmpty ? nil : notes
        ingredient.updatedAt = Date()
    }
}

// MARK: - Camera Capture View (Placeholder)

struct CameraCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var captureMode: CaptureMode = .receipt

    enum CaptureMode: String, CaseIterable {
        case receipt = "Receipt"
        case groceries = "Groceries"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Mode", selection: $captureMode) {
                    ForEach(CaptureMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Spacer()

                // Camera preview placeholder
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.8))
                    .overlay {
                        VStack {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 60))
                                .foregroundStyle(.white.opacity(0.5))

                            Text("Camera Preview")
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.top)
                        }
                    }
                    .aspectRatio(3/4, contentMode: .fit)
                    .padding()

                Spacer()

                // Capture button
                Button {
                    // Capture and process image
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 70, height: 70)
                        .overlay {
                            Circle()
                                .stroke(Color.gray, lineWidth: 3)
                                .padding(4)
                        }
                }
                .padding(.bottom, 30)
            }
            .background(Color.black)
            .navigationTitle(captureMode == .receipt ? "Scan Receipt" : "Scan Groceries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

#Preview {
    InventoryView()
        .modelContainer(for: [Ingredient.self, Recipe.self], inMemory: true)
}
