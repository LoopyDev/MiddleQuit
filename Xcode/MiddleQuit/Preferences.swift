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
    private let showKey = "showStatusItem"

    var showStatusItem: Bool {
        get {
            // Default to true (visible)
            if defaults.object(forKey: showKey) == nil {
                return true
            }
            return defaults.bool(forKey: showKey)
        }
        set {
            defaults.set(newValue, forKey: showKey)
        }
    }
}

