import Foundation
@testable import CompileConquer

enum Solutions {
    /// A solver that beats any map of this level.
    static func general(for level: LevelSpec) -> String {
        switch level.world {
        case .farm: return level.crops.count == 1 ? PySolutions.farmSimple : PySolutions.farmMulti
        case .warehouse: return PySolutions.warehouse
        }
    }

    static var intended: [String: String] { PySolutions.intended }
}
