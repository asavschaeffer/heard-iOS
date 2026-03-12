import XCTest

class HeardUITestCase: XCTestCase {
    private var didAttachFailureScreenshot = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        didAttachFailureScreenshot = false
    }

    override func record(_ issue: XCTIssue) {
        if didAttachFailureScreenshot == false {
            didAttachFailureScreenshot = true
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "\(name)-failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        super.record(issue)
    }

    func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func replaceText(in element: XCUIElement, with text: String) {
        element.tap()

        let currentValue = (element.value as? String) ?? ""
        if currentValue.isEmpty == false, currentValue != element.placeholderValue {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }

        element.typeText(text)
    }

    @discardableResult
    func waitForNonExistence(
        of element: XCUIElement,
        timeout: TimeInterval = 4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        let didDisappear = result == .completed
        XCTAssertTrue(didDisappear, "Expected element to disappear.", file: file, line: line)
        return didDisappear
    }

    func searchField(
        withPlaceholder placeholder: String,
        in container: XCUIElement,
        app: XCUIApplication
    ) -> XCUIElement {
        let searchField = app.searchFields[placeholder].firstMatch
        if searchField.exists == false {
            container.swipeDown()
        }

        XCTAssertTrue(searchField.waitForExistence(timeout: 2))
        return searchField
    }
}
