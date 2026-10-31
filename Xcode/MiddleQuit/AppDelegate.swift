import Cocoa
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    private let eventTapManager = EventTapManager()
    private let dockHelper = DockAccessibilityHelper()
    private let quitController = QuitController()
    let launchAtLogin = LaunchAtLoginManager()
    private var statusController: StatusItemController!

    private var axPollingTimer: Timer?
    private var hasStartedEventTap = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController(
            preferences: preferences,
            onToggleShowIcon: { [weak self] show in
                self?.applyStatusItemVisibility(show: show)
            },
            onOpenAccessibility: { [weak self] in
                self?.openAccessibilitySettings()
                self?.beginAXTrustPolling(interval: 0.5)
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

        NSApp.setActivationPolicy(.accessory)
        applyStatusItemVisibility(show: preferences.showStatusItem)
        ensureAccessibilityAndStart()

        if !DockAccessibilityHelper.isAXEnabled() {
            // Defer until launch has finished, as the alert runs modally
            DispatchQueue.main.async { [weak self] in
                self?.promptForAccessibilityAndAutoStart()
            }
        }
    }

    // MARK: - Accessibility flow

    private func promptForAccessibilityAndAutoStart() {
        // Keep watching even if the alert is cancelled, so enabling it later still starts the app
        beginAXTrustPolling(interval: 0.5)

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission"
        alert.informativeText = "MiddleQuit needs Accessibility permission to handle mouse clicks. macOS will show a prompt. After allowing, MiddleQuit will become active automatically."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        DockAccessibilityHelper.requestAXPermissionIfNeeded()
        beginAXTrustPolling(interval: 0.5, fallbackAfter: 30.0)
    }

    // Polls until Accessibility is enabled. The fallback alert is offered once, and polling continues after it.
    private func beginAXTrustPolling(interval: TimeInterval, fallbackAfter: TimeInterval? = nil) {
        axPollingTimer?.invalidate()

        if DockAccessibilityHelper.isAXEnabled() {
            ensureAccessibilityAndStart()
            return
        }

        var deadline = fallbackAfter.map { Date().addingTimeInterval($0) }

        axPollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { return }
            if DockAccessibilityHelper.isAXEnabled() {
                timer.invalidate()
                self.axPollingTimer = nil
                self.ensureAccessibilityAndStart()
            } else if let fallbackDate = deadline, Date() >= fallbackDate {
                deadline = nil
                self.offerAccessibilitySettingsFallback()
            }
        }

        RunLoop.main.add(axPollingTimer!, forMode: .common)
    }

    private func offerAccessibilitySettingsFallback() {
        let fallback = NSAlert()
        fallback.messageText = "Accessibility Not Enabled"
        fallback.informativeText = "You can enable Accessibility for MiddleQuit in System Settings. Would you like to open it now?"
        fallback.alertStyle = .warning
        fallback.addButton(withTitle: "Open Settings")
        fallback.addButton(withTitle: "Cancel")
        let result = fallback.runModal()
        guard result == .alertFirstButtonReturn else { return }

        openAccessibilitySettings()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Event tap lifecycle

    private func ensureAccessibilityAndStart() {
        guard DockAccessibilityHelper.isAXEnabled() else {
            return
        }
        guard !hasStartedEventTap else {
            return
        }
        hasStartedEventTap = true

        statusController.rebuildMenu()

        eventTapManager.start(
            resolveAction: { [weak self] flags in
                guard let self else { return nil }

                func effectiveModifier(from flags: NSEvent.ModifierFlags) -> Preferences.ActivationChoice {
                    if flags.contains(.command) { return .command }
                    if flags.contains(.option)  { return .option }
                    if flags.contains(.control) { return .control }
                    if flags.contains(.shift)   { return .shift }
                    return .none
                }

                let eff = effectiveModifier(from: flags)
                let quitChoice = self.preferences.quitActivation
                let forceChoice = self.preferences.forceActivation

                if quitChoice == forceChoice, quitChoice != .disabled {
                    return nil
                }

                if eff == quitChoice, quitChoice != .disabled {
                    return .quit
                }
                if eff == forceChoice, forceChoice != .disabled {
                    return .forceQuit
                }
                return nil
            },
            handler: { [weak self] point, action in
                guard let self else { return false }
                if let pid = self.dockHelper.pidForDockTile(at: point) {
                    switch action {
                    case .quit:
                        self.quitController.gracefulQuit(pid: pid)
                    case .forceQuit:
                        self.quitController.forceQuit(pid: pid)
                    }
                    return self.eventTapManager.canSwallow
                }
                return false
            }
        )
    }

    func applyStatusItemVisibility(show: Bool) {
        if show {
            statusController.show()
        } else {
            statusController.hide()
        }
    }

    // Opening the app again is the way back to Settings when the menu bar icon is hidden
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController.openSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        axPollingTimer?.invalidate()
        eventTapManager.stop()
    }
}
