import Foundation

/// Python programs used by the tests: general solvers that beat any map, and the
/// "intended" solutions each level's hints point toward (which must earn 3 stars).
/// Shared by the unit tests and the UI tests.
enum PySolutions {
    // Breadth-first search, so the general solvers work on any map.
    static let pathTo = """
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

    /// Farm levels with one crop (GOAL is a number).
    static let farmSimple = pathTo + """
    targets = []
    for y in range(field.height):
        for x in range(field.width):
            if field.tile_at(x, y).ground == "soil":
                targets.append((x, y))
    if len(targets) == 0:
        for y in range(field.height):
            for x in range(field.width):
                if field.tile_at(x, y).ground == "grass":
                    targets.append((x, y))
    i = 0
    while stock[Wheat] < GOAL:
        tx, ty = targets[i % len(targets)]
        i += 1
        if (drone.x, drone.y) != (tx, ty):
            path_to(tx, ty, drone, field)
        if field.tile_at(tx, ty).ground == "grass":
            till()
        plant()
        while not field.tile_at(tx, ty).crop.ripe:
            wait()
        harvest()
        print(f"stock is {stock[Wheat]} of {GOAL}")
    """

    /// Farm levels with several crops (GOAL is a dictionary), including crops that are already growing.
    static let farmMulti = pathTo + """
    def needed():
        for seed in GOAL:
            if stock[seed] < GOAL[seed]:
                return seed
        return None

    spots = []
    for y in range(field.height):
        for x in range(field.width):
            spots.append((x, y))
    for x, y in spots:
        crop = field.tile_at(x, y).crop
        if crop is not None and crop.ripe and stock[crop.kind] < GOAL.get(crop.kind, 0):
            path_to(x, y, drone, field)
            harvest()

    soil = [p for p in spots if field.tile_at(p[0], p[1]).ground == "soil" and field.tile_at(p[0], p[1]).crop is None]
    seed = needed()
    while seed is not None:
        tx, ty = soil[0]
        path_to(tx, ty, drone, field)
        plant(seed)
        while not field.tile_at(tx, ty).crop.ripe:
            wait()
        harvest()
        seed = needed()
    """

    static let warehouse = pathTo + """
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

    // MARK: Intended solutions (what the level teaches). These must earn 3 stars.

    /// Works out which way a row of soil runs from the drone.
    private static let rowDirection = """
    d = East
    back = West
    if not field.is_open(drone.x + 1, drone.y) or field.tile_at(drone.x + 1, drone.y).ground != "soil":
        d = West
        back = East

    """

    private static let goTo = """
    def go_to(x, y):
        while loader.x < x:
            move(East)
        while loader.x > x:
            move(West)
        while loader.y < y:
            move(North)
        while loader.y > y:
            move(South)

    """

    static let intended: [String: String] = [
        "py.farm.1": """
        plant()
        wait()
        harvest()
        """,
        "py.farm.6": rowDirection + """
        for i in range(5):
            move(d)
            plant()
        wait(5)
        for i in range(5):
            harvest()
            move(back)
        """,
        "py.farm.7": """
        dx = East
        bx = West
        if field.tile_at(drone.x + 1, drone.y).ground != "soil":
            dx = West
            bx = East
        dy = North
        by = South
        if field.tile_at(drone.x, drone.y + 1).ground != "soil":
            dy = South
            by = North
        for row in range(3):
            for col in range(4):
                plant()
                move(dx)
            for col in range(4):
                move(bx)
            move(dy)
        for row in range(3):
            move(by)
        for row in range(3):
            for col in range(4):
                harvest()
                move(dx)
            for col in range(4):
                move(bx)
            move(dy)
        """,
        "py.farm.8": """
        d = East
        if not field.is_open(drone.x + 1, drone.y):
            d = West
        for i in range(6):
            move(d)
            tile = field.tile_at(drone.x, drone.y)
            if tile.crop.ripe:
                harvest()
        """,
        "py.farm.9": rowDirection + """
        for seed in [Wheat, Carrot]:
            for i in range(4):
                move(d)
                plant(seed)
            wait(GROW_TIME[seed])
            for i in range(4):
                harvest()
                move(back)
        """,
        "py.farm.10": pathTo + """
        def grow(seed):
            plant(seed)
            water()
            wait(GROW_TIME[seed] // 2)
            harvest()

        best = None
        for y in range(field.height):
            for x in range(field.width):
                if field.tile_at(x, y).ground == "soil":
                    dist = abs(x - drone.x) + abs(y - drone.y)
                    if best is None or dist < best[0]:
                        best = (dist, x, y)
        path_to(best[1], best[2], drone, field)
        for seed in GOAL:
            for i in range(GOAL[seed]):
                grow(seed)
        """,
        "py.warehouse.5": """
        for i in range(4):
            for j in range(i + 1):
                move(East)
            pick()
            for j in range(i + 1):
                move(West)
            drop()
        """,
        "py.warehouse.sort": goTo + """
        for i in range(5):
            go_to(i + 1, 0)
            color = scan()
            pick()
            go_to(BAYS[color].x, BAYS[color].y)
            drop()
        """,
        "py.warehouse.stock": goTo + """
        for crate in floor.crates:
            go_to(crate.x, crate.y)
            pick()
            bay = BAYS[crate.color]
            go_to(bay.x, bay.y)
            drop()
        """,
    ]
}
