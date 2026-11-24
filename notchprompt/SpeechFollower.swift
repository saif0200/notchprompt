//
//  SpeechFollower.swift
//  notchprompt
//

import AVFoundation
import Speech
import os

/// Counts and positions only, never transcript text. Read with: log show --info --predicate 'subsystem == "notch.notchprompt"'
let followLog = Logger(subsystem: "notch.notchprompt", category: "follow")

/// Recognises speech on this Mac and tracks where in the script the user is. Nothing is stored or sent.
@MainActor
final class SpeechFollower: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var permissionDenied = false
    /// No on-device recognizer for any fallback locale; we never use server recognition.
    @Published private(set) var unavailable = false

    /// Hand to AudioLevelMonitor.bufferConsumer; safe to call from the audio thread.
    nonisolated let sink = RequestSink()

    private var script = ""
    private var tracker = ScriptTracker(script: "")
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var contextualStrings: [String] = []
    private var isActive = false
    /// Invalidates callbacks from tasks we've already replaced or stopped.
    private var generation = 0
    /// Consecutive tasks that ended in an error without recognising anything.
    private var consecutiveFailures = 0
    private static let maxFailures = 5

    func setScript(_ newScript: String) {
        guard newScript != script else { return }
        script = newScript
        tracker = ScriptTracker(script: newScript)
        progress = 0
        let distinct = Set(ScriptTracker.tokenize(newScript).map(\.text).filter { $0.count >= ScriptTracker.longWordLength })
        contextualStrings = Array(distinct.sorted().prefix(100))
    }

    func reset() {
        tracker.reset()
        progress = 0
        // The live transcript still ends with the old words, which would relocate straight back; start a clean one.
        if isActive, task != nil { startTask() }
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            permissionDenied = false
            begin()
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    // stop() may have run while the prompt was up.
                    guard self.isActive else { return }
                    self.permissionDenied = status != .authorized
                    if status == .authorized { self.begin() }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        generation += 1
        endTask()
    }

    private func begin() {
        guard task == nil else { return }
        consecutiveFailures = 0
        let locales = [Locale.current, Locale(identifier: "en-AU"), Locale(identifier: "en-US")]
        recognizer = locales.lazy
            .compactMap { SFSpeechRecognizer(locale: $0) }
            .first { $0.isAvailable && $0.supportsOnDeviceRecognition }
        unavailable = recognizer == nil
        followLog.info("begin recognizer=\(self.recognizer?.locale.identifier ?? "nil", privacy: .public)")
        if recognizer != nil { startTask() }
    }

    private func startTask() {
        guard isActive, let recognizer else { return }
        endTask()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        generation += 1
        let current = generation
        sink.set(request)
        task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let failed = error != nil
            if let error { followLog.error("task error \((error as NSError).domain, privacy: .public) \((error as NSError).code)") }
            let finished = failed || result?.isFinal == true
            Task { @MainActor in self.handle(text: text, failed: failed, finished: finished, generation: current) }
        }
    }

    private func handle(text: String?, failed: Bool, finished: Bool, generation: Int) {
        followLog.info("result words=\(text?.split(separator: " ").count ?? -1) failed=\(failed) finished=\(finished) stale=\(generation != self.generation)")
        guard isActive, generation == self.generation else { return }
        if let text, !text.isEmpty {
            consecutiveFailures = 0
            if tracker.update(recognized: text) != nil { progress = tracker.progress }
            followLog.info("tracker index=\(self.tracker.currentWordIndex) progress=\(self.progress)")
        }
        guard finished else { return }
        // Tasks end on silence timeouts and the on-device time limit; the tracker keeps its place across restarts.
        endTask()
        self.generation += 1
        let next = self.generation
        var delay: UInt64 = 300_000_000
        if failed {
            consecutiveFailures += 1
            if consecutiveFailures >= Self.maxFailures {
                unavailable = true
                return
            }
            delay <<= UInt64(consecutiveFailures)
        }
        Task {
            try? await Task.sleep(nanoseconds: delay)
            if next == self.generation { startTask() }
        }
    }

    private func endTask() {
        sink.set(nil)
        task?.cancel()
        task = nil
    }
}

/// Lock-guarded request shared between the audio thread and the main actor.
final class RequestSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ new: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        let old = request
        request = new
        lock.unlock()
        old?.endAudio()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
}
