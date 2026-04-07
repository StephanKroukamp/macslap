import Foundation
import AppKit

/// Monitors screen wake/unlock events via NSWorkspace notifications.
class ScreenWakeMonitor {
    var onScreenWake: (() -> Void)?
    var onScreenSleep: (() -> Void)?

    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let center = NSWorkspace.shared.notificationCenter

        // Screen wakes up (lid opened or unlocked)
        center.addObserver(
            self,
            selector: #selector(handleScreenWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        // Screen goes to sleep (lid closed or locked)
        center.addObserver(
            self,
            selector: #selector(handleScreenSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )

        // Also listen for session unlock (login screen → desktop)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleScreenWake),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )

        print("[MacSlap] Screen wake/sleep monitoring started")
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        isRunning = false
        print("[MacSlap] Screen wake/sleep monitoring stopped")
    }

    @objc private func handleScreenWake() {
        DispatchQueue.main.async { [weak self] in
            self?.onScreenWake?()
        }
    }

    @objc private func handleScreenSleep() {
        DispatchQueue.main.async { [weak self] in
            self?.onScreenSleep?()
        }
    }

    deinit {
        stop()
    }
}
