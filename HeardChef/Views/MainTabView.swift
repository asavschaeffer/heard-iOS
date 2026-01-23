import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label("Heard", systemImage: "waveform.circle.fill")
                }
                .tag(0)

            InventoryView()
                .tabItem {
                    Label("Inventory", systemImage: "refrigerator.fill")
                }
                .tag(1)

            RecipesView()
                .tabItem {
                    Label("Recipes", systemImage: "book.fill")
                }
                .tag(2)
            
            SettingsView(settings: ChatSettings())
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(.orange)
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [Ingredient.self, Recipe.self], inMemory: true)
}
