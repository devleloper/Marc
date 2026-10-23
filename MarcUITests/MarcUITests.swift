import XCTest

/// End-to-end checks of the main browser flows. The app runs with `-ui-testing`, which uses
/// in-memory databases, skips onboarding and disables network-dependent features.
final class MarcUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    @MainActor
    func testLaunchShowsSidebarAndEmptyContent() {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["addressField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["newTabRow"].exists)
    }

    @MainActor
    func testCommandBarOpensATab() {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("t", modifierFlags: .command)
        let field = app.textFields["commandBarField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("about:blank\r")
        XCTAssertTrue(app.descendants(matching: .any)["tabRow"].waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists, "The Command Bar closes after opening a page")
    }

    @MainActor
    func testEscapeClosesCommandBar() {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("t", modifierFlags: .command)
        let field = app.textFields["commandBarField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testToggleSidebarHidesAndShowsIt() {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let address = app.descendants(matching: .any)["addressField"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(address.waitForNonExistence(timeout: 3))
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(address.waitForExistence(timeout: 3))
    }

    @MainActor
    func testCreatingASpace() {
        // With some keyboard layouts (such as U.S. International – PC) XCUITest synthesizes "c" as
        // ⌘C, so typed test strings avoid that letter.
        let spaceName = "Studio"
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["Spaces"].click()
        app.menuBars.menuItems["New Space"].click()
        let name = app.textFields["spaceNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText(spaceName)
        XCTAssertEqual(name.value as? String, spaceName)
        app.buttons["createSpaceButton"].click()
        let header = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'spaceHeader' AND label CONTAINS %@", spaceName))
            .firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "The sidebar switches to the new Space")
        XCTAssertFalse(name.exists, "The form closes after creating the Space")
    }
}
