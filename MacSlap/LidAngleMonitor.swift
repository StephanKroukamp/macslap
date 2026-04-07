import Foundation
import IOKit
import IOKit.hid

class LidAngleMonitor {
    var angleThreshold: Double = 5.0
    /// Called every tick with (angle, delta)
    var onTick: ((Double, Double) -> Void)?

    private var timer: Timer?
    private var isRunning = false
    private(set) var sensorAvailable = false
    private let pollInterval: TimeInterval = 0.02  // 50Hz for fast response

    private var lastAngle: Double?
    private var lastDelta: Double = 0

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
            print("[MacSlap] Lid angle monitoring started (50Hz)")
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
        lastDelta = 0
        print("[MacSlap] Lid angle monitoring stopped")
    }

    private func poll() {
        guard let angle = readLidAngle() else { return }

        if let prev = lastAngle {
            let delta = angle - prev

            if abs(delta) >= 1 {
                // Filter noise: ±1 jitter alternates direction every tick.
                // Real movement has same-direction consecutive deltas,
                // OR a direction change with magnitude >= 2 (genuine reversal).
                let isNoise = abs(delta) == 1
                    && lastDelta != 0
                    && (delta > 0) != (lastDelta > 0)  // Alternating sign

                if !isNoise {
                    lastDelta = delta
                    lastAngle = angle
                    onTick?(angle, delta)
                    return
                }
            }

            // No significant change this tick
            onTick?(angle, 0)
        } else {
            lastAngle = angle
        }
    }

    // MARK: - HID Sensor

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
