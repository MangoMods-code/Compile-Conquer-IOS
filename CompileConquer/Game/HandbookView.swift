import SwiftUI

/// One entry in the handbook: a piece of code and what it does.
struct HandbookEntry: Identifiable {
    let code: String
    let note: String
    var id: String { code }
}

/// Quick reference for the current level: its commands, the things it can read, and Python basics.
enum Handbook {
    static func commands(for level: LevelSpec) -> [HandbookEntry] {
        let all: [String: HandbookEntry]
        switch level.world {
        case .farm:
            all = [
                "move": HandbookEntry(code: "move(direction)", note: "Fly one tile North, East, South or West. A blocked move still costs a tick."),
                "till": HandbookEntry(code: "till()", note: "Turn the grass under the drone into soil."),
                "plant": HandbookEntry(code: "plant(seed)", note: "Plant in empty soil under the drone. plant() on its own plants Wheat."),
                "water": HandbookEntry(code: "water()", note: "Wet the soil under the drone. Crops there grow twice as fast for 8 ticks."),
                "wait": HandbookEntry(code: "wait(ticks)", note: "Let time pass. wait() is 1 tick, wait(3) is 3."),
                "harvest": HandbookEntry(code: "harvest()", note: "Pick the crop under the drone. Only ripe crops count; unripe ones are lost."),
            ]
        case .warehouse:
            all = [
                "move": HandbookEntry(code: "move(direction)", note: "Drive one tile North, East, South or West. Racks and walls block the loader."),
                "pick": HandbookEntry(code: "pick()", note: "Lift the crate under the loader, if the forks are empty."),
                "drop": HandbookEntry(code: "drop()", note: "Put the crate down. On a bay of the same color it ships; a wrong bay refuses it."),
                "scan": HandbookEntry(code: "color = scan()", note: "Read the label of the crate here (or on the forks). Returns its color, like \"red\"."),
                "wait": HandbookEntry(code: "wait(ticks)", note: "Let time pass. wait() is 1 tick."),
            ]
        }
        return level.commands.compactMap { all[$0] }
    }

    static func things(for level: LevelSpec) -> [HandbookEntry] {
        switch level.world {
        case .farm:
            var out = [
                HandbookEntry(code: "drone.x, drone.y", note: "Where the drone is. (0, 0) is the bottom-left tile."),
                HandbookEntry(code: "field.tile_at(x, y)", note: "The tile at x, y. It has .ground, .crop and .wet."),
                HandbookEntry(code: "tile.crop", note: "The crop on a tile, or None. A crop has .kind, .age and .ripe."),
                HandbookEntry(code: "field.is_open(x, y)", note: "False for rocks, ponds and anything outside the fence."),
                HandbookEntry(code: "field.width, field.height", note: "The size of the field in tiles."),
            ]
            if level.crops.count == 1 {
                out.append(HandbookEntry(code: "stock[Wheat]", note: "How many you've harvested. You win when it reaches GOAL."))
                out.append(HandbookEntry(code: "GROW_TIME", note: "Ticks a crop needs before it's ripe."))
            } else {
                out.append(HandbookEntry(code: "stock[seed]", note: "How many of that crop you've harvested. GOAL[seed] is the target."))
                out.append(HandbookEntry(code: "GROW_TIME[seed]", note: "Ticks that crop needs before it's ripe."))
            }
            if level.farm?.maxLost != nil {
                out.append(HandbookEntry(code: "lost, MAX_LOST", note: "Unripe crops harvested so far, and how many are allowed."))
            }
            return out
        case .warehouse:
            return [
                HandbookEntry(code: "loader.x, loader.y", note: "Where the loader is. (0, 0) is the bottom-left tile."),
                HandbookEntry(code: "loader.carrying", note: "The crate on the forks, or None."),
                HandbookEntry(code: "floor.crates", note: "A list of every crate still on the floor. Each has .x, .y and .color."),
                HandbookEntry(code: "floor.crate_at(x, y)", note: "The crate on that tile, or None."),
                HandbookEntry(code: "floor.is_open(x, y)", note: "False for racks and walls."),
                HandbookEntry(code: "BAYS[\"red\"]", note: "The bay for a color. It has .x and .y."),
                HandbookEntry(code: "shipped", note: "Crates delivered so far. You win when it reaches GOAL."),
            ]
        }
    }

    static let python: [HandbookEntry] = [
        HandbookEntry(code: "count = 3\ncount = count + 1", note: "A variable stores a value under a name. Assign with a single =."),
        HandbookEntry(code: "for i in range(4):\n    move(East)", note: "Repeat the indented lines 4 times. i counts 0, 1, 2, 3."),
        HandbookEntry(code: "while drone.x < 5:\n    move(East)", note: "Repeat as long as the condition is true."),
        HandbookEntry(code: "if color == \"red\":\n    ...\nelif color == \"blue\":\n    ...\nelse:\n    ...", note: "Run different lines depending on a condition. Compare with ==, !=, <, >, <=, >=."),
        HandbookEntry(code: "def go(steps):\n    for i in range(steps):\n        move(North)\n\ngo(3)", note: "def makes your own command. Inputs go in the brackets; return hands a value back."),
        HandbookEntry(code: "seeds = [Wheat, Carrot]\nseeds.append(Pumpkin)\nfor seed in seeds:\n    plant(seed)", note: "A list holds values in order. seeds[0] is the first one, len(seeds) counts them."),
        HandbookEntry(code: "ages = {\"a\": 1}\nages[\"b\"] = 2", note: "A dictionary looks values up by key."),
        HandbookEntry(code: "print(f\"x is {drone.x}\")", note: "print shows values in the Console. An f-string drops values into text."),
        HandbookEntry(code: "if a > 1 and not done:", note: "Combine conditions with and, or, not."),
    ]
}

struct HandbookView: View {
    let level: LevelSpec
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Commands on this level", icon: "bolt.fill", color: Theme.blue, entries: Handbook.commands(for: level))
                    section("Things you can read", icon: "eye.fill", color: Theme.purple, entries: Handbook.things(for: level))
                    section("Python basics", icon: "chevron.left.forwardslash.chevron.right", color: Theme.accent, entries: Handbook.python)
                }
                .padding(20)
            }
            .background(GridBackground())
            .navigationTitle("Handbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(Theme.mono(14, .bold))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func section(_ title: String, icon: String, color: Color, entries: [HandbookEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title.uppercased()).font(Theme.mono(11, .bold))
            }
            .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { i, e in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    HStack(alignment: .top, spacing: 14) {
                        Text(e.code)
                            .font(Theme.mono(12, .bold))
                            .foregroundStyle(color)
                            .frame(width: 230, alignment: .leading)
                        Text(e.note)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.text.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                }
            }
            .card(radius: 14)
        }
    }
}
