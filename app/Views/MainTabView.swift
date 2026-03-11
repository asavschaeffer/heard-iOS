import SwiftUI
import SwiftData

struct MainTabView: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            ChatView()
                .tabItem {
                    Label("Heard", systemImage: "waveform.circle.fill")
                }
                .tag(AppNavigationState.Tab.chat)

            InventoryView()
                .tabItem {
                    Label("Inventory", systemImage: "refrigerator.fill")
                }
                .tag(AppNavigationState.Tab.inventory)

            RecipesView()
                .tabItem {
                    Label("Recipes", systemImage: "book.fill")
                }
                .tag(AppNavigationState.Tab.recipes)
            
            SettingsView(settings: ChatSettings())
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(AppNavigationState.Tab.settings)
        }
        .tint(.orange)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppNavigationState())
        .modelContainer(for: [Ingredient.self, Recipe.self], inMemory: true)
}
