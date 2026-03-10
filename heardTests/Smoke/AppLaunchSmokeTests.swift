import XCTest
@testable import heard

final class AppLaunchSmokeTests: XCTestCase {
    func testXCTestDetectionIsEnabled() {
        XCTAssertTrue(TestSupport.isRunningTests)
    }

    func testAppCreatesSharedModelContainerInTestMode() {
        let app = HeardChefApp()
        _ = app.sharedModelContainer
    }
}
