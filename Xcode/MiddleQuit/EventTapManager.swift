//
//  EventTapManager.swift
//  MiddleQuit
//
//  Created by Mat Trocha on 08/12/2025.
//

import Cocoa

final class EventTapManager {
    enum MouseButton: Int64 {
        case left = 0
        case right = 1
        case middle = 2
    }

    enum ResolvedAction {
        case quit
        case forceQuit
    }

    // Return true to consume the event (prevent Dock from seeing it)
    typealias MiddleClickHandler = (_ locationInScreen: CGPoint, _ action: ResolvedAction) -> Bool

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Left clicks get their own tap, enabled only while three fingers are down. Every click on the Mac
    // waits on an enabled tap, so if the permission ever goes, an always-on one would stop all clicking.
    private var clickTap: CFMachPort?
    private var clickRunLoopSource: CFRunLoopSource?
    private var threeFingersDown = false
    var onTapDisabled: (() -> Void)?
    private var handler: MiddleClickHandler?

    // Three-finger physical clicks arrive as left clicks, so these tell the tap when to treat one as a middle click
    var isThreeFingerClick: (() -> Bool)?
    var didThreeFingerClick: (() -> Void)?
    var convertsThreeFingerClicks: (() -> Bool)?

    // With our tap acting as a middle click, an app like MiddleClick answers the same gesture with one of its own.
    // Whichever arrives second is dropped. Clicks from the same source are always kept, however fast.
    private var lastMiddleClick: (ours: Bool, time: Date)?
    private let duplicateClickWindow: TimeInterval = 0.2
    private let ownClickMarker: Int64 = 0x4D51    // "MQ"

    // Track whether to swallow the matching mouseUp for a handled click
    private var swallowNextOtherMouseUp = false
    private var swallowNextLeftMouseUp = false
    private var convertNextLeftMouseUp = false

    // Public read-only: whether this tap can swallow events (depends on creation mode)
    private(set) var canSwallow = false

    // Provider to resolve action based on current modifiers. Return nil for "no action".
    private var actionResolver: ((NSEvent.ModifierFlags) -> ResolvedAction?)?

    func start(resolveAction: @escaping (NSEvent.ModifierFlags) -> ResolvedAction?,
               handler: @escaping MiddleClickHandler) {
        self.handler = handler
        self.actionResolver = resolveAction

        // Build mask in a way that works across SDKs (UInt vs UInt64)
        let downShift = CGEventMask(CGEventType.otherMouseDown.rawValue)
        let upShift   = CGEventMask(CGEventType.otherMouseUp.rawValue)
        let downBit: CGEventMask = CGEventMask(1) << downShift
        let upBit: CGEventMask   = CGEventMask(1) << upShift
        let mask: CGEventMask = downBit | upBit

        // Try session default (captures synthetic events, can swallow)
        if createTap(tap: .cgSessionEventTap, options: .defaultTap, eventsOfInterest: mask) {
            canSwallow = true
            print("EventTap: using cgSessionEventTap (default) — can swallow")
        }
        // Else try HID default (captures hardware events, can swallow)
        else if createTap(tap: .cghidEventTap, options: .defaultTap, eventsOfInterest: mask) {
            canSwallow = true
            print("EventTap: using cghidEventTap (default) — can swallow")
        }
        // Else, try session listen-only (observe only, cannot swallow)
        else if createTap(tap: .cgSessionEventTap, options: .listenOnly, eventsOfInterest: mask) {
            canSwallow = false
            print("EventTap: using cgSessionEventTap (listenOnly) — cannot swallow")
        } else {
            print("Failed to create any event tap. Check that App Sandbox is OFF and Accessibility is enabled, then relaunch the app.")
        }
        createClickTap()
    }

