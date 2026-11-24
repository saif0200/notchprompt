//
//  PrompterModel.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import Foundation
import Combine
import CoreGraphics
import AppKit
import SwiftUI

@MainActor
final class PrompterModel: ObservableObject {
    enum ScrollMode: String, CaseIterable {
        case infinite
        case stopAtEnd
    }
    
    enum CountdownBehavior: String, CaseIterable {
        case always
        case freshStartOnly
        case never
        
        var label: String {
            switch self {
            case .always:
                return "Always"
            case .freshStartOnly:
                return "Fresh start only"
            case .never:
                return "Never"
            }
        }
    }

    enum VoiceMode: String, CaseIterable {
        case off
        case startStop
        case followWords
    }

    static let shared = PrompterModel()

    @Published var script: String = """
Paste your script here.

Tip: Use the menu bar icon to start/pause or reset the scroll.
""" { didSet { speechFollower.setScript(script) } }

    @Published var isRunning: Bool = false { didSet { syncVoiceMonitor() } }
    @Published var manualScrollEnabled: Bool = false
    @Published var isOverlayVisible: Bool = true
    @Published var privacyModeEnabled: Bool = true
    @Published private(set) var hasStartedSession: Bool = false
    @Published private(set) var isCountingDown: Bool = false { didSet { syncVoiceMonitor() } }
    @Published var countdownSeconds: Int = 3
    @Published var countdownBehavior: CountdownBehavior = .freshStartOnly
    @Published private(set) var countdownRemaining: Int = 0
    @Published private(set) var didReachEndInStopMode: Bool = false

    @Published var voiceMode: VoiceMode = .off {
        didSet {
            if voiceMode != .off { lastActiveVoiceMode = voiceMode }
            syncVoiceMonitor()
        }
    }
    private(set) var lastActiveVoiceMode: VoiceMode = .startStop
    @Published var voiceSensitivity: Double = 0.5 { didSet { voiceMonitor.sensitivity = voiceSensitivity } }
    // Voice glow
    @Published var glowEnabled: Bool = Defaults.glowEnabled
    @Published var glowColor: Color = Defaults.glowColor
    @Published var glowWidth: Double = Defaults.glowWidth
    @Published var glowIntensity: Double = Defaults.glowIntensity
    @Published var glowRestingLine: Bool = Defaults.glowRestingLine
    // Follow my words
    @Published var followGlideSpeed: Double = Defaults.followGlideSpeed
    @Published var followJumpBoost: Double = Defaults.followJumpBoost
    @Published var followReadingLine: Double = Defaults.followReadingLine
    // Layout and controls
    @Published var textSideMargin: Double = Defaults.textSideMargin
    @Published var textTopOffset: Double = Defaults.textTopOffset
    @Published var autoHideControls: Bool = Defaults.autoHideControls
    @Published var pauseOnHover: Bool = Defaults.pauseOnHover

    @Published private(set) var voiceIsSpeaking: Bool = false
    @Published private(set) var voiceLevel: Double = 0
    @Published private(set) var voicePermissionDenied: Bool = false
    @Published private(set) var voiceUnavailable: Bool = false
    @Published private(set) var speechPermissionDenied: Bool = false
    @Published private(set) var speechUnavailable: Bool = false
    @Published private(set) var followProgress: Double = 0

    /// True when the script may scroll. Fails open if the mic is denied so the prompter still works.
    var isVoiceGateOpen: Bool {
        voiceMode == .off || voicePermissionDenied || voiceUnavailable || voiceIsSpeaking
    }

    /// Follow mode only drives the scroll when speech can work; otherwise it falls back to the voice gate.
    var isFollowingWords: Bool {
        voiceMode == .followWords && !voicePermissionDenied && !voiceUnavailable
            && !speechPermissionDenied && !speechUnavailable
    }

    private let voiceMonitor = AudioLevelMonitor()
    private let speechFollower = SpeechFollower()

