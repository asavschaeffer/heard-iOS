import XCTest

final class ChatAttachmentContextMenuUITests: HeardUITestCase {
    func testLongPressOnImageAttachmentShowsReactionsAndActions() {
        let app = launchChatAttachmentsScenario()
        assertContextMenu(for: "chat.message.attachment.image", in: app)
    }

    func testLongPressOnVideoAttachmentShowsReactionsAndActions() {
        let app = launchChatAttachmentsScenario()
        assertContextMenu(for: "chat.message.attachment.video", in: app)
    }

    private func launchChatAttachmentsScenario() -> XCUIApplication {
        let app = UIHarness.launchApp(scenario: .attachmentsBasic)
        app.tabBars.buttons["Chat"].tap()
        return app
    }

    private func assertContextMenu(for identifier: String, in app: XCUIApplication) {
        let attachment = waitForExistence(of: identifier, in: app)
        attachment.press(forDuration: 1.2)

        XCTAssertTrue(app.buttons["👍"].waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: Self.existenceTimeout))
        XCTAssertTrue(app.buttons["Share…"].waitForExistence(timeout: Self.existenceTimeout))
    }
}
