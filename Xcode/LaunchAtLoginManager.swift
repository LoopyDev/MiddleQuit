//
//  LaunchAtLoginManager.swift
//  MiddleQuit
//
//  Created by Mat Trocha on 08/12/2025.
//

import Foundation
import ServiceManagement
import AppKit

final class LaunchAtLoginManager {

    enum Result {
        case enabled
        case disabled
        case requiresApproval
        case failed(Error)
        case unavailable
    }

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }

    @discardableResult
    func toggle() -> Result {
        guard #available(macOS 13.0, *) else {
            return .unavailable
        }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                return .disabled
            } else {
                try SMAppService.mainApp.register()
                switch SMAppService.mainApp.status {
                case .enabled:
                    return .enabled
                case .requiresApproval:
                    return .requiresApproval
                default:
                    return .enabled // best-effort; status can settle shortly after
                }
            }
        } catch {
            return .failed(error)
        }
    }

    func openLoginItemsSettingsIfAvailable() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
