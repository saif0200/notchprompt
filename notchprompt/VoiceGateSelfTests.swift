//
//  VoiceGateSelfTests.swift
//  notchprompt
//

import Foundation

enum VoiceGateSelfTests {
    static func run() {
        var g = VoiceGate(sensitivity: 0.5)
        assert(!g.update(levelDB: -80, at: 0), "silence must not open")
        assert(!g.update(levelDB: -45, at: 0.1), "quiet noise must not open at mid sensitivity")
        assert(g.update(levelDB: -20, at: 0.2), "loud opens")

        // 0.3 s of silence is shorter than the hangover.
        assert(g.update(levelDB: -80, at: 0.3))
        assert(g.update(levelDB: -80, at: 0.5), "stays open through a 0.3 s gap")
        assert(g.update(levelDB: -20, at: 0.6))

        // Sustained silence closes after the hangover.
        assert(g.update(levelDB: -80, at: 1.0))
        assert(g.update(levelDB: -80, at: 1.6))
        assert(!g.update(levelDB: -80, at: 1.8), "closes after hangover")

        let sensitive = VoiceGate.openThresholdDB(sensitivity: 1)
        let mid = VoiceGate.openThresholdDB(sensitivity: 0.5)
        let strict = VoiceGate.openThresholdDB(sensitivity: 0)
        assert(sensitive < mid && mid < strict, "higher sensitivity must lower the threshold")
    }
}
