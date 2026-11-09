//
//  WhisperTranscriptionEngine.swift
//  notchprompt
//

import AVFoundation
import Combine
import Foundation
import WhisperKit

enum ModelLoadState: Equatable {
    case notLoaded
    case loading(progress: Double)
    case loaded
    case failed(String)
}

@MainActor
final class WhisperTranscriptionEngine: ObservableObject, ScriptListeningEngine {
    /// The tail of what was heard, oldest first. Replaced on every pass.
    @Published private(set) var heardWords: [String] = []
    @Published private(set) var status: VoiceInputStatus = .off
    @Published private(set) var modelLoadState: ModelLoadState = .notLoaded

    var heardWordsPublisher: AnyPublisher<[String], Never> { $heardWords.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<VoiceInputStatus, Never> { $status.eraseToAnyPublisher() }
    var preparationPublisher: AnyPublisher<ModelLoadState, Never> { $modelLoadState.eraseToAnyPublisher() }
    var isPrepared: Bool { modelLoadState == .loaded }

    private nonisolated static let sampleRate = 16_000.0
    /// About 15 spoken words: all the aligner needs, and shorter audio decodes faster.
    private static let windowSeconds = 6.0
    /// The gap after each pass. Passes run back to back, so this sets the latency.
    private static let passGap: Duration = .milliseconds(100)

    private var whisperKit: WhisperKit?
    private var audioEngine: AVAudioEngine?
    private var isTranscribing = false
    private let sampleBuffer = RollingSampleBuffer(capacity: Int(sampleRate * windowSeconds))
    private var transcriptionTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    /// The model and tokenizer are inside the app: no download, no network.
    func prepare() async {
        if modelLoadState == .loaded { return }
        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.modelLoadState = .loading(progress: 0)

            guard let bundled = Bundle.main.url(forResource: "WhisperModel", withExtension: nil) else {
                self.modelLoadState = .failed("This build is missing its speech model.")
                return
            }

            do {
                let config = WhisperKitConfig(
                    modelFolder: bundled.appendingPathComponent("openai_whisper-base").path,
                    tokenizerFolder: bundled,
                    computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine),
                    verbose: false,
                    load: true,
                    download: false
                )
                self.whisperKit = try await WhisperKit(config)
                self.modelLoadState = .loaded
            } catch {
                self.modelLoadState = .failed("Couldn't load the speech model.")
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    func start() {
        guard modelLoadState == .loaded, whisperKit != nil, !isTranscribing else { return }
        status = .requestingPermission

        Task { [weak self] in
            let allowed = await MicrophoneAccess.request()
            guard let self else { return }
            guard allowed else {
                self.status = .failed(MicrophoneAccess.deniedMessage)
                return
            }
            guard self.status == .requestingPermission else { return }
            self.beginListening()
        }
    }

    func stop() {
        transcriptionTask?.cancel()
        transcriptionTask = nil

        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
        isTranscribing = false

        sampleBuffer.removeAll()
        heardWords = []
        status = .off
    }

    private func beginListening() {
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard MicrophoneAccess.hasUsableInput(format) else {
            status = .failed("No microphone found.")
            return
        }

        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: format,
            block: Self.tap(writingTo: sampleBuffer, sourceRate: format.sampleRate)
        )

        do {
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            status = .failed("Couldn't start the microphone.")
            return
        }

        audioEngine = engine
        beginTranscribing()
    }

    private func beginTranscribing() {
        isTranscribing = true
        status = .listening

        transcriptionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.transcribeLatestAudio()
                try? await Task.sleep(for: Self.passGap)
            }
        }
    }

    private func transcribeLatestAudio() async {
        guard let whisperKit else { return }
        let samples = sampleBuffer.snapshot()
        guard samples.count > Int(Self.sampleRate * 0.5) else { return }

        // Only the words matter here. Timestamps and retries at a higher
        // temperature cost time on every pass and buy nothing.
        var options = DecodingOptions()
        options.language = "en"
        options.temperature = 0
        options.temperatureFallbackCount = 0
        options.withoutTimestamps = true
        options.wordTimestamps = false
        options.skipSpecialTokens = true

        guard let results = try? await whisperKit.transcribe(audioArray: samples, decodeOptions: options),
              isTranscribing
        else { return }

        let words = results
            .map(\.text)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if !words.isEmpty {
            heardWords = words
        }
    }

#if DEBUG
    func debugBeginFileFeed() async {
        sampleBuffer.removeAll()
        beginTranscribing()
    }

    func debugFeed(_ samples: [Float], sampleRate: Double) {
        sampleBuffer.append(samples)
    }
#endif

    private nonisolated static func tap(
        writingTo buffer: RollingSampleBuffer,
        sourceRate: Double
    ) -> AVAudioNodeTapBlock {
        { pcm, _ in
            buffer.append(convertToMono16kHz(buffer: pcm, fromRate: sourceRate))
        }
    }

    private nonisolated static func convertToMono16kHz(buffer: AVAudioPCMBuffer, fromRate sourceRate: Double) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return [] }

        var mono = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameCount {
                mono[frame] += samples[frame]
            }
        }
        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for frame in 0..<frameCount {
                mono[frame] *= scale
            }
        }

        guard abs(sourceRate - sampleRate) > 1 else { return mono }

        let ratio = sampleRate / sourceRate
        let outputCount = Int(Double(frameCount) * ratio)
        var resampled = [Float](repeating: 0, count: outputCount)
        for index in 0..<outputCount {
            let sourcePosition = Double(index) / ratio
            let whole = Int(sourcePosition)
            let fraction = Float(sourcePosition - Double(whole))
            if whole + 1 < frameCount {
                resampled[index] = mono[whole] * (1 - fraction) + mono[whole + 1] * fraction
            } else if whole < frameCount {
                resampled[index] = mono[whole]
            }
        }
        return resampled
    }
}

/// Written on the audio thread, read on the main actor. Holds only the most
/// recent `capacity` samples, so a long session uses no more memory than a short one.
private final class RollingSampleBuffer: @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var samples: [Float] = []

    init(capacity: Int) {
        self.capacity = capacity
        samples.reserveCapacity(capacity * 2)
    }

    func append(_ newSamples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: newSamples)
        if samples.count > capacity * 2 {
            samples.removeFirst(samples.count - capacity)
        }
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return Array(samples.suffix(capacity))
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true)
    }
}
