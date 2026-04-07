import Foundation
import IOKit
import IOKit.hid

class LidAngleMonitor {
    var angleThreshold: Double = 5.0
    /// Called every tick with (angle, isMoving, speed)
    var onTick: ((Double, Bool, Double) -> Void)?

    private var timer: Timer?
    private var isRunning = false
    private(set) var sensorAvailable = false

    private let pollInterval: TimeInterval = 0.05  // 20Hz

    // Sliding window of recent angle readings
    private var samples: [(time: TimeInterval, angle: Double)] = []
    private let windowDuration: TimeInterval = 0.5  // 500ms lookback

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
        samples.removeAll()
        print("[MacSlap] Lid angle monitoring stopped")
    }

    private func poll() {
        guard let angle = readLidAngle() else { return }
        let now = ProcessInfo.processInfo.systemUptime

        // Add to sliding window
        samples.append((time: now, angle: angle))

        // Trim samples older than the window
        samples.removeAll { now - $0.time > windowDuration }

        guard samples.count >= 2 else { return }

        // Movement = range of angles in the window
        let angles = samples.map { $0.angle }
        let minAngle = angles.min()!
        let maxAngle = angles.max()!
        let range = maxAngle - minAngle

        // If the angle has varied by 2+ degrees in the window, lid is moving
        // This catches direction reversals because the window spans both directions
        let isMoving = range >= 2.0

        // Speed estimate: range / window time span
        let timeSpan = samples.last!.time - samples.first!.time
        let speed = timeSpan > 0 ? range / timeSpan : 0

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
