import Foundation

enum TestSupport {
    private static let environment = ProcessInfo.processInfo.environment

    static let isRunningUnitTests: Bool = {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestBundlePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        if ProcessInfo.processInfo.arguments.contains("-XCTest") { return true }
        return NSClassFromString("XCTestCase") != nil
    }()

    static let isRunningUITests = ProcessInfo.processInfo.arguments.contains("-ui-testing")

    static let isRunningTests = isRunningUnitTests || isRunningUITests

    static let shouldRenderTestHarnessOnly = isRunningUnitTests

    static let shouldUseInMemoryModelContainer = isRunningTests

    static let shouldSkipWarmup: Bool = {
        if isRunningUnitTests {
            return true
        }

        if isRunningUITests {
            return environment["HEARD_SKIP_WARMUP"] != "0"
        }

        return false
    }()

    static let defaultTabIndex: Int = isRunningUITests ? 1 : 0
}
