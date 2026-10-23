import XCTest

/// Captures the screenshots used in the README from the demo workspace. Skipped unless the
/// `MARC_SCREENSHOTS` environment variable is set; run `make screenshots` to capture them and
/// export them to docs/images.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureScreenshots() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MARC_SCREENSHOTS"] != nil,
            "Set MARC_SCREENSHOTS to capture the README screenshots.",
        )
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-demo-workspace"]
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        waitForPageLoad(in: app)
        capture(window, named: "marc-window")

        // Typed text avoids the letter "c"; see MarcUITests.testCreatingASpace.
        app.typeKey("t", modifierFlags: .command)
        let field = app.textFields["commandBarField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("swift")
        settle()
        capture(window, named: "command-bar")
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("2", modifierFlags: .control)
        let tab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'tabRow' AND label CONTAINS 'Swift.org'"))
            .firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()
        waitForPageLoad(in: app)
        capture(window, named: "light-space")
    }

    @MainActor
    private func waitForPageLoad(in app: XCUIApplication) {
        _ = app.buttons["Reload"].waitForExistence(timeout: 30)
        settle(seconds: 3)
    }

    private func settle(seconds: TimeInterval = 1) {
        let pause = expectation(description: "settle")
        pause.isInverted = true
        wait(for: [pause], timeout: seconds)
    }

    @MainActor
    private func capture(_ window: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "screenshot-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
