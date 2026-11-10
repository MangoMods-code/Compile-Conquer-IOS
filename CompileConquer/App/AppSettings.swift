import Foundation
import CryptoKit

/// Player settings, saved on the device.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var codeFontSize: Double { didSet { d.set(codeFontSize, forKey: "set.font") } }
    @Published var defaultSpeed: Int { didSet { d.set(defaultSpeed, forKey: "set.speed") } }
    @Published var showCropAges: Bool { didSet { d.set(showCropAges, forKey: "set.cropAges") } }
    @Published var showCoords: Bool { didSet { d.set(showCoords, forKey: "set.coords") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "set.haptics") } }
    @Published var soundOn: Bool { didSet { d.set(soundOn, forKey: "set.sound"); SoundFX.shared.settingsChanged() } }
    @Published var soundVolume: Double { didSet { d.set(soundVolume, forKey: "set.soundVol"); SoundFX.shared.settingsChanged() } }
    @Published var musicOn: Bool { didSet { d.set(musicOn, forKey: "set.music"); SoundFX.shared.settingsChanged() } }
    @Published var musicVolume: Double { didSet { d.set(musicVolume, forKey: "set.musicVol"); SoundFX.shared.settingsChanged() } }

    /// Owner tools: hidden until unlocked with the owner code.
    @Published var ownerUnlocked: Bool { didSet { d.set(ownerUnlocked, forKey: "owner.unlocked") } }
    /// Owner only: every built campaign and world is open, without finishing the one before.
    /// Levels inside a world still unlock one by one.
    @Published var playAnyCampaign: Bool { didSet { d.set(playAnyCampaign, forKey: "owner.anyCampaign") } }

    private init() {
        let ud = UserDefaults.standard
        codeFontSize = ud.object(forKey: "set.font") as? Double ?? 13
        defaultSpeed = ud.object(forKey: "set.speed") as? Int ?? 1
        showCropAges = ud.object(forKey: "set.cropAges") as? Bool ?? true
        showCoords = ud.object(forKey: "set.coords") as? Bool ?? true
        haptics = ud.object(forKey: "set.haptics") as? Bool ?? true
        soundOn = ud.object(forKey: "set.sound") as? Bool ?? true
        soundVolume = ud.object(forKey: "set.soundVol") as? Double ?? 0.8
        musicOn = ud.object(forKey: "set.music") as? Bool ?? true
        musicVolume = ud.object(forKey: "set.musicVol") as? Double ?? 0.5
        ownerUnlocked = ud.bool(forKey: "owner.unlocked")
        playAnyCampaign = ud.bool(forKey: "owner.anyCampaign")
    }

    static func hash(_ code: String) -> String {
        SHA256.hash(data: Data(code.trimmingCharacters(in: .whitespaces).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The starting owner code is "conquer"; setOwnerCode stores a new one (as a hash).
    func checkOwnerCode(_ code: String) -> Bool {
        let stored = d.string(forKey: "owner.hash") ?? AppSettings.hash("conquer")
        return AppSettings.hash(code) == stored
    }

    func setOwnerCode(_ code: String) {
        d.set(AppSettings.hash(code), forKey: "owner.hash")
    }

    func lockOwnerTools() {
        playAnyCampaign = false
        ownerUnlocked = false
    }
}
