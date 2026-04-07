import Foundation
import IOKit
import IOKit.hid

class LidAngleMonitor {
    var angleThreshold: Double = 5.0
    /// Called with (currentAngle, smoothedSpeed) where speed is degrees/second
    var onMovement: ((Double, Double) -> Void)?
    /// Called when movement has fully stopped
    var onMovementStopped: (() -> Void)?

    private var timer: Timer?
    private var isRunning = false
    private var previousAngle: Double?
    private var pollInterval: TimeInterval = 0.05  // 20Hz
    private(set) var sensorAvailable = false

    // Smoothing: track recent angle samples to calculate activity
    private var angleSamples: [(time: TimeInterval, angle: Double)] = []
    private let sampleWindowDuration: TimeInterval = 0.6  // Look back 600ms
    private var lastMovingTime: TimeInterval = 0
    private let stopDelay: TimeInterval = 0.5  // Wait 500ms of no movement before stopping
    private var wasMoving = false

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
                    self?.pollAngle()
                }
            }
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
        angleSamples.removeAll()
        wasMoving = false
        print("[MacSlap] Lid angle monitoring stopped")
    }

    private func pollAngle() {
        guard let angle = readLidAngle() else { return }
        let now = ProcessInfo.processInfo.systemUptime

        // Add sample to the rolling window
        angleSamples.append((time: now, angle: angle))

        // Trim old samples outside the window
        angleSamples.removeAll { now - $0.time > sampleWindowDuration }

        guard angleSamples.count >= 2 else {
            previousAngle = angle
            return
        }

        // Calculate total movement in the window (sum of absolute deltas)
        var totalMovement: Double = 0
        for i in 1..<angleSamples.count {
            let delta = abs(angleSamples[i].angle - angleSamples[i - 1].angle)
            // Ignore single-degree noise between consecutive samples
            if delta >= 2 {
                totalMovement += delta
            }
        }

        // Calculate the time span of the window
        let windowSpan = angleSamples.last!.time - angleSamples.first!.time
        guard windowSpan > 0 else { return }

        // Speed = total movement over the window duration
        let speed = totalMovement / windowSpan

        // Minimum speed threshold to count as "moving" (filters sensor noise)
        let isMoving = speed > 8.0  // At least 8 deg/s of real movement

        if isMoving {
            lastMovingTime = now
            wasMoving = true
            onMovement?(angle, speed)
        } else if wasMoving {
            // Still within the stop delay? Keep reporting at decreasing speed
            let timeSinceMoved = now - lastMovingTime
            if timeSinceMoved < stopDelay {
                // Report with decaying speed for smooth fade
                let decay = 1.0 - (timeSinceMoved / stopDelay)
                let fadingSpeed = speed + 15.0 * decay  // Keep some volume during fade
                onMovement?(angle, fadingSpeed)
            } else {
                // Fully stopped
                wasMoving = false
                onMovementStopped?()
            }
        }

        previousAngle = angle
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
