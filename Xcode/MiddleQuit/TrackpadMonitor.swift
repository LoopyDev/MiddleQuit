//
//  TrackpadMonitor.swift
//  MiddleQuit
//

import Cocoa

// Trackpad settings that affect three-finger gestures, read from System Settings' own preferences.
enum TrackpadSettings {
    private static let domains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]

    private static func value(_ key: String) -> Int {
        for domain in domains {
            CFPreferencesAppSynchronize(domain as CFString)
            if let number = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber, number.intValue != 0 {
                return number.intValue
            }
        }
        return 0
    }

    // "Look up & data detectors" set to "Tap with Three Fingers"
    static var threeFingerTapIsLookUp: Bool { value("TrackpadThreeFingerTapGesture") == 2 }

    // With three-finger drag on, a three-finger press starts a drag, so it can't count as a click
    static var threeFingerDragEnabled: Bool { value("TrackpadThreeFingerDrag") != 0 }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// Reads finger contacts through MultitouchSupport, a private framework. It's loaded at runtime so that if
// a macOS update removes it, three-finger taps go quiet and the rest of the app carries on.
final class TrackpadMonitor {
    private typealias DeviceRef = UnsafeMutableRawPointer
    private typealias ContactCallback = @convention(c) (DeviceRef?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterCallback = @convention(c) (DeviceRef, ContactCallback) -> Void
    private typealias DeviceStart = @convention(c) (DeviceRef, Int32) -> Void
    private typealias DeviceStop = @convention(c) (DeviceRef) -> Void

    // Matches the framework's per-finger record
    private struct Touch {
        var frame: Int32, timestamp: Double
        var identifier: Int32, state: Int32, fingerID: Int32, handID: Int32
        var x: Float, y: Float, velocityX: Float, velocityY: Float
        var size: Float, unused1: Int32
        var angle: Float, majorAxis: Float, minorAxis: Float
        var absoluteX: Float, absoluteY: Float, absoluteVelocityX: Float, absoluteVelocityY: Float
        var unused2: Int32, unused3: Int32, density: Float
    }
    private static let touching: ClosedRange<Int32> = 3...5     // made, held, breaking contact

    private struct API {
        let createList: CreateList
        let register: RegisterCallback
        let unregister: RegisterCallback
        let start: DeviceStart
        let stop: DeviceStop

        init?() {
            guard MemoryLayout<Touch>.stride == 96,
                  let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
                  let createList = dlsym(handle, "MTDeviceCreateList"),
                  let register = dlsym(handle, "MTRegisterContactFrameCallback"),
                  let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
                  let start = dlsym(handle, "MTDeviceStart"),
                  let stop = dlsym(handle, "MTDeviceStop") else {
                return nil
            }
            self.createList = unsafeBitCast(createList, to: CreateList.self)
            self.register = unsafeBitCast(register, to: RegisterCallback.self)
            self.unregister = unsafeBitCast(unregister, to: RegisterCallback.self)
            self.start = unsafeBitCast(start, to: DeviceStart.self)
            self.stop = unsafeBitCast(stop, to: DeviceStop.self)
        }
    }

    private static let api = API()
    private static weak var active: TrackpadMonitor?

    private static func deviceCount() -> Int {
        guard let list = api?.createList()?.takeRetainedValue() else { return 0 }
        return CFArrayGetCount(list)
    }

    static var hasTrackpad: Bool { deviceCount() > 0 }

    var onTap: (() -> Void)?
    var onThreeFingersChanged: ((Bool) -> Void)?

    private var devices: CFArray?
    private var deviceWatch: Timer?
    private var wakeObserver: NSObjectProtocol?

    // Contact frames arrive on the framework's own thread
    private let lock = NSLock()
    private var recognizer = ThreeFingerTapRecognizer()
    private var fingerCount = 0

    private var isRunning: Bool { deviceWatch != nil }

    // True while exactly three fingers rest on the trackpad
    var threeFingersDown: Bool {
        lock.lock(); defer { lock.unlock() }
        return fingerCount == 3
    }

    // The fingers pressed down, so this gesture is a click and shouldn't also count as a tap
    func cancelTap() {
        lock.lock(); defer { lock.unlock() }
        recognizer.cancel()
    }

    func start() {
        guard Self.api != nil, !isRunning else { return }
        Self.active = self
        attach()

        // Devices go quiet across sleep, and a Magic Trackpad can arrive at any time
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reattach()
        }
        deviceWatch = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Self.deviceCount() != (self.devices.map(CFArrayGetCount) ?? 0) {
                self.reattach()
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        deviceWatch?.invalidate()
        deviceWatch = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        detach()
    }

    private func reattach() {
        detach()
        attach()
    }

    private func forEachDevice(_ body: (DeviceRef) -> Void) {
        guard let devices else { return }
        for i in 0..<CFArrayGetCount(devices) {
            if let device = CFArrayGetValueAtIndex(devices, i) {
                body(UnsafeMutableRawPointer(mutating: device))
            }
        }
    }

    private func attach() {
        guard let api = Self.api else { return }
        devices = api.createList()?.takeRetainedValue()
        forEachDevice { device in
            api.register(device, Self.contactFrame)
            api.start(device, 0)
        }
    }

    private func detach() {
        guard let api = Self.api else { return }
        forEachDevice { device in
            api.unregister(device, Self.contactFrame)
            api.stop(device)
        }
        devices = nil
        lock.lock(); defer { lock.unlock() }
        recognizer = ThreeFingerTapRecognizer()
        fingerCount = 0
    }

    private static let contactFrame: ContactCallback = { _, touches, count, timestamp, _ in
        guard let monitor = TrackpadMonitor.active else { return 0 }
        var contacts: [ThreeFingerTapRecognizer.Contact] = []
        if let touches {
            let records = touches.bindMemory(to: Touch.self, capacity: Int(count))
            for i in 0..<Int(count) where touching.contains(records[i].state) {
                contacts.append(.init(id: records[i].identifier, x: records[i].x, y: records[i].y))
            }
        }
        monitor.process(contacts, time: timestamp)
        return 0
    }

    private func process(_ contacts: [ThreeFingerTapRecognizer.Contact], time: Double) {
        lock.lock()
        let wereThree = fingerCount == 3
        fingerCount = contacts.count
        let areThree = fingerCount == 3
        let tapped = recognizer.update(contacts: contacts, time: time)
        lock.unlock()

        if wereThree != areThree {
            DispatchQueue.main.async { [weak self] in
                self?.onThreeFingersChanged?(areThree)
            }
        }
        if tapped {
            DispatchQueue.main.async { [weak self] in
                self?.onTap?()
            }
        }
    }
}
