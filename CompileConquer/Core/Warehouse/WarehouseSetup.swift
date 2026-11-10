import Foundation

/// The locked top of main.py for warehouse levels: declares every variable and defines each
/// loader command with its real body. The bodies mirror WarehouseWorld: keep them in sync.
/// Lines stay under about 44 characters so they fit on a phone.
enum WarehouseSetup {
    static let commandOrder = ["move", "pick", "drop", "scan", "wait"]

    static func source(for l: LevelSpec) -> String {
        let p = l.warehouse
        var s = """
        # ====== WAREHOUSE SETUP (locked) ======
        # This part builds the level. Every name
        # your code can use is created below, and
        # each command shows what it really does.
        # Your code goes at the very bottom.

        # ---- The floor ----
        # floor is the grid you see on the left.
        # Blue racks block the loader.
        #   floor.is_open(x, y)   False for racks
        #                         and walls
        #   floor.crate_at(x, y)  the crate on that
        #                         tile, or None
        #   floor.crates          every crate still
        #                         on the floor
        floor = Floor(width=\(l.width), height=\(l.height))

        # loader is your forklift.
        #   loader.x, loader.y  its tile (0, 0 is
        #                       the bottom left)
        #   loader.carrying     the crate on its
        #                       forks, or None
        loader = floor.loader


        # ---- Directions ----
        # North is up on the map.
        North = "North"
        East = "East"
        South = "South"
        West = "West"


        # ---- Crates and bays ----
        # Every crate has .x, .y and .color.

        """
        if p?.hidden == true {
            s += """
            # Labels on these crates are hidden:
            # .color is "?" until you scan() them.

            """
        }
        if p?.rerollPositions == true {
            s += """
            # The crates land somewhere new every
            # time you press Run.

            """
        } else if p?.rerollColors == true {
            s += """
            # The colors are re-rolled every time
            # you press Run.

            """
        }
        s += """
        # Each striped bay takes one color.
        # BAYS["red"].x and BAYS["red"].y say
        # where the red bay is.
        BAYS = floor.bays

        # Crates delivered so far, and the goal:
        shipped = 0
        GOAL = \(l.goal)


        # ---- Time ----
        def tick():
            # One tick passes. Nothing grows in a
            # warehouse, but every command below
            # still takes 1 tick.
            floor.time += 1


        # ---- Loader commands ----

        """

        for name in commandOrder where l.commands.contains(name) {
            s += defs[name, default: ""] + "\n\n"
        }

        s += """
        # ============ YOUR CODE ============

        """
        return s
    }

    private static let defs: [String: String] = [
        "move": """
        def move(direction):
            # Drive one tile in a direction.
            x = loader.x
            y = loader.y
            if direction == North:
                y = y + 1
            elif direction == South:
                y = y - 1
            elif direction == East:
                x = x + 1
            elif direction == West:
                x = x - 1
            # Racks and walls block it: the loader
            # stays put, but the tick is used.
            if floor.is_open(x, y):
                loader.x = x
                loader.y = y
            tick()
        """,
        "pick": """
        def pick():
            # Lift the crate under the loader.
            crate = floor.crate_at(loader.x, loader.y)
            if loader.carrying is None:
                if crate is not None:
                    floor.remove(crate)
                    loader.carrying = crate
            tick()
        """,
        "drop": """
        def drop():
            # Put the carried crate down here.
            global shipped
            crate = loader.carrying
            x = loader.x
            y = loader.y
            bay = floor.bay_at(x, y)
            if crate is not None:
                if bay is not None:
                    # A bay only takes its color.
                    if bay.color == crate.color:
                        shipped += 1
                        loader.carrying = None
                elif floor.crate_at(x, y) is None:
                    floor.put(crate, x, y)
                    loader.carrying = None
            tick()
        """,
        "scan": """
        def scan():
            # Read the label of the crate here, or
            # the one on the forks. It returns the
            # color, so you can store it:
            #     color = scan()
            crate = floor.crate_at(loader.x, loader.y)
            if crate is None:
                crate = loader.carrying
            tick()
            if crate is None:
                return None
            crate.hidden = False
            return crate.color
        """,
        "wait": """
        def wait(ticks=1):
            # Do nothing while time passes.
            for i in range(ticks):
                tick()
        """,
    ]
}
