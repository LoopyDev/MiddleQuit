//
//  ThreeFingerTapRecognizer.swift
//  MiddleQuit
//

import Foundation

// Turns raw trackpad contacts into three-finger taps. Knows nothing about the hardware.
struct ThreeFingerTapRecognizer {
    struct Contact {
        let id: Int32
        let x: Float      // 0...1 across the trackpad
        let y: Float
    }

    static let maxDuration = 0.35     // longer than this is a rest or a press, not a tap
    static let maxTravel: Float = 0.06

    private var startTime: Double?
    private var startPositions: [Int32: (x: Float, y: Float)] = [:]
    private var peakCount = 0
    private var cancelled = false

    mutating func cancel() {
        cancelled = true
    }

    // Feed every frame, including empty ones. Returns true on the frame that completes a tap.
    mutating func update(contacts: [Contact], time: Double) -> Bool {
        guard !contacts.isEmpty else {
            defer { reset() }
            guard let start = startTime else { return false }
            return !cancelled && peakCount == 3 && time - start <= Self.maxDuration
        }

        if startTime == nil {
            startTime = time
        }
        peakCount = max(peakCount, contacts.count)

        for contact in contacts {
            if let origin = startPositions[contact.id] {
                let dx = contact.x - origin.x, dy = contact.y - origin.y
                if dx * dx + dy * dy > Self.maxTravel * Self.maxTravel {
                    cancelled = true      // a swipe or scroll
                }
            } else {
                startPositions[contact.id] = (contact.x, contact.y)
            }
        }
        return false
    }

    private mutating func reset() {
        startTime = nil
        startPositions = [:]
        peakCount = 0
        cancelled = false
    }
}
