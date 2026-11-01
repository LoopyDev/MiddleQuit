//
//  SetupGuide.swift
//  MiddleQuit
//

import Combine
import SwiftUI

final class SetupGuideModel: ObservableObject {
    let hasTrackpad: Bool
    @Published var finished = false
    @Published var lookUpConflict = false

    init(hasTrackpad: Bool) {
        self.hasTrackpad = hasTrackpad
        refresh()
    }

    var contentSize: NSSize {
        NSSize(width: 380, height: lookUpConflict ? 440 : 330)
    }

    func refresh() {
        lookUpConflict = hasTrackpad && TrackpadSettings.threeFingerTapIsLookUp
    }
}

private struct GestureAnimation: View {
    let hasTrackpad: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4)
            let press = t < 0.18 ? 1.0 : max(0, 1 - (t - 0.18) / 0.3)
            if hasTrackpad {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .frame(width: 150, height: 96)
                    .overlay {
                        HStack(spacing: 14) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(Color.red.opacity(0.35 + 0.65 * press))
                                    .frame(width: 24, height: 24)
                                    .scaleEffect(1.15 - 0.25 * press)
                            }
                        }
                    }
            } else {
                Capsule()
                    .strokeBorder(.secondary, lineWidth: 3)
                    .frame(width: 64, height: 96)
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.red.opacity(0.35 + 0.65 * press))
                            .frame(width: 12, height: 26)
                            .offset(y: 14 + 3 * press)
                    }
            }
        }
        .frame(height: 100)
    }
}

struct SetupGuideView: View {
    @ObservedObject var model: SetupGuideModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Quit apps from the Dock")
                .font(.title2.bold())

            GestureAnimation(hasTrackpad: model.hasTrackpad)

            Text(model.hasTrackpad
                 ? "Point at an app in the Dock, then tap the trackpad with three fingers."
                 : "Point at an app in the Dock, then click the middle mouse button.")
                .multilineTextAlignment(.center)

            if model.finished {
                Label("That's it. MiddleQuit is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Try it now on an open app you don't need.")
                    .foregroundStyle(.secondary)
            }

            if model.lookUpConflict {
                VStack(spacing: 6) {
                    Text("Your three-finger tap is set to Look Up, which can get in the way. Change “Look up & data detectors” to fix it.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                    Button("Open Trackpad Settings") {
                        TrackpadSettings.openSettings()
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }

            Button(model.finished ? "Done" : "Skip") {
                onDone()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: model.contentSize.width, height: model.contentSize.height)
    }
}

// Stays above other windows, because trying the gesture means reaching for the Dock.
// The window sets its own size: letting SwiftUI drive it fights the animation and AppKit gives up.
final class SetupGuideController {
    private var window: NSWindow?
    private var model: SetupGuideModel?
    private var observers: [NSObjectProtocol] = []

    func show(hasTrackpad: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = SetupGuideModel(hasTrackpad: hasTrackpad)
        let hosting = NSHostingController(rootView: SetupGuideView(model: model) { [weak self] in
            self?.close()
        })
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(model.contentSize)
        window.title = "Welcome to MiddleQuit"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.tearDown()
            },
            // Catches the setting being fixed while the guide waits in the background
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self, weak model] _ in
                guard let model else { return }
                model.refresh()
                self?.window?.setContentSize(model.contentSize)
            },
        ]
        self.window = window
        self.model = model
    }

    func noteQuit() {
        guard let model, !model.finished else { return }
        model.finished = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.close()
        }
    }

    private func close() {
        window?.close()
    }

    private func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        window = nil
        model = nil
    }
}
