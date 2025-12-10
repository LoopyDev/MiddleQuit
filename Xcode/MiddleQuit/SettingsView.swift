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

    @State private var showStatusItem: Bool

    // Per-action activations
    @State private var quitActivation: Preferences.ActivationChoice
    @State private var forceActivation: Preferences.ActivationChoice

    init(preferences: Preferences, onToggleShowIcon: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.onToggleShowIcon = onToggleShowIcon
        _showStatusItem = State(initialValue: preferences.showStatusItem)
        _quitActivation = State(initialValue: preferences.quitActivation)
        _forceActivation = State(initialValue: preferences.forceActivation)
    }

    var body: some View {
        Form {
            // GENERAL
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    // Option label not bold
                    Toggle("Show menu bar icon", isOn: Binding(
                        get: { showStatusItem },
                        set: { newValue in
                            showStatusItem = newValue
                            preferences.showStatusItem = newValue
                            onToggleShowIcon(newValue)
                        }
                    ))
                }
            } header: {
                // Heading bold
                Text("General")
                    .font(.headline)
            }

            // ACTIVATION
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    // Option label not bold
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
                    // Option label not bold
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
                // Heading bold, with extra separation from General
                Text("Activation")
                    .font(.headline)
                    .padding(.top, 16)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 520, height: 280)
    }

    // Build options list excluding the other picker's current selection,
    // but keep the current selection so the Picker remains valid even if prefs conflict.
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

    // Labels shown in the menus
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
    return SettingsView(preferences: prefs, onToggleShowIcon: { _ in })
}
