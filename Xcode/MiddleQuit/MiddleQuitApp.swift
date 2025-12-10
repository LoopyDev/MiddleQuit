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
        Settings {
            SettingsView(
                preferences: appDelegate.preferences,
                onToggleShowIcon: { show in
                    appDelegate.applyStatusItemVisibility(show: show)
                },
                isLaunchAtLoginEnabled: {
                    appDelegate.launchAtLogin.isEnabled
                },
                onToggleLaunchAtLogin: {
                    _ = appDelegate.launchAtLogin.toggle()
                }
            )
        }
        .windowResizability(.contentSize)
    }
}

// ... rest unchanged ...
