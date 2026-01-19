import SwiftUI
import SwiftData

struct AddInventoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var quantity: Double = 1.0
    @State private var unit = "count"
    @State private var category: IngredientCategory = .other
    @State private var location: StorageLocation = .pantry
    @State private var hasExpiry = false
    @State private var expiryDate = Date()
    @State private var notes = ""

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Ingredient name", text: $name)
                        .focused($isNameFocused)

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
                    Toggle("Has Expiry Date", isOn: $hasExpiry.animation())

                    if hasExpiry {
                        DatePicker("Expiry Date", selection: $expiryDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    quickAddButtons
                }
            }
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addIngredient()
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

    // MARK: - Quick Add Buttons

    @ViewBuilder
    private var quickAddButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(quickAddItems, id: \.name) { item in
                    Button {
                        applyQuickAdd(item)
                    } label: {
                        Text(item.name)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quickAddItems: [(name: String, category: IngredientCategory, location: StorageLocation)] {
        [
            ("Eggs", .dairy, .fridge),
            ("Milk", .dairy, .fridge),
            ("Butter", .dairy, .fridge),
            ("Chicken", .meat, .fridge),
            ("Rice", .pantry, .pantry),
            ("Pasta", .pantry, .pantry),
            ("Olive Oil", .condiments, .pantry),
            ("Onions", .produce, .counter),
            ("Garlic", .produce, .counter),
            ("Salt", .condiments, .pantry)
        ]
    }

    private func applyQuickAdd(_ item: (name: String, category: IngredientCategory, location: StorageLocation)) {
        name = item.name
        category = item.category
        location = item.location
    }

    // MARK: - Actions

    private func addIngredient() {
        let ingredient = Ingredient(
            name: name,
            quantity: quantity,
            unit: unit,
            category: category,
            location: location,
            expiryDate: hasExpiry ? expiryDate : nil,
            notes: notes.isEmpty ? nil : notes
        )

        modelContext.insert(ingredient)
        dismiss()
    }
}

// MARK: - Bulk Add View

struct BulkAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var items: [PendingItem] = []

    struct PendingItem: Identifiable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: String
        var category: IngredientCategory
        var location: StorageLocation
        var isSelected: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach($items) { $item in
                    HStack {
                        Toggle(isOn: $item.isSelected) {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .fontWeight(.medium)
                                Text("\(item.quantity, specifier: "%.1f") \(item.unit)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkmark)
                    }
                }
            }
            .navigationTitle("Add Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Selected") {
                        addSelectedItems()
                    }
                    .fontWeight(.semibold)
                    .disabled(items.filter(\.isSelected).isEmpty)
                }
            }
        }
    }

    private func addSelectedItems() {
        for item in items where item.isSelected {
            let ingredient = Ingredient(
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                category: item.category,
                location: item.location
            )
            modelContext.insert(ingredient)
        }
        dismiss()
    }
}

// MARK: - Checkmark Toggle Style

struct CheckmarkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(configuration.isOn ? Color.orange : Color.gray)
                    .font(.title2)
            }
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == CheckmarkToggleStyle {
    static var checkmark: CheckmarkToggleStyle { CheckmarkToggleStyle() }
}

#Preview {
    AddInventoryView()
        .modelContainer(for: [Ingredient.self], inMemory: true)
}
