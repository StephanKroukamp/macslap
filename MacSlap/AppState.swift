import Foundation
import Combine

class AppState: ObservableObject {
    @Published var slapCount: Int = 0
    @Published var isListening: Bool = true

    // Slap settings
    @Published var slapSoundURL: URL? {
        didSet { save("slapSoundPath", value: slapSoundURL?.path ?? "") }
    }
    @Published var slapSensitivity: Double = 2.5 {
        didSet {
            save("slapSensitivity", value: slapSensitivity)
            slapDetector.sensitivity = slapSensitivity
        }
    }
    @Published var slapCooldown: Double = 0.5 {
        didSet {
            save("slapCooldown", value: slapCooldown)
            slapDetector.cooldown = slapCooldown
        }
    }
    @Published var slapEnabled: Bool = true {
        didSet {
            save("slapEnabled", value: slapEnabled)
            if slapEnabled { slapDetector.start() } else { slapDetector.stop() }
        }
    }

    // Charger settings
    @Published var chargerPlugSoundURL: URL? {
        didSet { save("chargerPlugSoundPath", value: chargerPlugSoundURL?.path ?? "") }
    }
    @Published var chargerUnplugSoundURL: URL? {
        didSet { save("chargerUnplugSoundPath", value: chargerUnplugSoundURL?.path ?? "") }
    }
    @Published var chargerEnabled: Bool = true {
        didSet {
            save("chargerEnabled", value: chargerEnabled)
            if chargerEnabled { chargerMonitor.start() } else { chargerMonitor.stop() }
        }
    }
    @Published var lastChargerEvent: String = ""
    @Published var lastChargerTime: Date = .distantPast

    // Lid settings
    @Published var lidSoundURL: URL? {
        didSet { save("lidSoundPath", value: lidSoundURL?.path ?? "") }
    }
    @Published var lidEnabled: Bool = true {
        didSet {
            save("lidEnabled", value: lidEnabled)
            if lidEnabled { lidAngleMonitor.start() } else { lidAngleMonitor.stop() }
        }
    }
    @Published var lidAngleThreshold: Double = 5.0 {
        didSet {
            save("lidAngleThreshold", value: lidAngleThreshold)
            lidAngleMonitor.angleThreshold = lidAngleThreshold
        }
    }

    @Published var currentLidAngle: Double = 0
    @Published var lastSlapMagnitude: Double = 0
    @Published var lastSlapTime: Date = .distantPast
    @Published var lastLidTriggerTime: Date = .distantPast
    @Published var lastLidDelta: Double = 0
    @Published var lidMovementSpeed: Double = 0  // degrees/second

    let slapDetector = SlapDetector()
    let lidAngleMonitor = LidAngleMonitor()
    let chargerMonitor = ChargerMonitor()
    let soundManager = SoundManager()

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadSettings()
        setupDetectors()
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        slapSensitivity = d.double(forKey: "slapSensitivity") > 0 ? d.double(forKey: "slapSensitivity") : 2.5
        slapCooldown = d.double(forKey: "slapCooldown") > 0 ? d.double(forKey: "slapCooldown") : 0.5
        slapEnabled = d.object(forKey: "slapEnabled") as? Bool ?? true
        chargerEnabled = d.object(forKey: "chargerEnabled") as? Bool ?? true
        lidEnabled = d.object(forKey: "lidEnabled") as? Bool ?? true
        lidAngleThreshold = d.double(forKey: "lidAngleThreshold") > 0 ? d.double(forKey: "lidAngleThreshold") : 5.0
        slapCount = d.integer(forKey: "slapCount")

        let slapPath = d.string(forKey: "slapSoundPath") ?? ""
        if !slapPath.isEmpty { slapSoundURL = URL(fileURLWithPath: slapPath) }

        let lidPath = d.string(forKey: "lidSoundPath") ?? ""
        if !lidPath.isEmpty { lidSoundURL = URL(fileURLWithPath: lidPath) }

        let chargerPlugPath = d.string(forKey: "chargerPlugSoundPath") ?? ""
        if !chargerPlugPath.isEmpty { chargerPlugSoundURL = URL(fileURLWithPath: chargerPlugPath) }
        let chargerUnplugPath = d.string(forKey: "chargerUnplugSoundPath") ?? ""
        if !chargerUnplugPath.isEmpty { chargerUnplugSoundURL = URL(fileURLWithPath: chargerUnplugPath) }
    }

    private func setupDetectors() {
        slapDetector.sensitivity = slapSensitivity
        slapDetector.cooldown = slapCooldown
        lidAngleMonitor.angleThreshold = lidAngleThreshold

        slapDetector.onSlap = { [weak self] magnitude in
            guard let self = self, self.isListening else { return }
            DispatchQueue.main.async {
                self.slapCount += 1
                self.lastSlapMagnitude = magnitude
                self.lastSlapTime = Date()
                self.save("slapCount", value: self.slapCount)

                let volume = Float(min(magnitude / (self.slapSensitivity * 2), 1.0))
                if let url = self.slapSoundURL {
                    self.soundManager.play(url: url, volume: volume)
                } else if let defaultURL = self.soundManager.defaultSlapSound() {
                    self.soundManager.play(url: defaultURL, volume: volume)
                }
            }
        }

        lidAngleMonitor.onMovement = { [weak self] angle, speed in
            guard let self = self, self.isListening else { return }
            DispatchQueue.main.async {
                self.currentLidAngle = angle
                self.lidMovementSpeed = speed
                self.lastLidDelta = speed
                self.lastLidTriggerTime = Date()

                // Volume proportional to movement speed
                // Slow movement (~20 deg/s) = quiet, fast (~100+ deg/s) = loud
                let volume = Float(min(speed / 80.0, 1.0))

                let url = self.lidSoundURL ?? self.soundManager.defaultLidSound()
                if let soundURL = url {
                    self.soundManager.updateLoopingSound(url: soundURL, volume: volume)
                }
            }
        }

        chargerMonitor.onChargerPluggedIn = { [weak self] in
            guard let self = self, self.isListening else { return }
            self.lastChargerEvent = "Plugged In"
            self.lastChargerTime = Date()
            let url = self.chargerPlugSoundURL ?? self.soundManager.defaultChargerPlugSound()
            if let soundURL = url {
                self.soundManager.play(url: soundURL, volume: 1.0)
            }
        }

        chargerMonitor.onChargerUnplugged = { [weak self] in
            guard let self = self, self.isListening else { return }
            self.lastChargerEvent = "Unplugged"
            self.lastChargerTime = Date()
            let url = self.chargerUnplugSoundURL ?? self.soundManager.defaultChargerUnplugSound()
            if let soundURL = url {
                self.soundManager.play(url: soundURL, volume: 1.0)
            }
        }

        if slapEnabled { slapDetector.start() }
        if lidEnabled { lidAngleMonitor.start() }
        if chargerEnabled { chargerMonitor.start() }
    }

    private func save(_ key: String, value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    func resetCount() {
        slapCount = 0
        save("slapCount", value: 0)
    }
}
