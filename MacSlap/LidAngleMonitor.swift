import Foundation
import IOKit
import IOKit.hid

class LidAngleMonitor {
    var angleThreshold: Double = 5.0  // Used for UI display only now
    /// Called every poll with (currentAngle, angularSpeed) where speed is degrees/second
    var onMovement: ((Double, Double) -> Void)?

    private var timer: Timer?
    private var isRunning = false
    private var previousAngle: Double?
    private var pollInterval: TimeInterval = 0.05  // 20Hz for smooth tracking
    private(set) var sensorAvailable = false

    // HID sensor
    private var hidManager: IOHIDManager?
    private var angleElement: IOHIDElement?
    private var angleDevice: IOHIDDevice?

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if setupHIDSensor() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.timer = Timer.scheduledTimer(withTimeInterval: self.pollInterval, repeats: true) { [weak self] _ in
                    self?.pollAngle()
                }
            }
            sensorAvailable = true
            print("[MacSlap] Lid angle monitoring started (SPU sensor, 20Hz)")
        } else {
            sensorAvailable = false
            print("[MacSlap] Lid angle sensor not found on this Mac")
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
        previousAngle = nil
        print("[MacSlap] Lid angle monitoring stopped")
    }

    private func pollAngle() {
        guard let angle = readLidAngle() else { return }

        if let prev = previousAngle {
            let delta = angle - prev
            // Sensor reports integers, so ignore ±1 degree noise
            if abs(delta) >= 2 {
                let speed = abs(delta) / pollInterval
                onMovement?(angle, speed)
                previousAngle = angle
            }
            // Don't update previousAngle on noise — only on real movement
        } else {
            previousAngle = angle
        }
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
                let usagePage = IOHIDElementGetUsagePage(elem)
                let usage = IOHIDElementGetUsage(elem)
                let logMax = IOHIDElementGetLogicalMax(elem)

                if usagePage == 0x20 && usage == 0x47F && logMax == 360 {
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
        let result = IOHIDDeviceGetValue(device, element, &valueRef)
        guard result == kIOReturnSuccess else { return nil }

        let angle = Double(IOHIDValueGetIntegerValue(valueRef.takeUnretainedValue()))
        return (angle >= 0 && angle <= 360) ? angle : nil
    }

    deinit {
        stop()
    }
}
