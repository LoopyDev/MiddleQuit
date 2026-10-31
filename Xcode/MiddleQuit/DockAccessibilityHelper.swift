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
