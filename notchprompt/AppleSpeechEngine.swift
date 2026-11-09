//
//  AppleSpeechEngine.swift
//  notchprompt
//
//  Follows the script with SpeechAnalyzer (macOS 26 and later). It streams words
//  as they're spoken and revises them as it hears more. macOS owns the language
//  model and downloads it once if it isn't already on the Mac.
//

import AVFoundation
import Combine
import Foundation
import Speech

@available(macOS 26.0, *)
@MainActor
final class AppleSpeechEngine: ObservableObject, ScriptListeningEngine {
    @Published private(set) var heardWords: [String] = []
    @Published private(set) var status: VoiceInputStatus = .off
    @Published private(set) var preparation: ModelLoadState = .notLoaded

    var heardWordsPublisher: AnyPublisher<[String], Never> { $heardWords.eraseToAnyPublisher() }
    var statusPublisher: AnyPublisher<VoiceInputStatus, Never> { $status.eraseToAnyPublisher() }
    var preparationPublisher: AnyPublisher<ModelLoadState, Never> { $preparation.eraseToAnyPublisher() }
    var isPrepared: Bool { preparation == .loaded }

    private static let retainedWords = 40

    private var locale: Locale?
    private var audioEngine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var forwarder: AnalyzerAudioForwarder?
    private var startGeneration = 0
    private var finalizedWords: [String] = []
    private var volatileWords: [String] = []

    private func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }

    func prepare() async {
        if preparation == .loaded { return }
        preparation = .loading(progress: 0)

        guard let locale = await Self.bestLocale() else {
            preparation = .failed("Apple Speech doesn't support this Mac's language. Switch the engine to Whisper.")
            return
        }

        do {
            let module = makeTranscriber(locale: locale)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                let progressTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        self?.preparation = .loading(progress: request.progress.fractionCompleted)
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                defer { progressTask.cancel() }
                try await request.downloadAndInstall()
            }
            self.locale = locale
            preparation = .loaded
        } catch {
            preparation = .failed("Couldn't download Apple's speech model. Check your connection, or switch the engine to Whisper.")
        }
    }

    private static func bestLocale() async -> Locale? {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: .current) { return match }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }

    func start() {
        guard audioEngine == nil, analyzer == nil else { return }
        startGeneration += 1
        let generation = startGeneration
        status = .requestingPermission

        Task { [weak self] in
            let allowed = await MicrophoneAccess.request()
            guard let self, generation == self.startGeneration else { return }
            guard allowed else {
                self.status = .failed(MicrophoneAccess.deniedMessage)
                return
            }

            guard let forwarder = await self.beginAnalysis(generation: generation) else { return }
            self.attachMicrophone(to: forwarder)
        }
    }

    func stop() {
        startGeneration += 1
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
        forwarder = nil
        inputContinuation?.finish()
        inputContinuation = nil
        resultsTask?.cancel()
        resultsTask = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        finalizedWords = []
        volatileWords = []
        heardWords = []
        status = .off
    }

    /// Sets up the analyzer and returns the object audio should be sent to.
    private func beginAnalysis(generation: Int) async -> AnalyzerAudioForwarder? {
        guard let locale else {
            status = .failed("Apple's speech model isn't ready yet.")
            return nil
        }

        let transcriber = makeTranscriber(locale: locale)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            status = .failed("Apple Speech can't use this Mac's audio.")
            return nil
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        do {
            try await analyzer.prepareToAnalyze(in: format)
            try await analyzer.start(inputSequence: stream)
        } catch {
            continuation.finish()
            status = .failed("Couldn't start Apple Speech. Switch the engine to Whisper.")
            return nil
        }

        guard generation == startGeneration else {
            continuation.finish()
            await analyzer.cancelAndFinishNow()
            return nil
        }

        self.analyzer = analyzer
        inputContinuation = continuation
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.absorb(text: String(result.text.characters), isFinal: result.isFinal)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed("Apple Speech stopped. Press start again, or switch the engine to Whisper.")
            }
        }

        let forwarder = AnalyzerAudioForwarder(continuation: continuation, outputFormat: format)
        self.forwarder = forwarder
        return forwarder
    }

    private func attachMicrophone(to forwarder: AnalyzerAudioForwarder) {
        let engine = AVAudioEngine()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard MicrophoneAccess.hasUsableInput(format) else {
            status = .failed("No microphone found.")
            return
        }

        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(sendingTo: forwarder))
        do {
            engine.prepare()
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            status = .failed("Couldn't start the microphone.")
            return
        }

        audioEngine = engine
        status = .listening
    }

    private func absorb(text: String, isFinal: Bool) {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if isFinal {
            finalizedWords = Array((finalizedWords + words).suffix(Self.retainedWords))
            volatileWords = []
        } else {
            volatileWords = words
        }
        heardWords = Array((finalizedWords + volatileWords).suffix(Self.retainedWords))
    }

    /// Runs on the audio thread, so it must capture nothing main-actor isolated.
    private nonisolated static func tap(sendingTo forwarder: AnalyzerAudioForwarder) -> AVAudioNodeTapBlock {
        { buffer, _ in forwarder.forward(buffer) }
    }

#if DEBUG
    func debugBeginFileFeed() async {
        startGeneration += 1
        _ = await beginAnalysis(generation: startGeneration)
        status = .listening
    }

    func debugFeed(_ samples: [Float], sampleRate: Double) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        forwarder?.forward(buffer)
    }
#endif
}

/// Converts whatever the input delivers into the analyzer's format. Converting
/// always also copies, which matters because the tap reuses its buffers.
@available(macOS 26.0, *)
private final class AnalyzerAudioForwarder: @unchecked Sendable {
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let outputFormat: AVAudioFormat
    private var converter: AVAudioConverter?

    init(continuation: AsyncStream<AnalyzerInput>.Continuation, outputFormat: AVAudioFormat) {
        self.continuation = continuation
        self.outputFormat = outputFormat
    }

    func forward(_ buffer: AVAudioPCMBuffer) {
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        // `.noDataNow`, not `.endOfStream`: the converter keeps its resampling
        // state from one buffer to the next.
        converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, output.frameLength > 0 else { return }
        continuation.yield(AnalyzerInput(buffer: output))
    }
}
