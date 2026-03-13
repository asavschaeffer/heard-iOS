import SwiftData
import Testing
@testable import heard

@Suite(.tags(.hosted, .smoke))
@MainActor
struct AppLaunchSmokeTests {
    @Test
    func hostedHarnessDetectsTestExecution() {
        #expect(TestSupport.isRunningTests)
        #expect(TestSupport.shouldUseInMemoryModelContainer)
        #expect(TestSupport.shouldRenderTestHarnessOnly)
        #expect(TestSupport.shouldSkipWarmup)
    }

    @Test
    func appCreatesSharedModelContainerInTestMode() {
        let app = HeardChefApp()
        let container = app.sharedModelContainer

        _ = container.mainContext
        #expect(TestSupport.shouldUseInMemoryModelContainer)
    }
}