    // Visual / behavior tuning
    @Published var speedPointsPerSecond: Double = Defaults.speed
    @Published var fontSize: Double = Defaults.fontSize
    @Published var overlayWidth: Double = Defaults.overlayWidth
    @Published var overlayHeight: Double = Defaults.overlayHeight
    // Deprecated user setting: keep as a fixed constant unless changed explicitly in code.
    @Published var backgroundOpacity: Double = 1.0
    @Published var scrollMode: ScrollMode = .infinite
    /// 0 means "auto" (prefer built-in display)
    @Published var selectedScreenID: CGDirectDisplayID = 0
    // Fraction of the viewport height to fade at top and bottom.
    let edgeFadeFraction: Double = 0.20

    // Used to signal an immediate reset to the scrolling view.
    @Published private(set) var resetToken: UUID = UUID()
    @Published private(set) var jumpBackToken: UUID = UUID()
    @Published private(set) var jumpBackDistancePoints: CGFloat = 0
    @Published private(set) var manualScrollToken: UUID = UUID()
    @Published private(set) var manualScrollDeltaPoints: CGFloat = 0
    private(set) var savedScrollPhaseForResume: CGFloat?

    private var countdownTask: Task<Void, Never>?
    private var shouldUseCountdownOnNextStart: Bool = true

    static let speedRange: ClosedRange<Double> = 10...300
    static let speedStep: Double = 5
    static let speedPresetSlow: Double = 55
    static let speedPresetNormal: Double = 85
    static let speedPresetFast: Double = 125

    // Single source of truth for tunable defaults, used by property initialisers and "Reset all".
    private enum Defaults {
        static let glowEnabled = true
        static let glowColor = Color(red: 0.62, green: 0.24, blue: 0.08)
        static let glowWidth = 1.0
        static let glowIntensity = 1.0
        static let glowRestingLine = true
        static let followGlideSpeed = 5.0
        static let followJumpBoost = 3.5
        static let followReadingLine = 0.0
        static let textSideMargin = 34.0
        static let textTopOffset = 38.0
        static let autoHideControls = true
        // Hover pausing was hard-wired off in the overlay, so off keeps today's behaviour.
        static let pauseOnHover = false
        static let speed = 80.0
        static let fontSize = 22.0
        static let overlayWidth = 600.0
        static let overlayHeight = 150.0
    }

    private enum DefaultsKey {
        static let glowEnabled = "glowEnabled"
        static let glowColor = "glowColorRGB"
        static let glowWidth = "glowWidth"
        static let glowIntensity = "glowIntensity"
        static let glowRestingLine = "glowRestingLine"
        static let followGlideSpeed = "followGlideSpeed"
        static let followJumpBoost = "followJumpBoost"
        static let followReadingLine = "followReadingLine"
        static let textSideMargin = "textSideMargin"
        static let textTopOffset = "textTopOffset"
        static let autoHideControls = "autoHideControls"
        static let pauseOnHover = "pauseOnHover"

        static let hasSavedSession = "hasSavedSession"
        static let script = "script"
        static let isRunning = "isRunning"
        static let isOverlayVisible = "isOverlayVisible"
        static let privacyModeEnabled = "privacyModeEnabled"
        static let speed = "speedPointsPerSecond"
        static let fontSize = "fontSize"
        static let overlayWidth = "overlayWidth"
        static let overlayHeight = "overlayHeight"
        static let countdownSeconds = "countdownSeconds"
        static let countdownBehavior = "countdownBehavior"
        static let scrollMode = "scrollMode"
        static let selectedScreenID = "selectedScreenID"
        static let voiceActivationEnabled = "voiceActivationEnabled"
        static let voiceMode = "voiceMode"
        static let voiceSensitivity = "voiceSensitivity"
    }

