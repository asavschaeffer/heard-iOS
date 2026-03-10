import XCTest

enum UIHarness {
    static let keyboardDismissScenario = "keyboard_dismiss"

    static func launchApp(
        scenario: String = keyboardDismissScenario,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["UITEST_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), file: file, line: line)
        return app
    }
}
