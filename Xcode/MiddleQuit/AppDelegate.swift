import Cocoa
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    private let eventTapManager = EventTapManager()
    private let dockHelper = DockAccessibilityHelper()
    private let quitController = QuitController()
    private let trackpad = TrackpadMonitor()
    private let setupGuide = SetupGuideController()
    let launchAtLogin = LaunchAtLoginManager()
    private var statusController: StatusItemController!

    private var axPollingTimer: Timer?
    private var axLossTimer: Timer?
    private var axLossObserver: NSObjectProtocol?
    private let requestAccessibilityArgument = "--request-accessibility"
    private var hasStartedEventTap = false

    // Another middle-click app and our own tap can both report the same gesture. Only a repeat from
    // the other source is a duplicate, so quitting several apps quickly is never held up.
    private enum QuitSource { case click, tap }
    private var lastQuit: (pid: pid_t, source: QuitSource, time: Date)?
    private let repeatWindow: TimeInterval = 0.6
    // The Dock closes up after a quit, so a late duplicate could land on the next app along
    private let otherSourceWindow: TimeInterval = 0.3

    func applicationDidFinishLaunching(_ notification: Notification) {
        quitOlderCopies()

        statusController = StatusItemController(
            preferences: preferences,
            onToggleShowIcon: { [weak self] show in
                self?.applyStatusItemVisibility(show: show)
            },
            onOpenAccessibility: { [weak self] in
                self?.openAccessibilitySettings()
                self?.beginAXTrustPolling(interval: 0.5)
            },
            onShowSetupGuide: { [weak self] in
                self?.showSetupGuide()
            },
            onToggleThreeFingerTap: { [weak self] in
                self?.applyThreeFingerTap()
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
                guard let self else { return }
                if CommandLine.arguments.contains(self.requestAccessibilityArgument) {
                    self.requestAccessibility()
                } else {
                    self.promptForAccessibilityAndAutoStart()
                }
            }
        }
    }

    // Two copies, say an installed one and a build from elsewhere, would both act on every click.
    // The one opened last is the one that was wanted.
    private func quitOlderCopies() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current
        let older = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { other in
            guard other != me, let theirs = other.launchDate, let mine = me.launchDate else { return false }
            return theirs < mine
        }
        for copy in older {
            copy.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            older.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
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

        requestAccessibility()
    }

    private func requestAccessibility() {
        clearStaleAccessibilityEntries()
        DockAccessibilityHelper.requestAXPermissionIfNeeded()
        beginAXTrustPolling(interval: 0.5, fallbackAfter: 30.0)
    }

    // An entry left by a differently signed build looks switched on but does nothing, and stays in
    // the list beside the real one. Only called when we have no permission, so nothing working is lost.
    private func clearStaleAccessibilityEntries() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", bundleID]
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        guard (try? reset.run()) != nil else { return }
        reset.waitUntilExit()
    }

    // A running app can't ask for a permission it has lost: macOS shows no prompt and doesn't re-add it.
    // A fresh launch can, and macOS adds the app back to the list if it was removed.
    private func offerToRestoreAccessibility() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "MiddleQuit Lost Accessibility Permission"
        alert.informativeText = "MiddleQuit has paused and can't quit apps from the Dock until the permission is back. To restore it, MiddleQuit will restart and macOS will ask you to allow it."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore Permission")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()

        // It may have been turned back on while the alert was open
        guard response == .alertFirstButtonReturn, !DockAccessibilityHelper.isAXEnabled() else { return }
        relaunchRequestingAccessibility()
    }

    private func relaunchRequestingAccessibility() {
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.5; /usr/bin/open -n \"$0\" --args \"$1\"", Bundle.main.bundlePath, requestAccessibilityArgument]
        guard (try? relaunch.run()) != nil else {
            openAccessibilitySettings()
            return
        }
        NSApp.terminate(nil)
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

        trackpad.onTap = { [weak self] in
            self?.handleThreeFingerTap()
        }
        trackpad.onThreeFingersChanged = { [weak self] down in
            self?.eventTapManager.setThreeFingersDown(down)
        }
        eventTapManager.onTapDisabled = { [weak self] in
            self?.stopIfAccessibilityLost()
        }
        eventTapManager.isThreeFingerClick = { [weak self] in
            guard let self, self.preferences.threeFingerTap, !TrackpadSettings.threeFingerDragEnabled else { return false }
            return self.trackpad.threeFingersDown
        }
        eventTapManager.didThreeFingerClick = { [weak self] in
            self?.trackpad.cancelTap()
        }
        eventTapManager.convertsThreeFingerClicks = { [weak self] in
            self?.preferences.threeFingerMiddleClickEverywhere ?? false
        }

        eventTapManager.start(
            resolveAction: { [weak self] flags in
                self?.resolveAction(flags: flags)
            },
            handler: { [weak self] point, action in
                guard let self, self.quitDockTile(at: point, action: action, source: .click) else { return false }
                return self.eventTapManager.canSwallow
            }
        )
        applyThreeFingerTap()
        watchForLostAccessibility()

        if !preferences.hasSeenSetupGuide {
            preferences.hasSeenSetupGuide = true
            showSetupGuide()
        }
    }

    // A running event tap without Accessibility can hang the clicks it watches, so as soon as
    // the permission goes, get out of the way and wait for it to come back.
    private func watchForLostAccessibility() {
        axLossObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.stopIfAccessibilityLost()
            // The setting takes a moment to change after the notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.stopIfAccessibilityLost()
            }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.stopIfAccessibilityLost()
        }
        RunLoop.main.add(timer, forMode: .common)
        axLossTimer = timer
    }

    private func stopWatchingAccessibility() {
        axLossTimer?.invalidate()
        axLossTimer = nil
        if let axLossObserver {
            DistributedNotificationCenter.default().removeObserver(axLossObserver)
        }
        axLossObserver = nil
    }

    private func stopIfAccessibilityLost() {
        guard hasStartedEventTap, !DockAccessibilityHelper.isAXEnabled() else { return }
        stopWatchingAccessibility()
        trackpad.stop()
        eventTapManager.stop()
        hasStartedEventTap = false
        statusController.rebuildMenu()
        beginAXTrustPolling(interval: 0.5)
        DispatchQueue.main.async { [weak self] in
            self?.offerToRestoreAccessibility()
        }
    }

    private func resolveAction(flags: NSEvent.ModifierFlags) -> EventTapManager.ResolvedAction? {
        func effectiveModifier(from flags: NSEvent.ModifierFlags) -> Preferences.ActivationChoice {
            if flags.contains(.command) { return .command }
            if flags.contains(.option)  { return .option }
            if flags.contains(.control) { return .control }
            if flags.contains(.shift)   { return .shift }
            return .none
        }

        let eff = effectiveModifier(from: flags)
        let quitChoice = preferences.quitActivation
        let forceChoice = preferences.forceActivation

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
    }

    // Returns true if the point was over a running app's Dock tile
    private func quitDockTile(at point: CGPoint, action: EventTapManager.ResolvedAction, source: QuitSource) -> Bool {
        guard let pid = dockHelper.pidForDockTile(at: point) else { return false }

        if let lastQuit {
            let elapsed = Date().timeIntervalSince(lastQuit.time)
            if (lastQuit.source != source && elapsed < otherSourceWindow) || (lastQuit.pid == pid && elapsed < repeatWindow) {
                return true
            }
        }
        lastQuit = (pid, source, Date())

        switch action {
        case .quit:
            quitController.gracefulQuit(pid: pid)
        case .forceQuit:
            quitController.forceQuit(pid: pid)
        }
        setupGuide.noteQuit()
        return true
    }

    // MARK: - Three-finger tap

    func applyThreeFingerTap() {
        guard hasStartedEventTap else { return }
        if preferences.threeFingerTap {
            trackpad.start()
        } else {
            trackpad.stop()
        }
    }

    private func handleThreeFingerTap() {
        guard let point = CGEvent(source: nil)?.location else { return }

        if preferences.threeFingerMiddleClickEverywhere {
            eventTapManager.postMiddleClick(at: point)
            return
        }

        let flags = NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
        if let action = resolveAction(flags: flags) {
            _ = quitDockTile(at: point, action: action, source: .tap)
        }
    }

    private func showSetupGuide() {
        setupGuide.show(hasTrackpad: TrackpadMonitor.hasTrackpad && preferences.threeFingerTap)
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
        stopWatchingAccessibility()
        trackpad.stop()
        eventTapManager.stop()
    }
}