    private func createClickTap() {
        guard canSwallow else { return }
        let mask = (CGEventMask(1) << CGEventMask(CGEventType.leftMouseDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.leftMouseUp.rawValue))
        guard let tapPort = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                guard type == .leftMouseDown || type == .leftMouseUp else {
                    return Unmanaged.passUnretained(event)
                }
                let result = manager.handleLeftClick(type: type, event: event)
                manager.updateClickTap()
                return result
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return
        }
        CGEvent.tapEnable(tap: tapPort, enable: false)
        clickTap = tapPort
        clickRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapPort, 0)
        if let clickRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), clickRunLoopSource, .commonModes)
        }
    }

    func setThreeFingersDown(_ down: Bool) {
        threeFingersDown = down
        updateClickTap()
    }

    // Stays on past the fingers lifting if a click is still waiting for its mouse-up
    private func updateClickTap() {
        guard let clickTap else { return }
        CGEvent.tapEnable(tap: clickTap, enable: threeFingersDown || swallowNextLeftMouseUp || convertNextLeftMouseUp)
    }

    private func createTap(tap: CGEventTapLocation, options: CGEventTapOptions, eventsOfInterest: CGEventMask) -> Bool {
        guard let tapPort = CGEvent.tapCreate(
            tap: tap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: eventsOfInterest,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()

                // Re-enable tap if system disabled it
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap, DockAccessibilityHelper.isAXEnabled() {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    } else {
                        DispatchQueue.main.async { manager.onTapDisabled?() }
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .otherMouseDown || type == .otherMouseUp else {
                    return Unmanaged.passUnretained(event)
                }

                let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)

                if type == .otherMouseDown {
                    guard buttonNumber == MouseButton.middle.rawValue else {
                        return Unmanaged.passUnretained(event)
                    }

                    if manager.isDuplicateMiddleClick(event) {
                        manager.swallowNextOtherMouseUp = true
                        return nil
                    }

                    let loc = event.location

                    // CGEvent.flags.rawValue is UInt64; NSEvent.ModifierFlags.RawValue is UInt.
                    let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

                    if let action = manager.actionResolver?(flags) {
                        if let shouldConsume = manager.handler?(loc, action), shouldConsume, manager.canSwallow {
                            manager.swallowNextOtherMouseUp = true
                            return nil // swallow down
                        }
                    }
                    return Unmanaged.passUnretained(event)
                } else {
                    // Mouse up events
                    if manager.swallowNextOtherMouseUp && manager.canSwallow {
                        manager.swallowNextOtherMouseUp = false
                        return nil
                    }
                    return Unmanaged.passUnretained(event)
                }
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            return false
        }

        eventTap = tapPort
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tapPort, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tapPort, enable: true)
            return true
        }
        return false
    }

    private func isDuplicateMiddleClick(_ event: CGEvent) -> Bool {
        let ours = event.getIntegerValueField(.eventSourceUserData) == ownClickMarker
        defer { lastMiddleClick = (ours, Date()) }
        guard canSwallow, convertsThreeFingerClicks?() == true, let last = lastMiddleClick else { return false }
        return last.ours != ours && Date().timeIntervalSince(last.time) < duplicateClickWindow
    }

    private func handleLeftClick(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .leftMouseUp {
            if swallowNextLeftMouseUp {
                swallowNextLeftMouseUp = false
                return nil
            }
            if convertNextLeftMouseUp {
                convertNextLeftMouseUp = false
                convertToMiddleClick(event, type: .otherMouseUp)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isThreeFingerClick?() == true else {
            return Unmanaged.passUnretained(event)
        }
        didThreeFingerClick?()

        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        if let action = actionResolver?(flags), handler?(event.location, action) == true, canSwallow {
            swallowNextLeftMouseUp = true
            return nil
        }
        if convertsThreeFingerClicks?() == true {
            convertNextLeftMouseUp = true
            convertToMiddleClick(event, type: .otherMouseDown)
        }
        return Unmanaged.passUnretained(event)
    }

    private func convertToMiddleClick(_ event: CGEvent, type: CGEventType) {
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: MouseButton.middle.rawValue)
    }

    // Goes through the tap like any other middle click, so the Dock is handled in one place
    func postMiddleClick(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            let click = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .center)
            click?.flags = CGEventSource.flagsState(.combinedSessionState)
            click?.setIntegerValueField(.eventSourceUserData, value: ownClickMarker)
            click?.post(tap: .cghidEventTap)
        }
    }

    func stop() {
        for tap in [eventTap, clickTap].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        for source in [runLoopSource, clickRunLoopSource].compactMap({ $0 }) {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        clickRunLoopSource = nil
        eventTap = nil
        clickTap = nil
        threeFingersDown = false
        handler = nil
        swallowNextOtherMouseUp = false
        swallowNextLeftMouseUp = false
        convertNextLeftMouseUp = false
        canSwallow = false
        actionResolver = nil
    }
}

