import Foundation
import IOKit
import IOKit.hid

class LidAngleMonitor {
    var angleThreshold: Double = 5.0
    /// Called every tick with (angle, isMoving, speed). Always called so the
    /// caller can manage sound start/stop smoothly.
    var onTick: ((Double, Bool, Double) -> Void)?

    private var timer: Timer?
    private var isRunning = false
    private(set) var sensorAvailable = false

    // Angle tracking
    private var lastAngle: Double?
    private var lastChangeTime: TimeInterval = 0
    private var lastSpeed: Double = 0
    private let pollInterval: TimeInterval = 0.05  // 20Hz
    // How long after the last detected change we still consider "moving"
    // Bridges gaps between integer degree steps at slow speeds
    private let movingTimeout: TimeInterval = 0.4

    // HID sensor
    private var hidManager: IOHIDManager?
    private var angleElement: IOHIDElement?
    private var angleDevice: IOHIDDevice?

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if setupHIDSensor() {
            sensorAvailable = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.timer = Timer.scheduledTimer(withTimeInterval: self.pollInterval, repeats: true) { [weak self] _ in
                    self?.poll()
                }
            }
            print("[MacSlap] Lid angle monitoring started")
        } else {
            sensorAvailable = false
            print("[MacSlap] Lid angle sensor not found")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        angleElement = nil
        angleDevice = nil
        isRunning = false
        lastAngle = nil
        lastSpeed = 0
        print("[MacSlap] Lid angle monitoring stopped")
    }

    private func poll() {
        guard let angle = readLidAngle() else { return }
        let now = ProcessInfo.processInfo.systemUptime

        if let prev = lastAngle {
            let delta = abs(angle - prev)

            if delta >= 2 {
                // Real movement detected (not noise)
                lastSpeed = delta / pollInterval
                lastChangeTime = now
                lastAngle = angle
            }
            // else: angle didn't change (or noise) — don't update lastAngle
        } else {
            lastAngle = angle
            lastChangeTime = now
        }

        // Are we "moving"? Yes if we saw a change recently
        let timeSinceChange = now - lastChangeTime
        let isMoving = timeSinceChange < movingTimeout && lastSpeed > 0

        // Decay speed smoothly after movement stops
        let speed: Double
        if isMoving {
            let decay = max(0, 1.0 - timeSinceChange / movingTimeout)
            speed = lastSpeed * decay
        } else {
            speed = 0
        }

        onTick?(angle, isMoving, speed)
    }

    // MARK: - HID Sensor Setup

    private func setupHIDSensor() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matchDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 0x20,
            kIOHIDDeviceUsageKey as String: 138
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return false }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }

        for device in devices {
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else { continue }
            for elem in elements {
                if IOHIDElementGetUsagePage(elem) == 0x20 && IOHIDElementGetUsage(elem) == 0x47F && IOHIDElementGetLogicalMax(elem) == 360 {
                    self.angleDevice = device
                    self.angleElement = elem
                    self.hidManager = manager
                    return true
                }
            }
        }

        // Fallback
        for device in devices {
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else { continue }
            for elem in elements {
                if IOHIDElementGetUsagePage(elem) == 0x20 && IOHIDElementGetLogicalMax(elem) == 360 && IOHIDElementGetType(elem).rawValue == 1 {
                    self.angleDevice = device
                    self.angleElement = elem
                    self.hidManager = manager
                    return true
                }
            }
        }

        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return false
    }

    private func readLidAngle() -> Double? {
        guard let device = angleDevice, let element = angleElement else { return nil }
        var valueRef = Unmanaged<IOHIDValue>.passUnretained(
            IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, 0)
        )
        guard IOHIDDeviceGetValue(device, element, &valueRef) == kIOReturnSuccess else { return nil }
        let angle = Double(IOHIDValueGetIntegerValue(valueRef.takeUnretainedValue()))
        return (angle >= 0 && angle <= 360) ? angle : nil
    }

    deinit { stop() }
}
