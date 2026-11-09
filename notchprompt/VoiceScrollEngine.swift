//
//  VoiceScrollEngine.swift
//  notchprompt
//
//  Moves the script while you're talking and holds it while you're not.
//

import AVFoundation
import Combine
import Foundation
import Speech

enum VoiceInputStatus: Equatable {
    case off
    case requestingPermission
    case listening
    case failed(String)

    var failureMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

enum MicrophoneAccess {
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static let deniedMessage = "Microphone access is off. Turn it on in System Settings, Privacy & Security, Microphone."

    /// With no input device the format is 0 Hz, and installing a tap on it raises
    /// an Objective-C exception that would take the whole app down.
    static func hasUsableInput(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }
}

@MainActor
final class VoiceScrollEngine: ObservableObject {
    @Published private(set) var voiceSpeedMultiplier: Double = 0
    @Published private(set) var status: VoiceInputStatus = .off

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.2
    private var lastSpeechTime = Date()
    private var startGeneration = 0
    private var restartTask: Task<Void, Never>?
    private var consecutiveFailures = 0

    private var isActive: Bool { audioEngine != nil }

    func start() {
        stop()
        startGeneration += 1
        let generation = startGeneration
        status = .requestingPermission

        Task { [weak self] in
            guard let self else { return }
            let speechAllowed = await Self.requestSpeechAuthorization()
            let micAllowed = await MicrophoneAccess.request()
            guard generation == self.startGeneration else { return }

            guard speechAllowed else {
                self.status = .failed("Speech recognition is off. Turn it on in System Settings, Privacy & Security, Speech Recognition.")
                return
            }
            guard micAllowed else {
                self.status = .failed(MicrophoneAccess.deniedMessage)
                return
            }
            self.beginListening()
        }
    }

    func stop() {
        startGeneration += 1
        restartTask?.cancel()
        restartTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        tearDownRecognition()

        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
        consecutiveFailures = 0
        voiceSpeedMultiplier = 0
        status = .off
    }

    private func beginListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            status = .failed("Speech recognition isn't available right now.")
            return
        }

        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard MicrophoneAccess.hasUsableInput(format) else {
            status = .failed("No microphone found.")
            return
        }

        let request = makeRequest(for: speechRecognizer)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(appendingTo: request))

        do {
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            status = .failed("Couldn't start the microphone.")
            return
        }

        audioEngine = engine
        recognitionRequest = request
        lastSpeechTime = Date()
        status = .listening
        beginRecognition(with: request, recognizer: speechRecognizer)

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.decayIfSilent() }
        }
    }

    private func decayIfSilent() {
        guard isActive, Date().timeIntervalSince(lastSpeechTime) > silenceThreshold else { return }
        voiceSpeedMultiplier = max(0, voiceSpeedMultiplier - 0.15)
    }

    private func makeRequest(for recognizer: SFSpeechRecognizer) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Stay on device when the language pack is there; never fail because it isn't.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        return request
    }

    private func beginRecognition(with request: SFSpeechAudioBufferRecognitionRequest, recognizer: SFSpeechRecognizer) {
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let heardSpeech = result != nil
            let failed = error != nil || result?.isFinal == true
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                if heardSpeech {
                    self.lastSpeechTime = Date()
                    self.voiceSpeedMultiplier = 1
                    self.consecutiveFailures = 0
                }
                if failed { self.scheduleRecognitionRestart() }
            }
        }
    }

    /// Recognition sessions expire, usually after about a minute. Restart with a
    /// delay, and give up rather than spin if it keeps failing straight away.
    private func scheduleRecognitionRestart() {
        guard restartTask == nil else { return }
        consecutiveFailures += 1
        guard consecutiveFailures <= 5 else {
            stop()
            status = .failed("Speech recognition keeps stopping. Try turning it off and on again.")
            return
        }

        let delay = min(0.25 * Double(consecutiveFailures), 1.5)
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.restartRecognition()
        }
    }

    private func restartRecognition() {
        restartTask = nil
        guard let audioEngine, let speechRecognizer else { return }
        tearDownRecognition()

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard MicrophoneAccess.hasUsableInput(format) else { return }

        let request = makeRequest(for: speechRecognizer)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(appendingTo: request))
        recognitionRequest = request
        beginRecognition(with: request, recognizer: speechRecognizer)
    }

    private func tearDownRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
    }

    /// Runs on the audio thread, so it must capture nothing main-actor isolated.
    private nonisolated static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
