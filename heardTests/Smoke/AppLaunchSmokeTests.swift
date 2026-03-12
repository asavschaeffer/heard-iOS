import Testing
@testable import heard

@Suite(.tags(.hosted, .smoke))
@MainActor
struct AppLaunchSmokeTests {
    @Test
    func xCTestDetectionIsEnabled() {
        #expect(TestSupport.isRunningTests)
    }

    @Test
    func appCreatesSharedModelContainerInTestMode() {
        let app = HeardChefApp()
        _ = app.sharedModelContainer
    }
}
