import XCTest

final class AppearanceUITests: HeardUITestCase {
    func testChatAttachmentsRenderInLightAndDarkMode() {
        for interfaceStyle in [UIHarness.InterfaceStyle.light, .dark] {
            let app = UIHarness.launchApp(
                scenario: .attachmentsBasic,
                interfaceStyle: interfaceStyle
            )

            app.tabBars.buttons["Chat"].tap()
            XCTAssertTrue(
                waitForExistence(of: "chat.message.attachment.image", in: app).exists,
                "Expected chat attachment to render in \(interfaceStyle.rawValue) mode."
            )

            app.terminate()
        }
    }
}
