import SwiftUI
import SwiftData
import OSLog
import FirebaseCore

private let logger = Logger(subsystem: "com.heardchef", category: "App")

@main
struct HeardChefApp: App {
    @StateObject private var warmup = AppWarmup()
    @StateObject private var navigationState = AppNavigationState()
    @State private var showsLaunchOverlay = true

    init() {
        FirebaseApp.configure()
    }

    private var uiTestColorSchemeOverride: ColorScheme? {
        guard TestSupport.isRunningUITests else { return nil }

        switch ProcessInfo.processInfo.environment["HEARD_UI_STYLE"]?.lowercased() {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Ingredient.self,
            Recipe.self,
            RecipeIngredient.self,
            RecipeStep.self,
            ChatThread.self,
            ChatMessage.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: TestSupport.shouldUseInMemoryModelContainer
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            UITestSupport.configure(container: container)
            return container
        } catch {
            logger.error("Failed to create ModelContainer: \(error.localizedDescription)")
            // Return in-memory container as fallback
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try! ModelContainer(for: schema, configurations: [fallbackConfig])
            UITestSupport.configure(container: container)
            return container
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if TestSupport.shouldRenderTestHarnessOnly {
                    Color.clear
                } else if TestSupport.shouldSkipWarmup {
                    MainTabView()
                        .environmentObject(navigationState)
                        .environmentObject(warmup)
                } else {
                    ZStack {
                        if warmup.isFinished {
                            MainTabView()
                                .environmentObject(navigationState)
                        }

                        if showsLaunchOverlay {
                            LaunchLoadingView {
                                showsLaunchOverlay = false
                            }
                        }
                    }
                    .task {
                        warmup.runAll()
                        FirestoreSync.shared.startListening(
                            modelContext: sharedModelContainer.mainContext
                        )
                    }
                    .environmentObject(navigationState)
                    .environmentObject(warmup)
                }
            }
            .preferredColorScheme(uiTestColorSchemeOverride)
        }
        .modelContainer(sharedModelContainer)
    }
}
