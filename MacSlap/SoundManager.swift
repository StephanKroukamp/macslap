import Foundation
import AVFoundation

class SoundManager {
    private var players: [URL: AVAudioPlayer] = [:]

    // Looping player for continuous lid sound
    private var loopPlayer: AVAudioPlayer?
    private var loopFadeTimer: Timer?
    private var loopTargetVolume: Float = 0
    private var loopURL: URL?

    func play(url: URL, volume: Float = 1.0) {
        // Stop any currently playing instance of this sound
        players[url]?.stop()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = max(0.1, min(volume, 1.0))
            player.prepareToPlay()
            player.play()
            players[url] = player
        } catch {
            print("[MacSlap] Failed to play sound: \(error.localizedDescription)")
        }
    }

    // MARK: - Continuous Looping Sound (for lid movement)

    /// Start or update the looping lid sound. Volume tracks movement speed.
    func updateLoopingSound(url: URL, volume: Float) {
        let vol = max(0.0, min(volume, 1.0))

        // If URL changed or player doesn't exist, create it
        if loopURL != url || loopPlayer == nil {
            loopPlayer?.stop()
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1  // Infinite loop
                player.volume = vol
                player.prepareToPlay()
                player.play()
                loopPlayer = player
                loopURL = url
            } catch {
                print("[MacSlap] Failed to start loop: \(error.localizedDescription)")
                return
            }
        }

        // Update volume immediately — smoothly interpolate to avoid pops
        if let player = loopPlayer {
            let current = player.volume
            // Smooth volume changes to avoid clicks
            player.volume = current + (vol - current) * 0.4
        }
    }

    /// Fade the loop to silence over ~200ms then stop
    private func fadeOutLoop() {
        loopFadeTimer?.invalidate()

        // Rapid fade-out in steps
        var step = 0
        loopFadeTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] timer in
            guard let self = self, let player = self.loopPlayer else {
                timer.invalidate()
                return
            }
            step += 1
            player.volume *= 0.6  // Exponential decay
            if player.volume < 0.01 || step > 8 {
                player.stop()
                self.loopPlayer = nil
                self.loopURL = nil
                timer.invalidate()
                self.loopFadeTimer = nil
            }
        }
    }

    /// Immediately stop the loop
    func stopLoop() {
        loopFadeTimer?.invalidate()
        loopFadeTimer = nil
        loopPlayer?.stop()
        loopPlayer = nil
        loopURL = nil
    }

    func stop() {
        players.values.forEach { $0.stop() }
        players.removeAll()
        stopLoop()
    }

    /// Returns URL to the default slap sound bundled with the app
    func defaultSlapSound() -> URL? {
        if let bundled = Bundle.main.url(forResource: "slap_default", withExtension: "aiff") {
            return bundled
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff")
    }

    /// Returns URL to the default lid sound bundled with the app
    func defaultLidSound() -> URL? {
        if let bundled = Bundle.main.url(forResource: "creak_default", withExtension: "aiff") {
            return bundled
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
    }

    /// Returns URL to the default charger plug-in sound
    func defaultChargerPlugSound() -> URL? {
        if let bundled = Bundle.main.url(forResource: "charger_plug", withExtension: "aiff") {
            return bundled
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/Bottle.aiff")
    }

    /// Returns URL to the default charger unplug sound
    func defaultChargerUnplugSound() -> URL? {
        if let bundled = Bundle.main.url(forResource: "charger_unplug", withExtension: "aiff") {
            return bundled
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/Basso.aiff")
    }

    /// Returns list of available system sounds
    static func systemSounds() -> [URL] {
        let soundsDir = URL(fileURLWithPath: "/System/Library/Sounds")
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: soundsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { ["aiff", "aif", "wav", "mp3", "m4a", "caf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Preview a sound at full volume
    func preview(url: URL) {
        play(url: url, volume: 1.0)
    }
}
