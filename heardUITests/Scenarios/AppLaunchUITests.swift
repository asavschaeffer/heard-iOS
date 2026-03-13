import XCTest

final class AppLaunchUITests: HeardUITestCase {
    func testWarmupOverlayDismissesAfterLaunch() {
        let app = UIHarness.launchApp(scenario: .editorFlows, skipWarmup: false)

        let inventoryTab = app.tabBars.buttons["Inventory"]
        XCTAssertTrue(inventoryTab.waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(waitForNonExistence(of: "launch.overlay", in: app, timeout: 5))

        inventoryTab.tap()
        XCTAssertTrue(inventoryTab.isHittable)
        XCTAssertTrue(inventoryTab.isSelected)
    }
}
