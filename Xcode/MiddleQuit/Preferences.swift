//
//  Preferences.swift
//  MiddleQuit
//
//  Created by Mat Trocha on 08/12/2025.
//

import Foundation
import AppKit

final class Preferences {
    private let defaults = UserDefaults.standard
    static let showKey = "showStatusItem"
    static let threeFingerTapKey = "threeFingerTap"
    static let threeFingerEverywhereKey = "threeFingerMiddleClickEverywhere"
    private let setupGuideKey = "hasSeenSetupGuide"

    // Keys for per-action activations
    private let quitActivationKey = "quitActivation"
    private let forceActivationKey = "forceActivation"

    enum ActivationChoice: String, CaseIterable, Identifiable {
        case disabled
        case none         // Plain middle click
        case command
        case option
        case control
        case shift

        var id: String { rawValue }

        // Full descriptive label used in menus
        var menuLabel: String {
            switch self {
            case .disabled: return "Disabled"
            case .none:     return "Middle Click"
            case .command:  return "⌘ Command + click"
            case .option:   return "⌥ Option + click"
            case .control:  return "⌃ Control + click"
            case .shift:    return "⇧ Shift + click"
            }
        }
    }

    var showStatusItem: Bool {
        get {
            if defaults.object(forKey: Self.showKey) == nil {
                return true
            }
            return defaults.bool(forKey: Self.showKey)
        }
        set {
            defaults.set(newValue, forKey: Self.showKey)
        }
    }

    var threeFingerTap: Bool {
        get {
            if defaults.object(forKey: Self.threeFingerTapKey) == nil {
                return true
            }
            return defaults.bool(forKey: Self.threeFingerTapKey)
        }
        set {
            defaults.set(newValue, forKey: Self.threeFingerTapKey)
        }
    }

    var threeFingerMiddleClickEverywhere: Bool {
        get { defaults.bool(forKey: Self.threeFingerEverywhereKey) }
        set { defaults.set(newValue, forKey: Self.threeFingerEverywhereKey) }
    }

    var hasSeenSetupGuide: Bool {
        get { defaults.bool(forKey: setupGuideKey) }
        set { defaults.set(newValue, forKey: setupGuideKey) }
    }

    // Default: Quit = Middle Click, Force Quit = Option + click
    var quitActivation: ActivationChoice {
        get {
            if let raw = defaults.string(forKey: quitActivationKey),
               let v = ActivationChoice(rawValue: raw) {
                return v
            }
            return .none
        }
        set {
            defaults.set(newValue.rawValue, forKey: quitActivationKey)
        }
    }

    var forceActivation: ActivationChoice {
        get {
            if let raw = defaults.string(forKey: forceActivationKey),
               let v = ActivationChoice(rawValue: raw) {
                return v
            }
            return .option
        }
        set {
            defaults.set(newValue.rawValue, forKey: forceActivationKey)
        }
    }
}

