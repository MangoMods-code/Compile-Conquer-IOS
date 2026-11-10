import XCTest

/// Walks through the game and saves screenshots to /tmp/cc-shots on the CI machine.
/// CI publishes them to the `ci-screenshots` branch so the look can be reviewed.
final class ScreenshotTests: XCTestCase {
    static let dir = "/tmp/cc-shots"

    override func setUp() { continueAfterFailure = true }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: Self.dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: "\(Self.dir)/\(name).png", contents: png)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest.allStars", "3", "-owner.anyCampaign", "YES", "-owner.unlocked", "YES"] + extra
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        return app
    }

    private func tap(_ app: XCUIApplication, _ id: String) {
        let b = app.buttons[id]
        if b.waitForExistence(timeout: 6) { b.tap() }
        sleep(1)
    }

    func testMenus() {
        let app = launch()
        shot("01-title")
        tap(app, "play")
        shot("02-campaigns")
        tap(app, "campaign.python")
        shot("03-worlds")
        tap(app, "world.farm")
        shot("04-levels-farm")
    }

    func testFarmLevel() {
        let app = launch(["-cc.code.py.farm.5", Solvers.farm, "-set.speed", "1"])
        tap(app, "play"); tap(app, "campaign.python"); tap(app, "world.farm"); tap(app, "level.py.farm.5")
        sleep(2)
        shot("05-farm-open")
        tap(app, "Your code")
        shot("06-farm-code")
        tap(app, "Run")
        sleep(4)
        shot("07-farm-running")
        if app.staticTexts["LEVEL COMPLETE"].waitForExistence(timeout: 90) { sleep(1) }
        shot("08-farm-won")
    }

    func testWarehouseLevel() {
        let app = launch(["-cc.code.py.warehouse.6", Solvers.warehouse, "-set.speed", "1"])
        tap(app, "play"); tap(app, "campaign.python"); tap(app, "world.warehouse")
        shot("09-levels-warehouse")
        tap(app, "level.py.warehouse.6")
        sleep(2)
        shot("10-warehouse-open")
        tap(app, "Run")
        sleep(5)
        shot("11-warehouse-running")
        if app.staticTexts["LEVEL COMPLETE"].waitForExistence(timeout: 120) { sleep(1) }
        shot("12-warehouse-won")
    }
}

enum Solvers {
    static let path = """
    def path_to(tx, ty, me, grid):
        start = (me.x, me.y)
        prev = {start: None}
        queue = [start]
        while len(queue) > 0:
            cur = queue.pop(0)
            if cur == (tx, ty):
                break
            x, y = cur
            for d in [North, East, South, West]:
                nx = x
                ny = y
                if d == North:
                    ny += 1
                elif d == South:
                    ny -= 1
                elif d == East:
                    nx += 1
                else:
                    nx -= 1
                nxt = (nx, ny)
                if grid.is_open(nx, ny) and nxt not in prev:
                    prev[nxt] = (cur, d)
                    queue.append(nxt)
        steps = []
        cur = (tx, ty)
        while prev[cur] is not None:
            p, d = prev[cur]
            steps.append(d)
            cur = p
        steps.reverse()
        for d in steps:
            move(d)

    """

    static let farm = path + """
    targets = []
    for y in range(field.height):
        for x in range(field.width):
            if field.tile_at(x, y).ground == "soil":
                targets.append((x, y))
    for t in targets:
        path_to(t[0], t[1], drone, field)
        plant()
        water()
    for t in targets:
        path_to(t[0], t[1], drone, field)
        while field.tile_at(t[0], t[1]).crop.age < GROW_TIME:
            wait()
        harvest()
    """

    static let warehouse = path + """
    while len(floor.crates) > 0 or loader.carrying is not None:
        if loader.carrying is None:
            c = floor.crates[0]
            path_to(c.x, c.y, loader, floor)
            pick()
        color = loader.carrying.color
        if color == "?":
            color = scan()
        bay = BAYS[color]
        path_to(bay.x, bay.y, loader, floor)
        drop()
        print("shipped", shipped)
    """
}
