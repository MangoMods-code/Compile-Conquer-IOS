import XCTest

/// Taps through the real menus into levels, the way a player does.
final class MenuFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(anyCampaign: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        // -key value launch arguments override UserDefaults for this run.
        app.launchArguments += ["-owner.anyCampaign", anyCampaign ? "YES" : "NO", "-owner.unlocked", anyCampaign ? "YES" : "NO"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        return app
    }

    private func open(_ app: XCUIApplication, world: String, level: String) {
        app.buttons["play"].tap()
        let campaign = app.buttons["campaign.python"]
        XCTAssertTrue(campaign.waitForExistence(timeout: 5))
        campaign.tap()
        let w = app.buttons["world.\(world)"]
        XCTAssertTrue(w.waitForExistence(timeout: 5))
        w.tap()
        let l = app.buttons["level.\(level)"]
        XCTAssertTrue(l.waitForExistence(timeout: 5))
        l.tap()
        // Give the level a few seconds to build and render; a crash fails here.
        sleep(4)
        XCTAssertEqual(app.state, .runningForeground, "app crashed opening \(level)")
        XCTAssertTrue(app.staticTexts["main.py"].waitForExistence(timeout: 5), "level screen didn't appear for \(level)")
    }

    func testOpenFarmLevel1() {
        let app = launch(anyCampaign: false)
        open(app, world: "farm", level: "py.farm.1")
    }

    func testOpenWarehouseLevel1WithOwnerSwitch() {
        let app = launch(anyCampaign: true)
        open(app, world: "warehouse", level: "py.warehouse.1")
        // Run the starter code too.
        app.buttons["Run"].tap()
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "app crashed running the warehouse level")
    }
}
