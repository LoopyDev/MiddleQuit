//
//  MiddleQuitApp.swift
//  MiddleQuit
//
//  Created by Mat Trocha on 08/12/2025.
//

import SwiftUI
import AppKit

@main
struct MiddleQuitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No default window at launch; keep only a hidden Settings scene.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let eventTapManager = EventTapManager()
    private let dockHelper = DockAccessibilityHelper()
    private let quitController = QuitController()
    private let launchAtLogin = LaunchAtLoginManager()
    private var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(
            preferences: preferences,
            onToggleShowIcon: { [weak self] show in
                self?.applyStatusItemVisibility(show: show)
            },
            onOpenAccessibility: { [weak self] in
                self?.presentAXRelaunchDialogThenOpenSettings()
            },
            onToggleLaunchAtLogin: { [weak self] in
                guard let self else { return }
                let result = self.launchAtLogin.toggle()
                switch result {
                case .requiresApproval:
                    self.launchAtLogin.openLoginItemsSettingsIfAvailable()
                case .failed(let error):
                    let alert = NSAlert()
                    alert.messageText = "Couldn’t Update Login Item"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                case .unavailable:
                    let alert = NSAlert()
                    alert.messageText = "Not Supported on This macOS Version"
                    alert.informativeText = "Enabling launch at login without a helper app requires macOS 13 or later."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                default:
                    break
                }
            },
            isLaunchAtLoginEnabled: { [weak self] in
                return self?.launchAtLogin.isEnabled ?? false
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        applyStatusItemVisibility(show: preferences.showStatusItem)
        ensureAccessibilityAndStart()
    }

    private func presentAXRelaunchDialogThenOpenSettings() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "MiddleQuit needs Accessibility permission to handle mouse clicks. After enabling the permission in System Settings, please quit and relaunch the app."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else { return }

        // Trigger the standard AX prompt (if needed) and open the proper System Settings pane.
        DockAccessibilityHelper.requestAXPermissionIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func ensureAccessibilityAndStart() {
        guard DockAccessibilityHelper.isAXEnabled() else {
            // AX not enabled; wait for user to enable and relaunch.
            return
        }

        // Start the event tap.
        eventTapManager.start { [weak self] point in
            guard let self else { return false }
            if let pid = self.dockHelper.pidForDockTile(at: point) {
                self.quitController.gracefulQuit(pid: pid)
                return self.eventTapManager.canSwallow
            }
            return false
        }
    }

    private func applyStatusItemVisibility(show: Bool) {
        if show {
            statusController.show()
            NSApp.setActivationPolicy(.accessory) // menu bar only
        } else {
            statusController.hide()
            NSApp.setActivationPolicy(.prohibited) // fully background
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager.stop()
    }
}
