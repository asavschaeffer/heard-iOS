import XCTest

enum UIHarness {
    enum Scenario: String {
        case editorFlows = "editor_flows"
        case keyboardDismiss = "keyboard_dismiss"
        case searchFiltering = "search_filtering"
        case emptyState = "empty_state"
        case attachmentsBasic = "attachments_basic"
    }

    enum InterfaceStyle: String, CaseIterable {
        case system
        case light
        case dark
    }

    static func launchApp(
        scenario: Scenario = .editorFlows,
        skipWarmup: Bool = true,
        interfaceStyle: InterfaceStyle = .system,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["UITEST_SCENARIO"] = scenario.rawValue
        app.launchEnvironment["HEARD_SKIP_WARMUP"] = skipWarmup ? "1" : "0"
        app.launchEnvironment["HEARD_UI_STYLE"] = interfaceStyle.rawValue
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), file: file, line: line)
        return app
    }
}
