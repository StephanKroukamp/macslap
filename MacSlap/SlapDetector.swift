import Foundation
import IOKit
import IOKit.hid

/// Detects physical slaps on the MacBook using the built-in accelerometer
/// (Apple SPU sensor, Bosch BMI286 IMU). Reads raw HID reports at ~100Hz
/// and detects sudden acceleration spikes above the sensitivity threshold.
/// Requires Apple Silicon M1 Pro or later.
class SlapDetector {
    var sensitivity: Double = 2.5  // g-force threshold above baseline ~1.0g
    var cooldown: Double = 0.5
    var onSlap: ((Double) -> Void)?

    private var lastSlapTime: Date = .distantPast
    private var isRunning = false
    private(set) var sensorAvailable = false

    // HID accelerometer
    private var hidManager: IOHIDManager?
    private var reportBuffer = [UInt8](repeating: 0, count: 64)

    // Baseline tracking (rolling average of magnitude)
    private var baselineMagnitude: Double = 1.0
    private let baselineAlpha: Double = 0.01  // Slow-moving average

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if setupAccelerometer() {
            sensorAvailable = true
            print("[MacSlap] Slap detection started (accelerometer)")
        } else {
            sensorAvailable = false
            print("[MacSlap] Accelerometer not found — slap detection unavailable")
        }
    }

    func stop() {
        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            hidManager = nil
        }
        isRunning = false
        baselineMagnitude = 1.0
        print("[MacSlap] Slap detection stopped")
    }

    // MARK: - Accelerometer Setup

    private func setupAccelerometer() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match the Apple SPU accelerometer: UsagePage 0xFF00, Usage 3
        let matchDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: 0xFF00,
            kIOHIDDeviceUsageKey as String: 3,
            kIOHIDTransportKey as String: "SPU"
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return false }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = devices.first else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return false
        }

        // Register for raw HID reports
        // Data format: 22-byte reports, X/Y/Z as Int32 LE at offsets 6, 10, 14
        // Divide by 65536 to get g-force
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            &reportBuffer,
            reportBuffer.count,
            { context, result, sender, type, reportID, report, reportLength in
                guard let ctx = context else { return }
                let detector = Unmanaged<SlapDetector>.fromOpaque(ctx).takeUnretainedValue()
                detector.handleAccelReport(report: report, length: Int(reportLength))
            },
            context
        )

        self.hidManager = manager
        return true
    }

    // MARK: - Process Accelerometer Data

    private func handleAccelReport(report: UnsafeMutablePointer<UInt8>, length: Int) {
        guard length >= 18 else { return }

        // Parse X, Y, Z as Int32 little-endian at byte offsets 6, 10, 14
        let x = readInt32LE(report, offset: 6)
        let y = readInt32LE(report, offset: 10)
        let z = readInt32LE(report, offset: 14)

        let gx = Double(x) / 65536.0
        let gy = Double(y) / 65536.0
        let gz = Double(z) / 65536.0
        let magnitude = sqrt(gx * gx + gy * gy + gz * gz)

        // Update baseline (slow-moving average of magnitude)
        baselineMagnitude = baselineMagnitude * (1.0 - baselineAlpha) + magnitude * baselineAlpha

        // Detect impact: sudden deviation from baseline
        // At rest, magnitude ≈ 1.0g (gravity). A slap causes a spike.
        let deviation = abs(magnitude - baselineMagnitude)

        // Map sensitivity slider (0.5 = very sensitive, 8.0 = very insensitive)
        // to a g-force threshold
        let threshold = sensitivity * 0.02  // 0.5 → 0.01g, 2.5 → 0.05g, 8.0 → 0.16g

        if deviation > threshold {
            let slapMagnitude = deviation / threshold  // Normalized force
            triggerSlap(magnitude: min(slapMagnitude, 10.0))
        }
    }

    private func readInt32LE(_ ptr: UnsafeMutablePointer<UInt8>, offset: Int) -> Int32 {
        return Int32(ptr[offset])
            | (Int32(ptr[offset + 1]) << 8)
            | (Int32(ptr[offset + 2]) << 16)
            | (Int32(ptr[offset + 3]) << 24)
    }

    // MARK: - Trigger

    private func triggerSlap(magnitude: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastSlapTime) > cooldown else { return }
        lastSlapTime = now

        DispatchQueue.main.async { [weak self] in
            self?.onSlap?(magnitude)
        }
    }

    deinit {
        stop()
    }
}