    private init() {
        voiceMonitor.$isSpeaking.assign(to: &$voiceIsSpeaking)
        voiceMonitor.$level.assign(to: &$voiceLevel)
        voiceMonitor.$permissionDenied.assign(to: &$voicePermissionDenied)
        voiceMonitor.$unavailable.assign(to: &$voiceUnavailable)
        speechFollower.$progress.assign(to: &$followProgress)
        speechFollower.$permissionDenied.assign(to: &$speechPermissionDenied)
        speechFollower.$unavailable.assign(to: &$speechUnavailable)
        let sink = speechFollower.sink
        voiceMonitor.bufferConsumer = { sink.append($0) }
    }

    deinit {
        countdownTask?.cancel()
    }

    func pasteScript(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let wasEmpty = script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        script = text
        if wasEmpty {
            hasStartedSession = true
        }
    }

    func resetScroll() {
        didReachEndInStopMode = false
        shouldUseCountdownOnNextStart = true
        savedScrollPhaseForResume = nil
        speechFollower.reset()
        resetToken = UUID()
    }

    func saveScrollPhaseForResume(_ phase: CGFloat) {
        savedScrollPhaseForResume = phase
    }

    func jumpBack(seconds: Double = 5) {
        // In follow mode the view snaps back to the spoken position, so this control restarts from the top instead.
        if isFollowingWords { resetScroll(); return }
        guard seconds > 0 else { return }
        didReachEndInStopMode = false
        jumpBackDistancePoints = CGFloat(speedPointsPerSecond * seconds)
        jumpBackToken = UUID()
    }

    func switchPlaybackModeFromOverlayControl() {
        if isRunning || isCountingDown {
            stop()
            manualScrollEnabled = true
            didReachEndInStopMode = false
            hasStartedSession = true
            shouldUseCountdownOnNextStart = false
            return
        }

        manualScrollEnabled = false
        start()
    }

    func handleManualScroll(deltaPoints: CGFloat) {
        guard abs(deltaPoints) > 0.01 else { return }

        if !manualScrollEnabled {
            manualScrollEnabled = true
        }

        if isRunning || isCountingDown {
            stop()
        }

        didReachEndInStopMode = false
        hasStartedSession = true
        shouldUseCountdownOnNextStart = false
        manualScrollDeltaPoints = deltaPoints
        manualScrollToken = UUID()
    }

    func toggleRunning() {
        if isRunning || isCountingDown {
            stop()
        } else {
            start()
        }
    }

    func start() {
        if isRunning || isCountingDown {
            return
        }

        manualScrollEnabled = false

        if scrollMode == .stopAtEnd, didReachEndInStopMode {
            // Keyboard "start" from end should restart from the top without requiring manual reset.
            resetScroll()
        }

        let delay = max(0, countdownSeconds)
        let shouldRunCountdown: Bool
        switch countdownBehavior {
        case .always:
            shouldRunCountdown = delay > 0
        case .freshStartOnly:
            shouldRunCountdown = delay > 0 && shouldUseCountdownOnNextStart
        case .never:
            shouldRunCountdown = false
        }
        
        guard shouldRunCountdown else {
            beginRunningNow()
            return
        }
        
        beginCountdown(seconds: delay)
    }

    func markReachedEndInStopMode() {
        guard scrollMode == .stopAtEnd else { return }
        didReachEndInStopMode = true
        stop()
    }

    func setScrollMode(_ newMode: ScrollMode) {
        // Entire transition is deferred to avoid publishing inside SwiftUI view updates.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let oldMode = self.scrollMode
            guard oldMode != newMode else { return }
            let wasTerminalStopState = (oldMode == .stopAtEnd && self.didReachEndInStopMode)

            self.scrollMode = newMode

            if newMode == .infinite {
                self.didReachEndInStopMode = false
                if wasTerminalStopState {
                    self.hasStartedSession = true
                    self.isCountingDown = false
                    self.countdownRemaining = 0
                    self.countdownTask?.cancel()
                    self.countdownTask = nil
                    self.shouldUseCountdownOnNextStart = false
                    self.isRunning = true
                }
            }
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        isCountingDown = false
        countdownRemaining = 0
        isRunning = false
    }

