import Foundation

/// The locked top part of main.py on farm levels. It declares every variable the level uses and
/// defines each drone command as a real Python function, so the player can read what everything does.
/// The bodies mirror FarmWorld exactly: keep them in sync when game rules change.
/// Lines are kept short (about 44 characters) so they don't wrap on a phone.
enum FarmSetup {
    static let commandOrder = ["move", "till", "plant", "water", "wait", "harvest"]

    static func source(for l: LevelSpec) -> String {
        let crops = l.crops
        let goals = l.cropGoals
        /// One crop and one goal: plain numbers. Otherwise dictionaries keyed by crop.
        let simple = crops.count == 1
        let maxLost = l.farm?.maxLost
        var prePlanted = false
        if let layout = l.farm?.layout, case .ripeRow = layout { prePlanted = true }

        var s = """
        # ======== FARM SETUP (locked) ========
        # This part builds the level. Every name
        # your code can use is created below, and
        # each command shows what it really does.
        # Your code goes at the very bottom.

        # ---- The map ----
        # field is the grid you see on the left.
        #   field.tile_at(x, y)  the tile at x, y
        #   field.is_open(x, y)  False for rocks,
        #                        ponds and the fence
        # Each tile has:
        #   .ground  "grass", "soil", "rock" or
        #            "water"
        #   .crop    the crop growing there, or None
        #            (a crop has .kind, .age, .ripe)
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

        s += "# ---- Crops ----\n"
        for c in crops { s += "\(c.kind.rawValue) = \"\(c.kind.rawValue)\"\n" }
        if prePlanted { s += "# Some crops are already growing here.\n" }
        s += "# Ticks a crop needs before it's ripe:\n"
        if simple {
            s += "GROW_TIME = \(crops.first?.growTime ?? 2)\n"
        } else {
            s += "GROW_TIME = {\n" + crops.map { "    \($0.kind.rawValue): \($0.growTime)," }.joined(separator: "\n") + "\n}\n"
        }
        s += "\n# Everything you've harvested so far:\n"
        if simple {
            s += "stock = {\(crops.first?.kind.rawValue ?? "Wheat"): 0}\n"
        } else {
            s += "stock = {\n" + crops.map { "    \($0.kind.rawValue): 0," }.joined(separator: "\n") + "\n}\n"
        }
        if simple {
            s += "# Harvest this many \(goals.first?.kind.rawValue ?? "Wheat") to win:\nGOAL = \(l.goal)\n"
        } else {
            s += "# Harvest this many of each to win:\n"
            s += "GOAL = {\n" + goals.map { "    \($0.kind.rawValue): \($0.count)," }.joined(separator: "\n") + "\n}\n"
        }

        if let maxLost {
            s += """


            # ---- Level rule ----
            # A crop harvested before it's ripe is
            # lost. Lose more than MAX_LOST and the
            # run ends.
            lost = 0
            MAX_LOST = \(maxLost)

            """
        }

        s += """


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
            s += def(name, simple: simple, countsLost: maxLost != nil) + "\n\n"
        }

        s += """
        # ============ YOUR CODE ============

        """
        return s
    }

    private static func def(_ name: String, simple: Bool, countsLost: Bool) -> String {
        switch name {
        case "move":
            return """
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
            """
        case "till":
            return """
            def till():
                # Turn grass under the drone into soil.
                tile = field.tile_at(drone.x, drone.y)
                if tile.ground == "grass":
                    tile.ground = "soil"
                tick()
            """
        case "plant":
            return """
            def plant(seed=Wheat):
                # Plant a seed in empty soil under
                # the drone. Grass won't take seeds.
                tile = field.tile_at(drone.x, drone.y)
                if tile.ground == "soil":
                    if tile.crop is None:
                        tile.crop = Crop(seed, age=0)
                tick()
            """
        case "water":
            return """
            def water():
                # Wet the soil under the drone. Crops
                # on wet soil age 2 per tick (see
                # tick above) for the next 8 ticks.
                tile = field.tile_at(drone.x, drone.y)
                if tile.ground == "soil":
                    tile.wet = 8
                tick()
            """
        case "wait":
            return """
            def wait(ticks=1):
                # Do nothing while time passes.
                # wait() lets 1 tick pass, wait(3)
                # lets 3 ticks pass.
                for i in range(ticks):
                    tick()
            """
        case "harvest":
            let ripeTest = simple ? "crop.age >= GROW_TIME" : "crop.age >= GROW_TIME[crop.kind]"
            if countsLost {
                return """
                def harvest():
                    # Pick the crop under the drone.
                    global lost
                    tile = field.tile_at(drone.x, drone.y)
                    crop = tile.crop
                    if crop is not None:
                        if \(ripeTest):
                            stock[crop.kind] += 1
                        else:
                            # Not ripe: it's wasted.
                            lost += 1
                        tile.crop = None
                    tick()
                """
            }
            return """
            def harvest():
                # Pick the crop under the drone.
                tile = field.tile_at(drone.x, drone.y)
                crop = tile.crop
                if crop is not None:
                    if \(ripeTest):
                        stock[crop.kind] += 1
                    # An unripe crop is still removed,
                    # so it's lost.
                    tile.crop = None
                tick()
            """
        default:
            return ""
        }
    }
}
