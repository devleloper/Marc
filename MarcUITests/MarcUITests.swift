import XCTest

/// End-to-end checks of the main browser flows. The app runs with `-ui-testing`, which uses
/// in-memory databases, skips onboarding and disables network-dependent features.
final class MarcUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = await MainActor.run {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launch()
            return app
        }
    }

    override func tearDown() async throws {
        await MainActor.run { app.terminate() }
    }

    @MainActor
    func testLaunchShowsSidebarAndEmptyContent() {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["addressField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["newTabRow"].exists)
    }

    @MainActor
    func testCommandBarOpensATab() {
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
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.typeKey("t", modifierFlags: .command)
        let field = app.textFields["commandBarField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testToggleSidebarHidesAndShowsIt() {
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
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        app.menuBars.menuBarItems["Spaces"].click()
        app.menuBars.menuItems["New Space"].click()
        let name = app.textFields["spaceNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Research")
        app.buttons["createSpaceButton"].click()
        XCTAssertTrue(app.staticTexts["Research"].waitForExistence(timeout: 5))
    }
}
