//
//  DockAccessibilityHelper.swift
//  MiddleQuit
//
//  Created by Mat Trocha on 08/12/2025.
//

import Cocoa
import ApplicationServices

final class DockAccessibilityHelper {

    // Dock process info
    private var dockApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
    }

    private var dockPID: pid_t? {
        dockApp?.processIdentifier
    }

    private var systemWide: AXUIElement {
        AXUIElementCreateSystemWide()
    }

    // AXIsProcessTrusted keeps answering true after the permission is removed from a running app,
    // so also ask the system for an event tap, which it refuses straight away.
    static func isAXEnabled() -> Bool {
        AXIsProcessTrusted() && canCreateEventTap()
    }

    private static func canCreateEventTap() -> Bool {
        // Listens for an event nothing sends, and is gone before it could ever be delivered
        let unusedEvent = CGEventMask(1) << CGEventMask(CGEventType.tabletProximity.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                          eventsOfInterest: unusedEvent, callback: { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }, userInfo: nil) else {
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        return true
    }

    static func requestAXPermissionIfNeeded() {
        let options: [CFString: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // Given a screen point (from CGEvent), determine if it's over a Dock tile and return PID if resolvable
    func pidForDockTile(at screenPoint: CGPoint) -> pid_t? {
        // CGEvent and AX both use top-left origin global coordinates, so no conversion is needed.
        guard let element = elementAtScreenPoint(screenPoint) else { return nil }

        // Ensure the element belongs to the Dock
        guard isElementInDock(element) else { return nil }

        // Attempt to resolve a running app PID conservatively.
        return resolveRunningAppPID(from: element)
    }

    // MARK: - AX helpers

    private func elementAtScreenPoint(_ point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success else { return nil }
        return element
    }

    private func isElementInDock(_ element: AXUIElement) -> Bool {
        guard let dockPID = dockPID else { return false }
        // Walk up the parent chain to see if any element belongs to Dock process
        var current: AXUIElement? = element
        var pid: pid_t = 0
        while let c = current {
            if AXUIElementGetPid(c, &pid) == .success, pid == dockPID {
                return true
            }
            current = parent(of: c)
        }
        return false
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var parent: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent)
        if err == .success, let p = parent {
            return (p as! AXUIElement)
        }
        return nil
    }

    // MARK: - Safer PID resolution

    private func resolveRunningAppPID(from element: AXUIElement) -> pid_t? {
        // Strategy:
        // 1) Find the application tile at or above the element. This skips folders,
        //    minimized windows and the Trash, whose titles could match a running app.
        // 2) Read the app's URL from the tile. Dock titles can differ from the app's
        //    name (e.g. "Visual Studio Code" is "Code"), so titles aren't reliable.
        // 3) Match that URL to running apps, and only if the match is unique.
        // 4) Otherwise, do nothing.

        guard let tile = applicationDockItem(containing: element),
              let url = urlAttribute(kAXURLAttribute as CFString, of: tile) else {
            return nil
        }
        return uniqueRunningAppPID(matchingBundleURL: url)
    }

    private func applicationDockItem(containing element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        while let c = current {
            if stringAttribute(kAXSubroleAttribute as CFString, of: c) == kAXApplicationDockItemSubrole {
                return c
            }
            current = parent(of: c)
        }
        return nil
    }

    private func uniqueRunningAppPID(matchingBundleURL url: URL) -> pid_t? {
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == target
        }
        if matches.count == 1, let pid = matches.first?.processIdentifier {
            return pid
        }
        return nil
    }

    private func stringAttribute(_ attr: CFString, of element: AXUIElement) -> String? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attr, &value)
        if err == .success, let s = value as? String {
            return s
        }
        return nil
    }

    private func urlAttribute(_ attr: CFString, of element: AXUIElement) -> URL? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attr, &value)
        if err == .success, let url = value as? URL {
            return url
        }
        return nil
    }
}
