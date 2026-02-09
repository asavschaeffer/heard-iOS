import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.heardchef", category: "App")

@main
struct HeardChefApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Ingredient.self,
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            ChatThread.self,
            ChatMessage.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            logger.error("Failed to create ModelContainer: \(error.localizedDescription)")
            // Return in-memory container as fallback
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallbackConfig])
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .modelContainer(sharedModelContainer)
    }
}
