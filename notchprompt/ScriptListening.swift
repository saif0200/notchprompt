//
//  ScriptListening.swift
//  notchprompt
//
//  The two speech engines that can follow a script. Each hands over the tail of
//  what it has heard, and ScriptAlignmentEngine works out where that is.
//

import Combine
import Foundation

enum SpeechEngineChoice: String, CaseIterable {
    case apple
    case whisper

    var label: String {
        switch self {
        case .apple: return "Apple Speech"
        case .whisper: return "Whisper"
        }
    }

    static var isAppleAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Apple's engine needs macOS 26. Whisper ships in the app and runs anywhere.
    static var preferred: SpeechEngineChoice { isAppleAvailable ? .apple : .whisper }
    static var available: [SpeechEngineChoice] { isAppleAvailable ? [.apple, .whisper] : [.whisper] }
}

@MainActor
protocol ScriptListeningEngine: AnyObject {
    var heardWordsPublisher: AnyPublisher<[String], Never> { get }
    var statusPublisher: AnyPublisher<VoiceInputStatus, Never> { get }
    var preparationPublisher: AnyPublisher<ModelLoadState, Never> { get }
    var isPrepared: Bool { get }

    func prepare() async
    func start()
    func stop()

#if DEBUG
    func debugBeginFileFeed() async
    func debugFeed(_ samples: [Float], sampleRate: Double)
#endif
}
