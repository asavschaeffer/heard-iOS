import XCTest
@testable import heard

@MainActor
final class AppStartupPerformanceTests: XCTestCase {
    func testSharedModelContainerCreationPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            let app = HeardChefApp()
            _ = app.sharedModelContainer
        }
    }
}
