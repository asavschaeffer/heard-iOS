import XCTest

class HeardUITestCase: XCTestCase {
    class var existenceTimeout: TimeInterval { 2 }
    class var disappearanceTimeout: TimeInterval { 4 }
    class var focusTransitionTimeout: TimeInterval { 4 }

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
    func waitForExistence(
        of identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let resolvedTimeout = timeout ?? Self.existenceTimeout
        let deadline = Date().addingTimeInterval(resolvedTimeout)
        var resolvedElement = element(identifier, in: app)

        repeat {
            resolvedElement = element(identifier, in: app)
            if resolvedElement.exists {
                return resolvedElement
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTAssertTrue(
            resolvedElement.exists,
            "Expected element \(identifier) to appear.",
            file: file,
            line: line
        )
        return resolvedElement
    }

    @discardableResult
    func waitForNonExistence(
        of element: XCUIElement,
        timeout: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let resolvedTimeout = timeout ?? Self.disappearanceTimeout
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: resolvedTimeout)
        let didDisappear = result == .completed
        XCTAssertTrue(didDisappear, "Expected element to disappear.", file: file, line: line)
        return didDisappear
    }

    @discardableResult
    func waitForNonExistence(
        of identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let resolvedTimeout = timeout ?? Self.disappearanceTimeout
        let deadline = Date().addingTimeInterval(resolvedTimeout)
        var resolvedElement = element(identifier, in: app)

        repeat {
            resolvedElement = element(identifier, in: app)
            if resolvedElement.exists == false {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        attachDebugDescription(for: resolvedElement, named: identifier)
        XCTAssertTrue(
            resolvedElement.exists == false,
            "Expected element \(identifier) to disappear.",
            file: file,
            line: line
        )
        return false
    }

    @discardableResult
    func waitForTransition(
        from disappearingIdentifier: String,
        to appearingIdentifier: String,
        in app: XCUIApplication,
        disappearanceTimeout: TimeInterval? = nil,
        appearanceTimeout: TimeInterval? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let didDisappear = waitForNonExistence(
            of: disappearingIdentifier,
            in: app,
            timeout: disappearanceTimeout,
            file: file,
            line: line
        )
        guard didDisappear else { return false }

        let appearedElement = waitForExistence(
            of: appearingIdentifier,
            in: app,
            timeout: appearanceTimeout,
            file: file,
            line: line
        )
        return appearedElement.exists
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

        XCTAssertTrue(searchField.waitForExistence(timeout: Self.existenceTimeout))
        return searchField
    }

    private func attachDebugDescription(for element: XCUIElement, named identifier: String) {
        guard element.exists else { return }

        let attachment = XCTAttachment(string: element.debugDescription)
        attachment.name = "Debug description for \(identifier)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
