import Foundation

/// The locked top part of main.py. It declares every variable the level uses and defines each
/// drone command as a real Python function, so the player can read what everything does.
/// The bodies mirror FarmWorld exactly: keep them in sync when game rules change.
/// Lines are kept short (about 44 characters) so they don't wrap on a phone.
enum FarmSetup {
    static let commandOrder = ["move", "till", "plant", "water", "wait", "harvest"]

    static func source(for l: LevelSpec) -> String {
        var s = """
        # ======== FARM SETUP (locked) ========
        # This part builds the level. Every name
        # your code can use is created below, and
        # each command shows what it really does.
        # Your code goes at the very bottom.

        # ---- The map ----
        # field is the grid you see on the left.
        # Each tile has:
        #   .ground  "grass", "soil", "rock" or
        #            "water"
        #   .crop    the crop growing there, or None
        #   .wet     ticks of water left (0 = dry)
        field = Field(width=\(l.width), height=\(l.height))

        # drone is your drone. drone.x and drone.y
        # are its tile (0, 0 is the bottom left).
        drone = field.drone


        """

        if l.usesDirections {
            s += """
            # ---- Directions ----
            # North is up on the map.
            North = "North"
            East = "East"
            South = "South"
            West = "West"


            """
        }

        s += """
        # ---- Crops ----
        Wheat = "Wheat"
        # Ticks a crop needs before it's ripe:
        GROW_TIME = \(l.growTime)

        # Everything you've harvested so far:
        stock = {Wheat: 0}
        # Harvest this many Wheat to win:
        GOAL = \(l.goal)


        # ---- Time ----
        def tick():
            # One tick passes. Every command below
            # ends by calling tick().
            for tile in field.tiles:
                if tile.crop is not None:
                    if tile.wet > 0:
                        tile.crop.age += 2
                    else:
                        tile.crop.age += 1
                if tile.wet > 0:
                    tile.wet -= 1


        # ---- Drone commands ----

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
            # Fly one tile in a direction.
            x = drone.x
            y = drone.y
            if direction == North:
                y = y + 1
            elif direction == South:
                y = y - 1
            elif direction == East:
                x = x + 1
            elif direction == West:
                x = x - 1
            # Rocks, ponds and the fence block it:
            # the drone stays put but the tick
            # is still used.
            if field.is_open(x, y):
                drone.x = x
                drone.y = y
            tick()
        """,
        "till": """
        def till():
            # Turn grass under the drone into soil.
            tile = field.tile_at(drone.x, drone.y)
            if tile.ground == "grass":
                tile.ground = "soil"
            tick()
        """,
        "plant": """
        def plant(seed=Wheat):
            # Plant a seed in empty soil under
            # the drone. Grass won't take seeds.
            tile = field.tile_at(drone.x, drone.y)
            if tile.ground == "soil":
                if tile.crop is None:
                    tile.crop = Crop(seed, age=0)
            tick()
        """,
        "water": """
        def water():
            # Wet the soil under the drone. Crops
            # on wet soil age 2 per tick (see
            # tick above) for the next 8 ticks.
            tile = field.tile_at(drone.x, drone.y)
            if tile.ground == "soil":
                tile.wet = 8
            tick()
        """,
        "wait": """
        def wait(ticks=1):
            # Do nothing while time passes.
            # wait() lets 1 tick pass, wait(3)
            # lets 3 ticks pass.
            for i in range(ticks):
                tick()
        """,
        "harvest": """
        def harvest():
            # Pick the crop under the drone.
            tile = field.tile_at(drone.x, drone.y)
            if tile.crop is not None:
                if tile.crop.age >= GROW_TIME:
                    stock[tile.crop.kind] += 1
                # An unripe crop is still removed,
                # so it's lost.
                tile.crop = None
            tick()
        """,
    ]
}