    func setSpeed(_ value: Double) {
        speedPointsPerSecond = clampedSpeed(value)
    }

    func adjustSpeed(delta: Double) {
        let newValue = speedPointsPerSecond + delta
        setSpeed(newValue)
    }

    func applySpeedPreset(_ preset: Double) {
        setSpeed(preset)
    }

    var estimatedReadDuration: TimeInterval {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let words = max(1, trimmed.split(whereSeparator: \.isWhitespace).count)
        // Approximation: 160 words/minute baseline adjusted by current speed.
        let baselineWPM = 160.0
        let speedFactor = speedPointsPerSecond / Self.speedPresetNormal
        let adjustedWPM = max(60, baselineWPM * speedFactor)
        let minutes = Double(words) / adjustedWPM
        return minutes * 60
    }

    func formattedEstimatedReadDuration() -> String {
        let duration = Int(round(estimatedReadDuration))
        guard duration > 0 else { return "~0s" }
        if duration < 60 {
            return "~\(duration)s"
        }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "~%dm %02ds", minutes, seconds)
    }

    /// Any tuning change; the app delegate debounces this into a save.
    var tuningChanged: AnyPublisher<Void, Never> {
        Publishers.MergeMany(
            $glowEnabled.map { _ in () }.eraseToAnyPublisher(),
            $glowColor.map { _ in () }.eraseToAnyPublisher(),
            $glowWidth.map { _ in () }.eraseToAnyPublisher(),
            $glowIntensity.map { _ in () }.eraseToAnyPublisher(),
            $glowRestingLine.map { _ in () }.eraseToAnyPublisher(),
            $followGlideSpeed.map { _ in () }.eraseToAnyPublisher(),
            $followJumpBoost.map { _ in () }.eraseToAnyPublisher(),
            $followReadingLine.map { _ in () }.eraseToAnyPublisher(),
            $textSideMargin.map { _ in () }.eraseToAnyPublisher(),
            $textTopOffset.map { _ in () }.eraseToAnyPublisher(),
            $autoHideControls.map { _ in () }.eraseToAnyPublisher(),
            $pauseOnHover.map { _ in () }.eraseToAnyPublisher()
        ).eraseToAnyPublisher()
    }

    func resetGlowColor() { glowColor = Defaults.glowColor }

    func resetTuningToDefaults() {
        glowEnabled = Defaults.glowEnabled
        glowColor = Defaults.glowColor
        glowWidth = Defaults.glowWidth
        glowIntensity = Defaults.glowIntensity
        glowRestingLine = Defaults.glowRestingLine
        followGlideSpeed = Defaults.followGlideSpeed
        followJumpBoost = Defaults.followJumpBoost
        followReadingLine = Defaults.followReadingLine
        textSideMargin = Defaults.textSideMargin
        textTopOffset = Defaults.textTopOffset
        autoHideControls = Defaults.autoHideControls
        pauseOnHover = Defaults.pauseOnHover
        speedPointsPerSecond = Defaults.speed
        fontSize = Defaults.fontSize
        overlayWidth = Defaults.overlayWidth
        overlayHeight = Defaults.overlayHeight
    }

    func loadFromDefaults() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.hasSavedSession) else {
            return
        }

        if let savedScript = defaults.string(forKey: DefaultsKey.script) {
            script = savedScript
        }

        privacyModeEnabled = defaults.object(forKey: DefaultsKey.privacyModeEnabled) as? Bool ?? privacyModeEnabled
        isOverlayVisible = defaults.object(forKey: DefaultsKey.isOverlayVisible) as? Bool ?? true
        // Never auto-start on launch; require explicit user start each session.
        isRunning = false
        isCountingDown = false
        countdownRemaining = 0
        hasStartedSession = false
        shouldUseCountdownOnNextStart = true
        speedPointsPerSecond = clampedSpeed(defaults.object(forKey: DefaultsKey.speed) as? Double ?? speedPointsPerSecond)
        fontSize = clamp(defaults.object(forKey: DefaultsKey.fontSize) as? Double ?? fontSize, lower: 12, upper: 40)
        overlayWidth = clamp(defaults.object(forKey: DefaultsKey.overlayWidth) as? Double ?? overlayWidth, lower: 400, upper: 1200)
        overlayHeight = clamp(defaults.object(forKey: DefaultsKey.overlayHeight) as? Double ?? overlayHeight, lower: 120, upper: 300)
        // Opacity UI has been removed; always render fully opaque by default.
        backgroundOpacity = 1.0
        defaults.removeObject(forKey: "backgroundOpacity")
        countdownSeconds = Int(clamp(Double(defaults.object(forKey: DefaultsKey.countdownSeconds) as? Int ?? countdownSeconds), lower: 0, upper: 10))
        if let rawValue = defaults.string(forKey: DefaultsKey.countdownBehavior),
           let savedBehavior = CountdownBehavior(rawValue: rawValue) {
            countdownBehavior = savedBehavior
        } else {
            countdownBehavior = .freshStartOnly
        }
        if let rawValue = defaults.string(forKey: DefaultsKey.scrollMode),
           let savedMode = ScrollMode(rawValue: rawValue) {
            scrollMode = savedMode
        } else {
            scrollMode = .infinite
        }
        selectedScreenID = CGDirectDisplayID(defaults.object(forKey: DefaultsKey.selectedScreenID) as? UInt32 ?? 0)
        if let rawValue = defaults.string(forKey: DefaultsKey.voiceMode), let saved = VoiceMode(rawValue: rawValue) {
            voiceMode = saved
        } else {
            voiceMode = defaults.bool(forKey: DefaultsKey.voiceActivationEnabled) ? .startStop : .off
        }
        voiceSensitivity = clamp(defaults.object(forKey: DefaultsKey.voiceSensitivity) as? Double ?? voiceSensitivity, lower: 0, upper: 1)

        func double(_ key: String, _ fallback: Double, _ lower: Double, _ upper: Double) -> Double {
            clamp(defaults.object(forKey: key) as? Double ?? fallback, lower: lower, upper: upper)
        }
        glowEnabled = defaults.object(forKey: DefaultsKey.glowEnabled) as? Bool ?? glowEnabled
        if let rgb = defaults.array(forKey: DefaultsKey.glowColor) as? [Double], rgb.count == 3 {
            glowColor = Color(red: rgb[0], green: rgb[1], blue: rgb[2])
        }
        glowWidth = double(DefaultsKey.glowWidth, glowWidth, 0.5, 2.0)
        glowIntensity = double(DefaultsKey.glowIntensity, glowIntensity, 0.4, 1.6)
        glowRestingLine = defaults.object(forKey: DefaultsKey.glowRestingLine) as? Bool ?? glowRestingLine
        followGlideSpeed = double(DefaultsKey.followGlideSpeed, followGlideSpeed, 2, 12)
        followJumpBoost = double(DefaultsKey.followJumpBoost, followJumpBoost, 1, 6)
        followReadingLine = double(DefaultsKey.followReadingLine, followReadingLine, 0, 1)
        textSideMargin = double(DefaultsKey.textSideMargin, textSideMargin, 16, 90)
        textTopOffset = double(DefaultsKey.textTopOffset, textTopOffset, 30, 70)
        autoHideControls = defaults.object(forKey: DefaultsKey.autoHideControls) as? Bool ?? autoHideControls
        pauseOnHover = defaults.object(forKey: DefaultsKey.pauseOnHover) as? Bool ?? pauseOnHover
    }

    func saveToDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.hasSavedSession)
        defaults.set(script, forKey: DefaultsKey.script)
        defaults.set(isRunning, forKey: DefaultsKey.isRunning)
        defaults.set(isOverlayVisible, forKey: DefaultsKey.isOverlayVisible)
        defaults.set(privacyModeEnabled, forKey: DefaultsKey.privacyModeEnabled)
        defaults.set(speedPointsPerSecond, forKey: DefaultsKey.speed)
        defaults.set(fontSize, forKey: DefaultsKey.fontSize)
        defaults.set(overlayWidth, forKey: DefaultsKey.overlayWidth)
        defaults.set(overlayHeight, forKey: DefaultsKey.overlayHeight)
        defaults.set(countdownSeconds, forKey: DefaultsKey.countdownSeconds)
        defaults.set(countdownBehavior.rawValue, forKey: DefaultsKey.countdownBehavior)
        defaults.set(scrollMode.rawValue, forKey: DefaultsKey.scrollMode)
        defaults.set(selectedScreenID, forKey: DefaultsKey.selectedScreenID)
        defaults.set(voiceMode.rawValue, forKey: DefaultsKey.voiceMode)
        defaults.set(voiceSensitivity, forKey: DefaultsKey.voiceSensitivity)
        defaults.set(glowEnabled, forKey: DefaultsKey.glowEnabled)
        if let c = NSColor(glowColor).usingColorSpace(.sRGB) {
            defaults.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)], forKey: DefaultsKey.glowColor)
        }
        defaults.set(glowWidth, forKey: DefaultsKey.glowWidth)
        defaults.set(glowIntensity, forKey: DefaultsKey.glowIntensity)
        defaults.set(glowRestingLine, forKey: DefaultsKey.glowRestingLine)
        defaults.set(followGlideSpeed, forKey: DefaultsKey.followGlideSpeed)
        defaults.set(followJumpBoost, forKey: DefaultsKey.followJumpBoost)
        defaults.set(followReadingLine, forKey: DefaultsKey.followReadingLine)
        defaults.set(textSideMargin, forKey: DefaultsKey.textSideMargin)
        defaults.set(textTopOffset, forKey: DefaultsKey.textTopOffset)
        defaults.set(autoHideControls, forKey: DefaultsKey.autoHideControls)
        defaults.set(pauseOnHover, forKey: DefaultsKey.pauseOnHover)
    }

    private func beginCountdown(seconds: Int) {
        countdownTask?.cancel()
        isCountingDown = true
        countdownRemaining = seconds

        countdownTask = Task { @MainActor in
            var remaining = seconds
            while remaining > 0 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    isCountingDown = false
                    countdownRemaining = 0
                    countdownTask = nil
                    return
                }
                remaining -= 1
                countdownRemaining = remaining
            }

            guard !Task.isCancelled else { return }
            beginRunningNow()
            countdownTask = nil
        }
    }
    
    private func beginRunningNow() {
        // Run before clearing the countdown so the mic isn't torn down and restarted in between.
        isRunning = true
        isCountingDown = false
        countdownRemaining = 0
        hasStartedSession = true
        shouldUseCountdownOnNextStart = false
    }

    // The mic is live only while voice scrolling can actually matter, so the system indicator isn't always on.
    private func syncVoiceMonitor() {
        followLog.info("sync mode=\(self.voiceMode.rawValue, privacy: .public) running=\(self.isRunning) countdown=\(self.isCountingDown) following=\(self.isFollowingWords) micDenied=\(self.voicePermissionDenied) micUnavail=\(self.voiceUnavailable) spDenied=\(self.speechPermissionDenied) spUnavail=\(self.speechUnavailable)")
        if voiceMode != .off && (isRunning || isCountingDown) {
            voiceMonitor.start()
        } else {
            voiceMonitor.stop()
        }
        if voiceMode == .followWords && (isRunning || isCountingDown) {
            speechFollower.setScript(script)
            speechFollower.start()
        } else {
            speechFollower.stop()
        }
    }

    func toggleVoice() {
        voiceMode = voiceMode == .off ? lastActiveVoiceMode : .off
    }

    private func clampedSpeed(_ value: Double) -> Double {
        let clamped = clamp(value, lower: Self.speedRange.lowerBound, upper: Self.speedRange.upperBound)
        let step = Self.speedStep
        return (clamped / step).rounded() * step
    }

    private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
