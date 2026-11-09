//
//  PrompterModel.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class PrompterModel: ObservableObject {
    enum ScrollMode: String, CaseIterable {
        case infinite
        case stopAtEnd
    }

    enum FontFamily: String, CaseIterable {
        case system
        case rounded
        case serif
        case monospaced
        case helvetica

        var label: String {
            switch self {
            case .system: return "SF Pro"
            case .rounded: return "SF Rounded"
            case .serif: return "New York"
            case .monospaced: return "SF Mono"
            case .helvetica: return "Helvetica Neue"
            }
        }

        /// `sfPro` was an earlier option that resolved to the system font anyway.
        init?(savedValue: String) {
            if savedValue == "sfPro" {
                self = .system
            } else {
                self.init(rawValue: savedValue)
            }
        }

        func font(size: CGFloat) -> NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: .medium)
            switch self {
            case .system:
                return base
            case .rounded:
                return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            case .serif:
                return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
            case .monospaced:
                return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            case .helvetica:
                return NSFont(name: "HelveticaNeue-Medium", size: size) ?? base
            }
        }
    }

    enum TextAlignmentOption: String, CaseIterable {
        case leading
        case center

        var label: String {
            switch self {
            case .leading: return "Left"
            case .center: return "Center"
            }
        }

        var nsAlignment: NSTextAlignment {
            switch self {
            case .leading: return .left
            case .center: return .center
            }
        }
    }

    enum ColorTheme: String, CaseIterable {
        case classic
        case retroGreen
        case darkBlue
        case warmAmber

        var label: String {
            switch self {
            case .classic: return "Black & White"
            case .retroGreen: return "Retro Green"
            case .darkBlue: return "Dark Blue"
            case .warmAmber: return "Warm Amber"
            }
        }

        var textHex: String {
            switch self {
            case .classic: return "#FFFFFF"
            case .retroGreen: return "#33FF33"
            case .darkBlue: return "#E0E8FF"
            case .warmAmber: return "#FFD699"
            }
        }

        var backgroundHex: String {
            switch self {
            case .classic: return "#000000"
            case .retroGreen: return "#001A00"
            case .darkBlue: return "#0A0E1A"
            case .warmAmber: return "#1A0E00"
            }
        }
    }

    enum CountdownBehavior: String, CaseIterable {
        case always
        case freshStartOnly
        case never

        var label: String {
            switch self {
            case .always: return "Always"
            case .freshStartOnly: return "Fresh start only"
            case .never: return "Never"
            }
        }
    }

    static let shared = PrompterModel()

    static let wordsPerMinuteRange: ClosedRange<Double> = 40...400
    static let speedStep: Double = 5
    static let speedPresetSlow: Double = 120
    static let speedPresetNormal: Double = 150
    static let speedPresetFast: Double = 180
    static let fontSizeRange: ClosedRange<Double> = 14...64
    static let islandNudgeRange: ClosedRange<Double> = -4...8

    /// Lives here, not in the view, so playback survives the island's forms.
    let scroller = PrompterScroller()

    @Published var script: String = PrompterModel.welcomeScript {
        didSet {
            guard script != oldValue else { return }
            refreshDocument()
        }
    }
    @Published private(set) var document = ScriptDocument(script: PrompterModel.welcomeScript)

    @Published private(set) var isRunning = false
    @Published var isOverlayVisible = true
    @Published var privacyModeEnabled = true
    @Published private(set) var hasStartedSession = false
    @Published private(set) var isCountingDown = false
    @Published var countdownSeconds = 3
    @Published var countdownBehavior: CountdownBehavior = .freshStartOnly
    @Published private(set) var countdownRemaining = 0
    @Published private(set) var didReachEnd = false

    /// Pace in words per minute, so changing the font never changes how fast you read.
    @Published var wordsPerMinute: Double = speedPresetNormal
    @Published var fontSize: Double = 26
    @Published var overlayWidth: Double = Double(IslandLayout.defaultExpandedSize.width)
    @Published var overlayHeight: Double = Double(IslandLayout.defaultExpandedSize.height)
    @Published var backgroundOpacity: Double = 1
    @Published var scrollMode: ScrollMode = .stopAtEnd
    @Published var islandAttachment: IslandAttachment = .floating
    @Published var islandVerticalNudge: Double = 0

    @Published var fontFamily: FontFamily = .system
    @Published var lineSpacing: Double = 1.35
    @Published var textAlignment: TextAlignmentOption = .center
    @Published var textColorHex = "#FFFFFF"
    @Published var backgroundColorHex = "#000000"
    @Published var horizontalMargin: Double = 28
    @Published var mirrorMode = false

    @Published var cueLineEnabled = true
    @Published var cueLinePosition: Double = 0.18
    @Published var cueLineColorHex = "#FFFFFF"
    @Published var cueLineOpacity: Double = 0.4
    @Published var focusModeEnabled = false
    @Published var focusVisibleLines = 3
    @Published var focusDimOpacity: Double = 0.7

    @Published var timedScrollEnabled = false
    @Published var targetDurationSeconds: Double = 300
    @Published var showTimeDisplay = true
    @Published private(set) var elapsedSeconds: Double = 0
    @Published private(set) var progress: Double = 0

    /// 0 means "auto" (prefer built-in display)
    @Published var selectedScreenID: CGDirectDisplayID = 0

    // The island's state
    @Published var isIslandExpanded = false
    @Published private(set) var islandForm: IslandForm = .idle
    private var isPointerOverIsland = false

    // Voice
    @Published private(set) var voiceScrollEnabled = false
    @Published private(set) var voiceTrackingEnabled = false
    @Published private(set) var voiceScrollStatus: VoiceInputStatus = .off
    @Published private(set) var voiceTrackingStatus: VoiceInputStatus = .off
    @Published private(set) var speechModelState: ModelLoadState = .notLoaded
    @Published private(set) var speechEngine: SpeechEngineChoice = .preferred
    @Published private(set) var trackingConfidence: AlignmentConfidence = .high
    @Published var highlightColorHex = "#FFCC00"

    private lazy var voiceEngine = VoiceScrollEngine()
    private lazy var whisperEngine = WhisperTranscriptionEngine()
    private var appleEngine: AnyObject?
