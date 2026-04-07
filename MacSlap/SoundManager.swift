import Foundation
import AVFoundation

class SoundManager {
    private var players: [URL: AVAudioPlayer] = [:]

    // Looping player for continuous lid sound
    private var loopPlayer: AVAudioPlayer?
    private var loopURL: URL?

    func play(url: URL, volume: Float = 1.0) {
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

    // MARK: - Continuous Looping Sound (accordion-style lid movement)

    /// Start or update the looping lid sound. Volume tracks movement speed.
    func updateLoopingSound(url: URL, volume: Float) {
        let vol = max(0.0, min(volume, 1.0))

        // If URL changed or player doesn't exist, create it
        if loopURL != url || loopPlayer == nil || loopPlayer?.isPlaying != true {
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

        // Smooth volume update
        if let player = loopPlayer {
            let current = player.volume
            player.volume = current + (vol - current) * 0.3
        }
    }

    /// Stop the looping sound immediately
    func stopLoop() {
        loopPlayer?.stop()
        loopPlayer = nil
        loopURL = nil
    }

    func stop() {
        players.values.forEach { $0.stop() }
        players.removeAll()
        stopLoop()
    }

    func defaultSlapSound() -> URL? {
        if let bundled = Bundle.main.url(forResource: "slap_default", withExtension: "aiff") {
            return bundled
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff")
    }

    func defaultLidSound() -> URL? {
        if let bundled = Bundle.main.url(forResource: "creak_default", withExtension: "aiff") {
            return bundled
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/Pop.aiff")
    }

    func defaultChargerPlugSound() -> URL? {
        if let bundled = Bundle.main.url(forResource: "charger_plug", withExtension: "aiff") {
            return bundled
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/Bottle.aiff")
    }

    func defaultChargerUnplugSound() -> URL? {
        if let bundled = Bundle.main.url(forResource: "charger_unplug", withExtension: "aiff") {
            return bundled
        }
        return URL(fileURLWithPath: "/System/Library/Sounds/Basso.aiff")
    }

    static func systemSounds() -> [URL] {
        let soundsDir = URL(fileURLWithPath: "/System/Library/Sounds")
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: soundsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { ["aiff", "aif", "wav", "mp3", "m4a", "caf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func preview(url: URL) {
        play(url: url, volume: 1.0)
    }
}
