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
    private var handler: MiddleClickHandler?

    // Track whether to swallow the matching mouseUp for a handled click
    private var swallowNextOtherMouseUp = false

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
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
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

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        handler = nil
        swallowNextOtherMouseUp = false
        canSwallow = false
        actionResolver = nil
    }
}

