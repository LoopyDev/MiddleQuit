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

    static func isAXEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAXPermissionIfNeeded() {
        let options: [CFString: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // Given a screen point (from CGEvent), determine if it's over a Dock tile and return PID if resolvable
    func pidForDockTile(at screenPoint: CGPoint) -> pid_t? {
        // Try both coordinate variants: as-is and flipped, to handle differences across macOS versions.
        let candidates = [screenPoint, convertToAXScreenPoint(screenPoint)]

        for point in candidates {
            guard let element = elementAtScreenPoint(point) else { continue }

            // Ensure the element belongs to the Dock
            guard isElementInDock(element) else { continue }

            // Attempt to resolve a running app PID conservatively.
            if let pid = resolveRunningAppPID(from: element) {
                return pid
            }
        }

        return nil
    }

    // MARK: - Coordinate conversion

    private func convertToAXScreenPoint(_ cgPoint: CGPoint) -> CGPoint {
        // AX APIs typically use a top-left origin global coordinate space,
        // while many Cocoa points are bottom-left. Flip Y using the union of all screens.
        let union = NSScreen.screens.reduce(into: CGRect.null) { partialResult, screen in
            partialResult = partialResult.union(screen.frame)
        }
        return CGPoint(x: cgPoint.x, y: union.maxY - cgPoint.y)
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
        // 1) Try to get a precise title from the element.
        // 2) If empty, check immediate children for a title (common pattern for Dock items).
        // 3) Match that title to running apps by exact equality, and only if the match is unique.
        // 4) Otherwise, do nothing.

        if let title = nonEmptyTitle(of: element),
           let pid = uniqueRunningAppPID(matchingExactTitle: title) {
            return pid
        }

        if let children = arrayAttribute(kAXChildrenAttribute as CFString, of: element) as? [AXUIElement] {
            for child in children {
                if let t = nonEmptyTitle(of: child),
                   let pid = uniqueRunningAppPID(matchingExactTitle: t) {
                    return pid
                }
            }
        }

        // No confident resolution
        return nil
    }

    private func nonEmptyTitle(of element: AXUIElement) -> String? {
        if let s = stringAttribute(kAXTitleAttribute as CFString, of: element), !s.isEmpty {
            return s
        }
        return nil
    }

    private func uniqueRunningAppPID(matchingExactTitle title: String) -> pid_t? {
        let matches = NSWorkspace.shared.runningApplications.filter { $0.localizedName == title }
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

    private func arrayAttribute(_ attr: CFString, of element: AXUIElement) -> [AnyObject]? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attr, &value)
        if err == .success, let arr = value as? [AnyObject] {
            return arr
        }
        return nil
    }
}
