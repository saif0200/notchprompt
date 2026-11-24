//
//  AudioLevelMonitor.swift
//  notchprompt
//

import AVFoundation
import Accelerate

/// Listens to the default mic and reports whether the user is speaking. Audio is only measured, never stored.
@MainActor
final class AudioLevelMonitor: ObservableObject {
    @Published private(set) var isSpeaking = false
    /// Loudness 0...1 for the speaking glow; published only on visible changes so the overlay isn't redrawn per buffer.
    @Published private(set) var level: Double = 0
    @Published private(set) var permissionDenied = false
    /// No usable input device or the engine failed to start; callers fail open so the script still scrolls.
    @Published private(set) var unavailable = false

    var sensitivity: Double = 0.5 {
        didSet { box.setSensitivity(sensitivity) }
    }

    /// Receives every tap buffer on the audio thread, so speech recognition shares this engine.
    var bufferConsumer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        didSet { sink.set(bufferConsumer) }
    }

    private let engine = AVAudioEngine()
    private let box = GateBox()
    private let sink = BufferSink()
    private var isStarted = false
    private var configObserver: NSObjectProtocol?

    func start() {
        guard !isStarted else { return }
        isStarted = true
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            permissionDenied = false
            startEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    // stop() may have run while the prompt was up.
                    guard self.isStarted else { return }
                    self.permissionDenied = !granted
                    if granted { self.startEngine() }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        // Off must behave like baseline: never touch the input node unless we started.
        guard isStarted else { return }
        isStarted = false
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isSpeaking = false
        level = 0
    }

    private func startEngine() {
        box.reset(sensitivity: sensitivity)
        // The box restarts closed, so the published flag must too or a stale true never clears.
        isSpeaking = false
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No input device (or one mid-switch) reports 0 Hz; the config-change notification retries.
        unavailable = true
        if format.sampleRate > 0 {
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(box: box, sink: sink, onChange: { [weak self] speaking in
                // A task queued before stop() must not resurrect the flag.
                Task { @MainActor in
                    guard let self, self.isStarted else { return }
                    self.isSpeaking = speaking
                }
            }, onLevel: { [weak self] level in
                Task { @MainActor in
                    guard let self, self.isStarted else { return }
                    self.level = level
                }
            }))
            do {
                try engine.start()
                unavailable = false
            } catch { input.removeTap(onBus: 0) }
        }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.restart()
            }
        }
    }

    private func restart() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        startEngine()
    }

    // Runs on the realtime audio thread, so it must not touch main-actor state.
    private nonisolated static func makeTap(
        box: GateBox,
        sink: BufferSink,
        onChange: @escaping @Sendable (Bool) -> Void,
        onLevel: @escaping @Sendable (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            sink.consume(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var rms: Float = 0
            vDSP_rmsqv(samples, 1, &rms, vDSP_Length(buffer.frameLength))
            let db = 20 * log10(Double(max(rms, 1e-7)))
            if let speaking = box.update(levelDB: db, at: ProcessInfo.processInfo.systemUptime) {
                onChange(speaking)
            }
            if let level = box.level(db: db) { onLevel(level) }
        }
    }
}

/// Lock-guarded gate shared between the audio thread and the main actor.
private final class GateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var gate = VoiceGate(sensitivity: 0.5)
    private var last = false
    private var lastLevel = 0.0

    /// Maps -55...-15 dBFS onto 0...1 (roughly room tone to raised voice); nil unless it moved enough to see.
    func level(db: Double) -> Double? {
        let value = min(max((db + 55) / 40, 0), 1)
        lock.lock(); defer { lock.unlock() }
        guard abs(value - lastLevel) >= 0.04 else { return nil }
        lastLevel = value
        return value
    }

    func setSensitivity(_ s: Double) {
        lock.lock(); defer { lock.unlock() }
        gate.openThresholdDB = VoiceGate.openThresholdDB(sensitivity: s)
    }

    func reset(sensitivity: Double) {
        lock.lock(); defer { lock.unlock() }
        gate = VoiceGate(sensitivity: sensitivity)
        last = false
    }

    /// Returns the new state only when it changed, so the main actor isn't flooded per buffer.
    func update(levelDB: Double, at time: TimeInterval) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        let open = gate.update(levelDB: levelDB, at: time)
        defer { last = open }
        return open == last ? nil : open
    }
}

private final class BufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var consumer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func set(_ consumer: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
        lock.lock(); defer { lock.unlock() }
        self.consumer = consumer
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let consumer = consumer
        lock.unlock()
        consumer?(buffer)
    }
}
