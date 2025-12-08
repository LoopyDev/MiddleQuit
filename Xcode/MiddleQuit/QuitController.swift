//
//  QuitController.swift
//  MiddleQuit
//
//  Created by Mat Trocha on 08/12/2025.
//

import Cocoa

final class QuitController {
    func gracefulQuit(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.terminate()
    }
}
