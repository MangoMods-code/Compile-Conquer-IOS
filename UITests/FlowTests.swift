import XCTest

/// Plays through the real app the way a player does, and saves screenshots of every screen
/// to /tmp/cc-shots. CI publishes them to the `ci-screenshots` branch so the look can be reviewed.
final class FlowTests: XCTestCase {
    static let dir = "/tmp/cc-shots"

    override func setUp() { continueAfterFailure = true }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(Self.dir)/\(name).png", contents: png)
    }

    private func code(_ levelID: String, _ python: String) -> [String] {
        ["-uitest.code.\(levelID)", Data(python.utf8).base64EncodedString()]
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        return app
    }

    /// Everything open, no intro cards, playback at 4x.
    private let unlocked = ["-uitest.allStars", "3", "-owner.anyCampaign", "YES", "-uitest.noIntro", "YES", "-set.speed", "2"]

    private func tap(_ app: XCUIApplication, _ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let b = app.buttons[id]
        XCTAssertTrue(b.waitForExistence(timeout: 8), "button \(id) not found", file: file, line: line)
        if b.exists { b.tap() }
        usleep(700_000)
    }

    private func open(_ app: XCUIApplication, world: String, level: String) {
        tap(app, "play")
        tap(app, "world.\(world)")
        tap(app, "level.\(level)")
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "app crashed opening \(level)")
    }

    private func waitForWin(_ app: XCUIApplication, timeout: TimeInterval = 150, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts["levelComplete"].waitForExistence(timeout: timeout), "level never completed", file: file, line: line)
        sleep(2)
    }

    // MARK: Flows

    func testFreshPlayerBeatsLevelOne() {
        let app = launch(code("py.farm.1", PySolutions.intended["py.farm.1"] ?? ""))
        shot("01-title")
        tap(app, "play")
        shot("02-worlds")
        tap(app, "world.farm")
        shot("03-levels-farm-new")
        tap(app, "level.py.farm.1")
        sleep(2)
        shot("04-intro-card")
        tap(app, "intro.start")
        shot("05-level-setup")
        tap(app, "Your code")
        shot("06-level-code")
        tap(app, "Run")
        waitForWin(app)
        shot("07-win-card")
        tap(app, "next")
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
        shot("08-next-level-intro")
    }

    func testFarmLoopsAndVariables() {
        let app = launch(unlocked + code("py.farm.9", PySolutions.intended["py.farm.9"] ?? ""))
        tap(app, "play")
        tap(app, "world.farm")
        shot("10-levels-farm-cleared")
        tap(app, "level.py.farm.9")
        sleep(2)
        tap(app, "Run")
        sleep(3)
        tap(app, "tab.Var")
        shot("11-farm-running-variables")
        waitForWin(app)
        shot("12-farm-win-tidy")
    }

    func testFarmIfLevelAndBigField() {
        var app = launch(unlocked + code("py.farm.8", PySolutions.intended["py.farm.8"] ?? ""))
        open(app, world: "farm", level: "py.farm.8")
        shot("13-farm-if-level")
        tap(app, "Run")
        waitForWin(app)
        app.terminate()

        app = launch(unlocked + code("py.farm.10", PySolutions.intended["py.farm.10"] ?? ""))
        open(app, world: "farm", level: "py.farm.10")
        tap(app, "Run")
        sleep(6)
        shot("14-farm-festival-running")
        waitForWin(app)
    }

    func testWarehouse() {
        var app = launch(unlocked + code("py.warehouse.stock", PySolutions.intended["py.warehouse.stock"] ?? ""))
        tap(app, "play")
        tap(app, "world.warehouse")
        shot("20-levels-warehouse")
        tap(app, "level.py.warehouse.stock")
        sleep(2)
        shot("21-warehouse-open")
        tap(app, "Run")
        sleep(4)
        shot("22-warehouse-running")
        waitForWin(app)
        shot("23-warehouse-win")
        app.terminate()

        app = launch(unlocked + code("py.warehouse.6", PySolutions.warehouse))
        open(app, world: "warehouse", level: "py.warehouse.6")
        tap(app, "Run")
        sleep(5)
        shot("24-night-shift-running")
        waitForWin(app, timeout: 240)
    }

    func testFailureReviewAndTools() {
        // A program that bumps into things and then breaks: the run should fail politely.
        let broken = "move(North)\nmove(North)\nmove(North)\nmove(North)\nmove(North)\nprint(\"so far so good\")\nmove(Up)\n"
        let app = launch(unlocked + code("py.farm.2", broken))
        open(app, world: "farm", level: "py.farm.2")
        tap(app, "Run")
        XCTAssertTrue(app.buttons["fixCode"].waitForExistence(timeout: 30), "failure banner never appeared")
        sleep(1)
        shot("30-failure-banner")
        tap(app, "Review run")
        tap(app, "stepBack")
        tap(app, "stepBack")
        shot("31-review-scrubbed-back")
        tap(app, "reset")

        // Tap a tile in the middle of the map to inspect it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.27, dy: 0.55)).tap()
        sleep(1)
        shot("32-tile-inspector")

        tap(app, "hint")
        tap(app, "handbook")
        sleep(1)
        shot("33-handbook")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testSettings() {
        let app = launch(["-owner.unlocked", "YES"])
        tap(app, "settings")
        sleep(1)
        shot("40-settings")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
