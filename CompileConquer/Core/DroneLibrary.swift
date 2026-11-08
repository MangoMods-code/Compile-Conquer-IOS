import Foundation

/// The read-only drone.py / farm.py the player can open to see where every command comes from.
enum DroneLibrary {
    static let modules: [String: Set<String>] = [
        "drone": ["move", "till", "plant", "water", "harvest", "wait"],
        "farm": ["North", "East", "South", "West", "Wheat"],
    ]

    private static let order = ["move", "till", "plant", "water", "wait", "harvest"]

    private static let defs: [String: String] = [
        "move": """
        def move(direction):
            \"\"\"Fly one tile in a direction: North, East, South or West.
            North is up on the map. Rocks, ponds and the fence
            block the drone: it bumps, stays put, and the tick is used.\"\"\"
        """,
        "till": """
        def till():
            \"\"\"Turn the grass under the drone into soil.
            Seeds can only be planted in soil.\"\"\"
        """,
        "plant": """
        def plant(seed=Wheat):
            \"\"\"Plant a seed in the soil under the drone.
            plant() plants Wheat. The tile must be soil and empty.\"\"\"
        """,
        "water": """
        def water():
            \"\"\"Water the soil under the drone.
            Wet soil grows crops 2x faster for the next 8 ticks.\"\"\"
        """,
        "wait": """
        def wait():
            \"\"\"Do nothing for 1 tick while crops keep growing.\"\"\"
        """,
        "harvest": """
        def harvest():
            \"\"\"Pick the crop under the drone and add it to your stock.
            Only ripe (golden) crops count. Harvesting a green one loses it.\"\"\"
        """,
    ]

    static func source(for level: LevelSpec) -> String {
        var out = """
        # drone.py (built in, read-only)
        # These are the commands main.py imports with:
        #     from drone import \(level.commands.joined(separator: ", "))
        # Every command takes 1 tick of game time.


        """
        for name in order where level.commands.contains(name) {
            out += defs[name, default: ""] + "\n    ...\n\n"
        }
        if level.commands.count < order.count {
            out += "# More commands unlock in later levels.\n\n"
        }
        out += """

        # farm.py (built in, read-only)
        # main.py imports with:
        #     from farm import \(level.farmNames.joined(separator: ", "))


        """
        if level.usesDirections {
            out += """
            North = "North"   # up on the map
            East = "East"     # right
            South = "South"   # down
            West = "West"     # left


            """
        }
        out += """
        Wheat = "Wheat"
        # Wheat ripens after \(level.growTime) ticks on this level (half that on wet soil).
        # Green = still growing, golden = ready to harvest.

        """
        return out
    }
}
