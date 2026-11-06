import Foundation
import IOKit
import IOKit.hid
import RoomCore

/// Reads the Mac's built-in accelerometer.
///
/// Apple offers no public API for it on macOS (CoreMotion is iOS only), so this talks to the sensor processor's
/// HID service directly. That interface is undocumented and could change in a macOS update. Every failure path
/// ends in `.unavailable`, which simply keeps the tank still. Not suitable for the App Store.
@MainActor @Observable
final class MotionSensor {
    enum State: Equatable { case unavailable(String), ready, running }

    private(set) var state: State
    private(set) var isCalibrating = false

    /// Updated ~100 times a second. Deliberately not observed, so SwiftUI is not invalidated at sensor rate.
    @ObservationIgnored private(set) var latest = MotionSample(x: 0, y: 0, z: -1)
    @ObservationIgnored var onCalibrated: ((TiltCalibration) -> Void)?
    @ObservationIgnored private var device: IOHIDDevice?
    @ObservationIgnored private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
    @ObservationIgnored private var calibrator = TiltCalibrator()
    @ObservationIgnored private var restored: [(io_service_t, String, Any?)] = []

    var isAvailable: Bool { if case .unavailable = state { return false } else { return true } }
    var isRunning: Bool { state == .running }

    init() {
        state = Self.findService(named: "accel") != nil ? .ready : .unavailable("This Mac has no motion sensor.")
    }

    deinit { buffer.deallocate() }

    // MARK: Lifecycle

    func start() {
        guard state == .ready else { return }
        guard let service = Self.findService(named: "accel") else { state = .unavailable("The motion sensor went away."); return }
        enableDriver()
        guard let dev = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
            IOObjectRelease(service); state = .unavailable("Could not open the motion sensor."); return
        }
        IOObjectRelease(service)
        let opened = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard opened == kIOReturnSuccess else {
            state = .unavailable(opened == kIOReturnNotPermitted ? "macOS did not allow access to the motion sensor." : "Could not open the motion sensor.")
            restoreDriver(); return
        }
        device = dev
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, buffer, 4096, { ctx, _, _, _, _, report, length in
            guard let ctx, length >= 18 else { return }
            let raw = UnsafeRawPointer(report)
            let sample = MotionSample(x: Double(raw.loadUnaligned(fromByteOffset: 6, as: Int32.self)) / 65536,
                                      y: Double(raw.loadUnaligned(fromByteOffset: 10, as: Int32.self)) / 65536,
                                      z: Double(raw.loadUnaligned(fromByteOffset: 14, as: Int32.self)) / 65536)
            let sensor = Unmanaged<MotionSensor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { sensor.receive(sample) }          // scheduled on the main run loop below
        }, context)
        IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        state = .running
    }

    func stop() {
        guard state == .running, let dev = device else { return }
        IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        device = nil
        restoreDriver()
        isCalibrating = false
        state = .ready
    }

    private func receive(_ s: MotionSample) {
        latest = s
        if isCalibrating, let cal = calibrator.add(s) {
            isCalibrating = false
            onCalibrated?(cal)
        }
    }

    // MARK: Calibration

    func beginCalibration() {
        if state == .ready { start() }
        guard state == .running else { return }
        calibrator = TiltCalibrator()
        isCalibrating = true
    }

    func cancelCalibration() { isCalibrating = false }

    // MARK: IOKit

    private static func intProperty(_ s: io_service_t, _ key: String) -> Int? {
        (IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
    }
    private static func stringProperty(_ s: io_service_t, _ key: String) -> String? {
        IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
    }

    /// The caller owns (and must release) the returned service.
    private static func findService(named product: String) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if stringProperty(service, "Product") == product { return service }
            IOObjectRelease(service); service = IOIteratorNext(iterator)
        }
        return nil
    }

    /// Switches the accelerometer driver on, remembering what it was set to so `stop()` can put it back.
    private func enableDriver() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if Self.intProperty(service, "PrimaryUsagePage") == 0xFF00 && Self.intProperty(service, "PrimaryUsage") == 3 {
                IOObjectRetain(service)
                for key in ["SensorPropertyReportingState", "SensorPropertyPowerState", "ReportInterval"] {
                    let previous = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                    restored.append((service, key, previous))
                }
                IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
                IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
                IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, 10_000 as CFNumber)   // 100 Hz
            }
            IOObjectRelease(service); service = IOIteratorNext(iterator)
        }
    }

    private func restoreDriver() {
        for (service, key, previous) in restored {
            IORegistryEntrySetCFProperty(service, key as CFString, (previous ?? (key == "ReportInterval" ? 0 : 0)) as CFTypeRef)
            IOObjectRelease(service)
        }
        restored.removeAll()
    }
}
