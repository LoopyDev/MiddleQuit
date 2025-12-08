//
//  StatusItemController.swift
//  MiddleQuit
//
//  Created by Mat Trocha on 08/12/2025.
//

import Cocoa

final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private let preferences: Preferences
    private let onToggleShowIcon: (Bool) -> Void
    private let onOpenAccessibility: () -> Void
    private let onToggleLaunchAtLogin: () -> Void
    private let isLaunchAtLoginEnabled: () -> Bool
    private let onQuit: () -> Void

    init(preferences: Preferences,
         onToggleShowIcon: @escaping (Bool) -> Void,
         onOpenAccessibility: @escaping () -> Void,
         onToggleLaunchAtLogin: @escaping () -> Void,
         isLaunchAtLoginEnabled: @escaping () -> Bool,
         onQuit: @escaping () -> Void) {
        self.preferences = preferences
        self.onToggleShowIcon = onToggleShowIcon
        self.onOpenAccessibility = onOpenAccessibility
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
        self.onQuit = onQuit
        super.init()
    }

    func show() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = statusItem?.button {
                button.image = NSImage(systemSymbolName: "circle.grid.3x3", accessibilityDescription: "MiddleQuit")
                button.imagePosition = .imageOnly
            }
            rebuildMenu()
        }
    }

    func hide() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    func rebuildMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        let showIconItem = NSMenuItem(title: preferences.showStatusItem ? "Hide Menu Bar Icon" : "Show Menu Bar Icon",
                                      action: #selector(toggleShowIcon),
                                      keyEquivalent: "")
        showIconItem.target = self
        menu.addItem(showIconItem)

        // Only show Accessibility Settings if not yet enabled.
        if !DockAccessibilityHelper.isAXEnabled() {
            let axItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAX), keyEquivalent: "")
            axItem.target = self
            menu.addItem(axItem)
        }

        // Launch at Login toggle
        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit MiddleQuit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
    }

    @objc private func toggleShowIcon() {
        let newValue = !preferences.showStatusItem
        preferences.showStatusItem = newValue
        onToggleShowIcon(newValue)
        rebuildMenu()
    }

    @objc private func openAX() {
        onOpenAccessibility()
    }

    @objc private func toggleLaunchAtLogin() {
        onToggleLaunchAtLogin()
        rebuildMenu()
    }

    @objc private func quitApp() {
        onQuit()
    }
}
