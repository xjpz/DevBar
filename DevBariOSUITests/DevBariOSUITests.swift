import XCTest

final class DevBariOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSmokeNavigationAcrossTabs() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["ios.dashboard.providersTitle"].waitForExistence(timeout: 5))

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["ios.accounts.scan"].waitForExistence(timeout: 5))

        tabBar.buttons.element(boundBy: 2).tap()
        XCTAssertTrue(app.staticTexts["ios.settings.refreshHint"].waitForExistence(timeout: 5))
    }
}