#if DEBUG
    private var debugAcceptsHeardWords = false
#endif
    private let alignmentEngine = ScriptAlignmentEngine()
    private var voiceScrollCancellables: Set<AnyCancellable> = []
    private var voiceTrackingCancellables: Set<AnyCancellable> = []

    private var elapsedTimer: Timer?
    private var elapsedBase: Double = 0
    private var runStartedAt: Date?
    private var countdownTask: Task<Void, Never>?
    private var shouldUseCountdownOnNextStart = true
    private let defaults: UserDefaults

    private static let welcomeScript = """
    Welcome to Notchprompt.

    Your script scrolls right under the camera, so your eyes stay on the lens and you look straight at your audience.

    Press Option Command P to start and pause. Open the Script Editor from the menu bar icon to replace this text with your own.
    """

    private enum DefaultsKey {
        static let hasSavedSession = "hasSavedSession"
        static let script = "script"
        static let isOverlayVisible = "isOverlayVisible"
        static let privacyModeEnabled = "privacyModeEnabled"
        static let wordsPerMinute = "wordsPerMinute"
        static let fontSize = "fontSize"
        static let overlayWidth = "overlayWidth"
        static let overlayHeight = "overlayHeight"
        static let countdownSeconds = "countdownSeconds"
        static let countdownBehavior = "countdownBehavior"
        static let scrollMode = "scrollMode"
        static let selectedScreenID = "selectedScreenID"
        static let islandAttachment = "islandAttachment"
        static let islandVerticalNudge = "islandVerticalNudge"
        static let fontFamily = "fontFamily"
        static let lineSpacing = "lineSpacing"
        static let textAlignment = "textAlignment"
        static let textColorHex = "textColorHex"
        static let backgroundColorHex = "backgroundColorHex"
        static let cueLineEnabled = "cueLineEnabled"
        static let cueLinePosition = "cueLinePosition"
        static let cueLineColorHex = "cueLineColorHex"
        static let cueLineOpacity = "cueLineOpacity"
        static let focusModeEnabled = "focusModeEnabled"
        static let focusVisibleLines = "focusVisibleLines"
        static let focusDimOpacity = "focusDimOpacity"
        static let timedScrollEnabled = "timedScrollEnabled"
        static let targetDurationSeconds = "targetDurationSeconds"
        static let showTimeDisplay = "showTimeDisplay"
        static let horizontalMargin = "horizontalMargin"
        static let backgroundOpacity = "backgroundOpacity"
        static let mirrorMode = "mirrorMode"
        static let highlightColorHex = "highlightColorHex"
        static let speechEngine = "speechEngine"
    }

    private init() {
#if DEBUG
        if let suite = ProcessInfo.processInfo.environment["NOTCHPROMPT_DEFAULTS_SUITE"],
           let scratch = UserDefaults(suiteName: suite) {
            defaults = scratch
        } else {
            defaults = .standard
        }
#else
        defaults = .standard
#endif
        scroller.onProgress = { [weak self] value in
            self?.progress = value
        }
        scroller.onReachedEnd = { [weak self] in
            self?.markReachedEnd()
        }
    }

    deinit {
        countdownTask?.cancel()
    }

    // MARK: - Script

    /// A new script from the library or a file. Editing in place keeps your spot;
    /// this starts over.
    func loadScript(_ text: String) {
        script = text
        resetScroll()
    }

    private func refreshDocument() {
        document = ScriptDocument(script: script)
        alignmentEngine.setWords(document.words)
        scroller.highlightRange = nil
    }

    var wordCount: Int { document.wordCount }

    /// The pace actually in use: timed scrolling replaces the manual one.
    var effectiveWordsPerMinute: Double {
        guard timedScrollEnabled, targetDurationSeconds > 0, wordCount > 0 else { return wordsPerMinute }
        let required = Double(wordCount) / (targetDurationSeconds / 60)
        return clamp(required, to: Self.wordsPerMinuteRange)
    }

    var estimatedReadDuration: TimeInterval {
        guard wordCount > 0 else { return 0 }
        return Double(wordCount) / effectiveWordsPerMinute * 60
    }

    var remainingSeconds: Double {
        max(0, estimatedReadDuration * (1 - progress))
    }

    func formattedEstimatedReadDuration() -> String {
        let duration = Int(estimatedReadDuration.rounded())
        guard duration > 0 else { return "0s" }
        guard duration >= 60 else { return "\(duration)s" }
        return String(format: "%dm %02ds", duration / 60, duration % 60)
    }

    func formattedTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Playback

    func toggleRunning() {
        if isRunning || isCountingDown {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isRunning, !isCountingDown, !document.isEmpty else {
            if document.isEmpty {
                isOverlayVisible = true
                expandIsland()
            }
            return
        }

        isOverlayVisible = true
        expandIsland()

        if didReachEnd || scroller.engine.isAtEnd {
            resetScroll()
        }

        startVoiceInputForPlayback()

        let delay = max(0, countdownSeconds)
        let useCountdown: Bool
        switch countdownBehavior {
        case .always: useCountdown = delay > 0
        case .freshStartOnly: useCountdown = delay > 0 && shouldUseCountdownOnNextStart
        case .never: useCountdown = false
        }

        if useCountdown {
            beginCountdown(seconds: delay)
        } else {
            beginRunningNow()
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        isCountingDown = false
        countdownRemaining = 0
        isRunning = false
        scroller.setRunning(false)
        stopElapsedClock()
        stopVoiceInputForPlayback()
        refreshIslandForm()
    }

    /// Back to the top, ready to go again.
    func resetScroll() {
        stop()
        didReachEnd = false
        hasStartedSession = false
        shouldUseCountdownOnNextStart = true
        elapsedBase = 0
        elapsedSeconds = 0
        alignmentEngine.reset()
        trackingConfidence = .high
        scroller.resetToTop()
        refreshIslandForm()
    }

    func jumpBack(seconds: Double = 5) {
        guard seconds > 0 else { return }
        didReachEnd = false
        scroller.jumpBack(seconds: seconds)
        refreshIslandForm()
    }

    /// The trackpad corrects your place without stopping the read.
    func handleManualScroll(deltaPoints: CGFloat) {
        guard abs(deltaPoints) > 0.01 else { return }
        scroller.nudge(by: deltaPoints)
        if !scroller.engine.isAtEnd { didReachEnd = false }
    }

    private func beginCountdown(seconds: Int) {
        countdownTask?.cancel()
        isCountingDown = true
        countdownRemaining = seconds
        refreshIslandForm()

        countdownTask = Task { @MainActor [weak self] in
            for remaining in stride(from: seconds - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.countdownRemaining = remaining
            }
            guard let self, !Task.isCancelled else { return }
            self.countdownTask = nil
            self.beginRunningNow()
        }
    }

    private func beginRunningNow() {
        isCountingDown = false
        countdownRemaining = 0
        hasStartedSession = true
        shouldUseCountdownOnNextStart = false
        isRunning = true
        scroller.setRunning(true)
        startElapsedClock()
        refreshIslandForm()
    }

    private func markReachedEnd() {
        didReachEnd = true
        stop()
        refreshIslandForm()
    }

    func setScrollMode(_ newMode: ScrollMode) {
        guard scrollMode != newMode else { return }
        scrollMode = newMode
        didReachEnd = false
    }

    // MARK: - Pace, type, size

    func setSpeed(_ value: Double) {
        wordsPerMinute = clampedSpeed(value)
    }

    func adjustSpeed(delta: Double) {
        // Nudging the pace means you've stopped wanting a fixed finish time.
        let current = effectiveWordsPerMinute
        timedScrollEnabled = false
        setSpeed(current + delta)
    }

    func applySpeedPreset(_ preset: Double) {
        timedScrollEnabled = false
        setSpeed(preset)
    }

    func adjustFontSize(delta: Double) {
        fontSize = clamp(fontSize + delta, to: Self.fontSizeRange)
    }

    func setOverlaySize(width: Double, height: Double) {
        overlayWidth = width.rounded()
        overlayHeight = height.rounded()
    }

    func applyColorTheme(_ theme: ColorTheme) {
        textColorHex = theme.textHex
        backgroundColorHex = theme.backgroundHex
    }

    private func clampedSpeed(_ value: Double) -> Double {
        let stepped = (value / Self.speedStep).rounded() * Self.speedStep
        return clamp(stepped, to: Self.wordsPerMinuteRange)
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Island

    func expandIsland() {
        guard !isIslandExpanded else { return }
        isIslandExpanded = true
        refreshIslandForm()
    }

    func collapseIsland() {
        guard isIslandExpanded else { return }
        isIslandExpanded = false
        refreshIslandForm()
    }

    func setPointerOverIsland(_ isOver: Bool) {
        guard isPointerOverIsland != isOver else { return }
        isPointerOverIsland = isOver
        refreshIslandForm()
    }

    private func refreshIslandForm() {
        let form: IslandForm
        if isIslandExpanded {
            form = .expanded
        } else if isRunning || isCountingDown || hasStartedSession || isPointerOverIsland {
            form = .compact
        } else {
            form = .idle
        }
        if islandForm != form { islandForm = form }
    }

    // MARK: - Voice

    var voiceFailureMessage: String? {
        voiceScrollStatus.failureMessage ?? voiceTrackingStatus.failureMessage
    }

    func setVoiceScrollEnabled(_ enabled: Bool) {
        guard voiceScrollEnabled != enabled else { return }
        voiceScrollEnabled = enabled
        voiceScrollCancellables.removeAll()

        guard enabled else {
            voiceEngine.stop()
            voiceScrollStatus = .off
            scroller.speedScale = 1
            return
        }

        if voiceTrackingEnabled { setVoiceTrackingEnabled(false) }

        voiceEngine.$voiceSpeedMultiplier
            .sink { [weak self] multiplier in
                self?.scroller.speedScale = CGFloat(multiplier)
            }
            .store(in: &voiceScrollCancellables)
        voiceEngine.$status
            .sink { [weak self] status in
                self?.voiceScrollStatus = status
            }
            .store(in: &voiceScrollCancellables)

        if isRunning || isCountingDown { voiceEngine.start() }
    }

    func setVoiceTrackingEnabled(_ enabled: Bool) {
        guard voiceTrackingEnabled != enabled else { return }
        voiceTrackingEnabled = enabled

        guard enabled else {
            voiceTrackingCancellables.removeAll()
            activeListener.stop()
            voiceTrackingStatus = .off
            trackingConfidence = .high
            scroller.highlightRange = nil
            scroller.speedScale = 1
            return
        }

        if voiceScrollEnabled { setVoiceScrollEnabled(false) }
        alignmentEngine.setWords(document.words)
        // Hold still until the first word is heard, then the voice drives.
        scroller.speedScale = 0
        connectListeningEngine()
    }

    /// Takes effect immediately, even in the middle of a read.
    func setSpeechEngine(_ choice: SpeechEngineChoice) {
        guard speechEngine != choice, SpeechEngineChoice.available.contains(choice) else { return }
        if voiceTrackingEnabled {
            voiceTrackingCancellables.removeAll()
            activeListener.stop()
        }
        speechEngine = choice
        if voiceTrackingEnabled {
            alignmentEngine.reset()
            connectListeningEngine()
        }
    }

    private var activeListener: ScriptListeningEngine {
        if speechEngine == .apple, #available(macOS 26.0, *) {
            if let engine = appleEngine as? AppleSpeechEngine { return engine }
            let engine = AppleSpeechEngine()
            appleEngine = engine
            return engine
        }
        return whisperEngine
    }

    private func connectListeningEngine() {
        let listener = activeListener
        voiceTrackingCancellables.removeAll()

        listener.preparationPublisher
            .sink { [weak self] state in
                self?.speechModelState = state
            }
            .store(in: &voiceTrackingCancellables)
        listener.statusPublisher
            .sink { [weak self] status in
                self?.voiceTrackingStatus = status
            }
            .store(in: &voiceTrackingCancellables)
        listener.heardWordsPublisher
            .sink { [weak self] words in
                self?.applyHeardWords(words)
            }
            .store(in: &voiceTrackingCancellables)

        Task { [weak self] in
            await listener.prepare()
            guard let self, self.voiceTrackingEnabled, self.activeListener === listener,
                  self.isRunning || self.isCountingDown
            else { return }
            listener.start()
        }
    }

    private func applyHeardWords(_ words: [String]) {
        var accepts = isRunning
#if DEBUG
        accepts = accepts || debugAcceptsHeardWords
#endif
        guard !words.isEmpty, accepts else { return }
        alignmentEngine.process(heard: words)
        trackingConfidence = alignmentEngine.confidence

        let index = alignmentEngine.currentWordIndex
        guard document.words.indices.contains(index) else { return }
        scroller.highlightRange = document.words[index].range
    }

    /// The microphone is only ever open while the script is playing.
    private func startVoiceInputForPlayback() {
        if voiceScrollEnabled {
            voiceEngine.start()
        }
        if voiceTrackingEnabled, activeListener.isPrepared {
            activeListener.start()
        }
    }

    private func stopVoiceInputForPlayback() {
        if voiceScrollEnabled {
            voiceEngine.stop()
        }
        if voiceTrackingEnabled {
            activeListener.stop()
        }
    }

    func shutDownVoiceInput() {
        if voiceScrollEnabled { voiceEngine.stop() }
        if voiceTrackingEnabled { activeListener.stop() }
    }

#if DEBUG
    /// Plays real speech through the real engine and aligner at real-time speed,
    /// with no microphone, and reports how far the tracked word trails the voice.
    func debugRunSpeechCheck(choice: SpeechEngineChoice, samples: [Float], script: String, sampleRate: Double) async {
        loadScript(script)
        setSpeechEngine(choice)
        debugAcceptsHeardWords = true
        defer { debugAcceptsHeardWords = false }
        setVoiceTrackingEnabled(true)

        let listener = activeListener
        let prepareStart = Date()
        await listener.prepare()
        print("[Speech:\(choice.rawValue)] prepared=\(listener.isPrepared) in \(String(format: "%.2f", Date().timeIntervalSince(prepareStart)))s state=\(speechModelState)")
        guard listener.isPrepared else {
            setVoiceTrackingEnabled(false)
            return
        }

        await listener.debugBeginFileFeed()
        let duration = Double(samples.count) / sampleRate
        let wordsPerSecond = Double(wordCount) / duration
        let started = Date()
        let cpuStart = OverlayDebugHarness.cpuSeconds()
        var fed = 0
        var lags: [Double] = []
        var firstLock: Double?

        while fed < samples.count {
            try? await Task.sleep(for: .milliseconds(50))
            let elapsed = Date().timeIntervalSince(started)
            let target = min(samples.count, Int(elapsed * sampleRate))
            if target > fed {
                listener.debugFeed(Array(samples[fed..<target]), sampleRate: sampleRate)
                fed = target
            }
            let index = alignmentEngine.currentWordIndex
            if index >= 0, firstLock == nil { firstLock = elapsed }
            if elapsed > 3 { lags.append(elapsed * wordsPerSecond - Double(index + 1)) }
        }

        try? await Task.sleep(for: .seconds(1.5))
        let cpu = (OverlayDebugHarness.cpuSeconds() - cpuStart) / (duration + 1.5) * 100
        let meanLag = lags.reduce(0, +) / Double(max(lags.count, 1))
        let reached = alignmentEngine.currentWordIndex
        print("[Speech:\(choice.rawValue)] first lock \(String(format: "%.1f", firstLock ?? -1))s, reached \(reached + 1)/\(wordCount), mean lag \(String(format: "%.1f", meanLag)) words (\(String(format: "%.2f", meanLag / wordsPerSecond))s), CPU \(String(format: "%.0f", cpu))%, status \(voiceTrackingStatus)")
        setVoiceTrackingEnabled(false)
    }
#endif

    // MARK: - Elapsed time

    private func startElapsedClock() {
        stopElapsedClock()
        runStartedAt = Date()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshElapsed() }
        }
    }

    private func stopElapsedClock() {
        refreshElapsed()
        elapsedBase = elapsedSeconds
        runStartedAt = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func refreshElapsed() {
        guard let runStartedAt else { return }
        let value = elapsedBase + Date().timeIntervalSince(runStartedAt)
        if Int(value) != Int(elapsedSeconds) { elapsedSeconds = value }
    }

    // MARK: - Persistence

    func loadFromDefaults() {
        guard defaults.bool(forKey: DefaultsKey.hasSavedSession) else {
            refreshDocument()
            return
        }

        if let savedScript = defaults.string(forKey: DefaultsKey.script) {
            script = savedScript
        }
        refreshDocument()

        func double(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) as? Double ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? fallback
        }

        privacyModeEnabled = bool(DefaultsKey.privacyModeEnabled, privacyModeEnabled)
        isOverlayVisible = bool(DefaultsKey.isOverlayVisible, true)
        wordsPerMinute = clampedSpeed(double(DefaultsKey.wordsPerMinute, wordsPerMinute))
        fontSize = clamp(double(DefaultsKey.fontSize, fontSize), to: Self.fontSizeRange)
        overlayWidth = double(DefaultsKey.overlayWidth, overlayWidth)
        overlayHeight = double(DefaultsKey.overlayHeight, overlayHeight)
        backgroundOpacity = clamp(double(DefaultsKey.backgroundOpacity, 1), to: 0.3...1)
        countdownSeconds = Int(clamp(double(DefaultsKey.countdownSeconds, Double(countdownSeconds)), to: 0...10))
        countdownBehavior = defaults.string(forKey: DefaultsKey.countdownBehavior).flatMap(CountdownBehavior.init) ?? countdownBehavior
        scrollMode = defaults.string(forKey: DefaultsKey.scrollMode).flatMap(ScrollMode.init) ?? scrollMode
        islandAttachment = defaults.string(forKey: DefaultsKey.islandAttachment).flatMap(IslandAttachment.init) ?? islandAttachment
        islandVerticalNudge = clamp(double(DefaultsKey.islandVerticalNudge, 0), to: Self.islandNudgeRange)
        selectedScreenID = (defaults.object(forKey: DefaultsKey.selectedScreenID) as? NSNumber)?.uint32Value ?? 0

        fontFamily = defaults.string(forKey: DefaultsKey.fontFamily).flatMap(FontFamily.init(savedValue:)) ?? fontFamily
        lineSpacing = clamp(double(DefaultsKey.lineSpacing, lineSpacing), to: 1...3)
        textAlignment = defaults.string(forKey: DefaultsKey.textAlignment).flatMap(TextAlignmentOption.init) ?? textAlignment
        textColorHex = defaults.string(forKey: DefaultsKey.textColorHex) ?? textColorHex
        backgroundColorHex = defaults.string(forKey: DefaultsKey.backgroundColorHex) ?? backgroundColorHex
        horizontalMargin = clamp(double(DefaultsKey.horizontalMargin, horizontalMargin), to: 10...120)
        mirrorMode = bool(DefaultsKey.mirrorMode, mirrorMode)

        cueLineEnabled = bool(DefaultsKey.cueLineEnabled, cueLineEnabled)
        cueLinePosition = clamp(double(DefaultsKey.cueLinePosition, cueLinePosition), to: 0.1...0.9)
        cueLineColorHex = defaults.string(forKey: DefaultsKey.cueLineColorHex) ?? cueLineColorHex
        cueLineOpacity = clamp(double(DefaultsKey.cueLineOpacity, cueLineOpacity), to: 0.1...1)
        focusModeEnabled = bool(DefaultsKey.focusModeEnabled, focusModeEnabled)
        focusVisibleLines = Int(clamp(double(DefaultsKey.focusVisibleLines, Double(focusVisibleLines)), to: 1...10))
        focusDimOpacity = clamp(double(DefaultsKey.focusDimOpacity, focusDimOpacity), to: 0.1...0.95)

        timedScrollEnabled = bool(DefaultsKey.timedScrollEnabled, timedScrollEnabled)
        targetDurationSeconds = clamp(double(DefaultsKey.targetDurationSeconds, targetDurationSeconds), to: 10...3600)
        showTimeDisplay = bool(DefaultsKey.showTimeDisplay, showTimeDisplay)
        highlightColorHex = defaults.string(forKey: DefaultsKey.highlightColorHex) ?? highlightColorHex
        if let saved = defaults.string(forKey: DefaultsKey.speechEngine).flatMap(SpeechEngineChoice.init),
           SpeechEngineChoice.available.contains(saved) {
            speechEngine = saved
        }
    }

    func saveToDefaults() {
        let d = defaults
        d.set(true, forKey: DefaultsKey.hasSavedSession)
        d.set(script, forKey: DefaultsKey.script)
        d.set(isOverlayVisible, forKey: DefaultsKey.isOverlayVisible)
        d.set(privacyModeEnabled, forKey: DefaultsKey.privacyModeEnabled)
        d.set(wordsPerMinute, forKey: DefaultsKey.wordsPerMinute)
        d.set(fontSize, forKey: DefaultsKey.fontSize)
        d.set(overlayWidth, forKey: DefaultsKey.overlayWidth)
        d.set(overlayHeight, forKey: DefaultsKey.overlayHeight)
        d.set(Double(countdownSeconds), forKey: DefaultsKey.countdownSeconds)
        d.set(countdownBehavior.rawValue, forKey: DefaultsKey.countdownBehavior)
        d.set(scrollMode.rawValue, forKey: DefaultsKey.scrollMode)
        d.set(NSNumber(value: selectedScreenID), forKey: DefaultsKey.selectedScreenID)
        d.set(islandAttachment.rawValue, forKey: DefaultsKey.islandAttachment)
        d.set(islandVerticalNudge, forKey: DefaultsKey.islandVerticalNudge)
        d.set(fontFamily.rawValue, forKey: DefaultsKey.fontFamily)
        d.set(lineSpacing, forKey: DefaultsKey.lineSpacing)
        d.set(textAlignment.rawValue, forKey: DefaultsKey.textAlignment)
        d.set(textColorHex, forKey: DefaultsKey.textColorHex)
        d.set(backgroundColorHex, forKey: DefaultsKey.backgroundColorHex)
        d.set(horizontalMargin, forKey: DefaultsKey.horizontalMargin)
        d.set(backgroundOpacity, forKey: DefaultsKey.backgroundOpacity)
        d.set(mirrorMode, forKey: DefaultsKey.mirrorMode)
        d.set(cueLineEnabled, forKey: DefaultsKey.cueLineEnabled)
        d.set(cueLinePosition, forKey: DefaultsKey.cueLinePosition)
        d.set(cueLineColorHex, forKey: DefaultsKey.cueLineColorHex)
        d.set(cueLineOpacity, forKey: DefaultsKey.cueLineOpacity)
        d.set(focusModeEnabled, forKey: DefaultsKey.focusModeEnabled)
        d.set(Double(focusVisibleLines), forKey: DefaultsKey.focusVisibleLines)
        d.set(focusDimOpacity, forKey: DefaultsKey.focusDimOpacity)
        d.set(timedScrollEnabled, forKey: DefaultsKey.timedScrollEnabled)
        d.set(targetDurationSeconds, forKey: DefaultsKey.targetDurationSeconds)
        d.set(showTimeDisplay, forKey: DefaultsKey.showTimeDisplay)
        d.set(highlightColorHex, forKey: DefaultsKey.highlightColorHex)
        d.set(speechEngine.rawValue, forKey: DefaultsKey.speechEngine)
    }
}
