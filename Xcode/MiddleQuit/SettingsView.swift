//
//  SettingsView.swift
//  MiddleQuit
//
//  Created by Mat Trocha on 08/12/2025.
//

import SwiftUI

struct SettingsView: View {
    let preferences: Preferences
    let onToggleShowIcon: (Bool) -> Void

    // New for launch at login
    let isLaunchAtLoginEnabled: () -> Bool
    let onToggleLaunchAtLogin: () -> Void

    @State private var showStatusItem: Bool

    // Per-action activations
    @State private var quitActivation: Preferences.ActivationChoice
    @State private var forceActivation: Preferences.ActivationChoice

    @State private var launchAtLoginEnabled: Bool

    init(
        preferences: Preferences,
        onToggleShowIcon: @escaping (Bool) -> Void,
        isLaunchAtLoginEnabled: @escaping () -> Bool,
        onToggleLaunchAtLogin: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.onToggleShowIcon = onToggleShowIcon
        self.isLaunchAtLoginEnabled = isLaunchAtLoginEnabled
        self.onToggleLaunchAtLogin = onToggleLaunchAtLogin
        _showStatusItem = State(initialValue: preferences.showStatusItem)
        _quitActivation = State(initialValue: preferences.quitActivation)
        _forceActivation = State(initialValue: preferences.forceActivation)
        // Query at init; update as user toggles
        _launchAtLoginEnabled = State(initialValue: isLaunchAtLoginEnabled())
    }

    var body: some View {
        Form {
            // GENERAL
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Show menu bar icon", isOn: Binding(
                        get: { showStatusItem },
                        set: { newValue in
                            showStatusItem = newValue
                            preferences.showStatusItem = newValue
                            onToggleShowIcon(newValue)
                        }
                    ))
                    // --- Launch at Login Toggle ---
                    Toggle("Launch at Login", isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { newValue in
                            onToggleLaunchAtLogin()
                            launchAtLoginEnabled = isLaunchAtLoginEnabled()
                        }
                    ))
                }
            } header: {
                Text("General")
                    .font(.headline)
            }

            // ACTIVATION
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quit")
                    Picker("", selection: Binding(
                        get: { quitActivation },
                        set: { newValue in
                            quitActivation = newValue
                            preferences.quitActivation = newValue
                        }
                    )) {
                        ForEach(optionsExcluding(otherSelection: forceActivation, currentSelection: quitActivation), id: \.self) { choice in
                            Text(label(for: choice)).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Force Quit")
                    Picker("", selection: Binding(
                        get: { forceActivation },
                        set: { newValue in
                            forceActivation = newValue
                            preferences.forceActivation = newValue
                        }
                    )) {
                        ForEach(optionsExcluding(otherSelection: quitActivation, currentSelection: forceActivation), id: \.self) { choice in
                            Text(label(for: choice)).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320, alignment: .leading)
                }
            } header: {
                Text("Activation")
                    .font(.headline)
                    .padding(.top, 16)
            }
        }
        // Increased vertical padding for top and bottom
        .padding(.vertical, 20)
        .frame(width: 396, height: 236)
        .onAppear {
            launchAtLoginEnabled = isLaunchAtLoginEnabled()
        }
    }

    private func optionsExcluding(
        otherSelection: Preferences.ActivationChoice,
        currentSelection: Preferences.ActivationChoice
    ) -> [Preferences.ActivationChoice] {
        if otherSelection == .disabled || otherSelection == currentSelection {
            return Array(Preferences.ActivationChoice.allCases)
        } else {
            return Preferences.ActivationChoice.allCases.filter { $0 != otherSelection }
        }
    }

    private func label(for choice: Preferences.ActivationChoice) -> String {
        switch choice {
        case .disabled: return "Disabled"
        case .none:     return "Middle Click"
        case .command:  return "⌘ Command + click"
        case .option:   return "⌥ Option + click"
        case .control:  return "⌃ Control + click"
        case .shift:    return "⇧ Shift + click"
        }
    }
}

#Preview {
    let prefs = Preferences()
    SettingsView(
        preferences: prefs,
        onToggleShowIcon: { _ in },
        isLaunchAtLoginEnabled: { false },
        onToggleLaunchAtLogin: {}
    )
}
