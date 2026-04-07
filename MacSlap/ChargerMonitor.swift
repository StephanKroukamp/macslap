import Foundation
import IOKit.ps

/// Monitors charger plug/unplug events using IOKit Power Sources.
class ChargerMonitor {
    var onChargerPluggedIn: (() -> Void)?
    var onChargerUnplugged: (() -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var wasPluggedIn: Bool?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Get initial state
        wasPluggedIn = isChargerConnected()

        // Register for power source change notifications
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let ctx = context else { return }
            let monitor = Unmanaged<ChargerMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.handlePowerSourceChange()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
            print("[MacSlap] Charger monitoring started (plugged in: \(wasPluggedIn == true))")
        } else {
            print("[MacSlap] Failed to create power source notification")
        }
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        isRunning = false
        wasPluggedIn = nil
        print("[MacSlap] Charger monitoring stopped")
    }

    private func handlePowerSourceChange() {
        let pluggedIn = isChargerConnected()

        if let was = wasPluggedIn {
            if pluggedIn && !was {
                DispatchQueue.main.async { [weak self] in
                    self?.onChargerPluggedIn?()
                }
            } else if !pluggedIn && was {
                DispatchQueue.main.async { [weak self] in
                    self?.onChargerUnplugged?()
                }
            }
        }

        wasPluggedIn = pluggedIn
    }

    private func isChargerConnected() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              !sources.isEmpty else {
            return false
        }

        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source as CFTypeRef)?.takeUnretainedValue() as? [String: Any] {
                if let powerSource = desc[kIOPSPowerSourceStateKey] as? String {
                    return powerSource == kIOPSACPowerValue
                }
            }
        }

        return false
    }

    deinit {
        stop()
    }
}
