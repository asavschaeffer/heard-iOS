import Foundation

enum TestSupport {
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestBundlePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        if ProcessInfo.processInfo.arguments.contains("-XCTest") { return true }
        return NSClassFromString("XCTestCase") != nil
    }()
}
