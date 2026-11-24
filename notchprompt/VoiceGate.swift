//
//  VoiceGate.swift
//  notchprompt
//

import Foundation

/// Turns a stream of mic levels into a steady "is the user speaking" flag.
struct VoiceGate {
    /// Close threshold sits below open so room noise hovering at the edge doesn't flutter the gate.
    static let hysteresisDB = 6.0
    /// Gaps between words and breaths are well under a second; this keeps the script moving through them.
    static let hangoverSeconds: TimeInterval = 0.7
    /// Sensitivity 1 opens on quiet speech; sensitivity 0 needs a clearly raised voice.
    static let mostSensitiveOpenDB = -50.0
    static let leastSensitiveOpenDB = -25.0

    static func openThresholdDB(sensitivity: Double) -> Double {
        let s = min(max(sensitivity, 0), 1)
        return leastSensitiveOpenDB + s * (mostSensitiveOpenDB - leastSensitiveOpenDB)
    }

    var openThresholdDB: Double
    private(set) var isOpen = false
    private var belowCloseSince: TimeInterval?

    init(sensitivity: Double) {
        openThresholdDB = Self.openThresholdDB(sensitivity: sensitivity)
    }

    mutating func update(levelDB: Double, at time: TimeInterval) -> Bool {
        if levelDB >= openThresholdDB {
            isOpen = true
            belowCloseSince = nil
        } else if isOpen {
            if levelDB < openThresholdDB - Self.hysteresisDB {
                let since = belowCloseSince ?? time
                belowCloseSince = since
                if time - since >= Self.hangoverSeconds { isOpen = false; belowCloseSince = nil }
            } else {
                belowCloseSince = nil
            }
        }
        return isOpen
    }
}
