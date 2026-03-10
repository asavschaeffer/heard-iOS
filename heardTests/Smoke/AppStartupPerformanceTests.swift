import XCTest
@testable import heard

@MainActor
final class AppStartupPerformanceTests: XCTestCase {
    func testSharedModelContainerCreationPerformance() {
        _ = HeardChefApp().sharedModelContainer

        let options = XCTMeasureOptions()
        options.iterationCount = 10
        options.invocationOptions = [.manuallyStart, .manuallyStop]

        measure(metrics: [XCTClockMetric()], options: options) {
            startMeasuring()
            let app = HeardChefApp()
            _ = app.sharedModelContainer
            stopMeasuring()
        }
    }
}
