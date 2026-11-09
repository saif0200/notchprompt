//
//  ScriptAlignmentEngine.swift
//  notchprompt
//
//  Works out where in the script the speaker is, from the last few words heard.
//

import Foundation

enum AlignmentConfidence: String {
    case high, medium, low, lost
}

final class ScriptAlignmentEngine {
    private(set) var currentWordIndex: Int = -1
    private(set) var confidence: AlignmentConfidence = .high

    private var scriptWords: [ScriptWord] = []
    private var lostCount = 0

    private let windowSize = 12
    private let segmentPadding = 3
    private let similarityThreshold = 0.68
    private let forwardRange = 40
    private let backwardRange = 2
    private let wideForwardRange = 120
    private let wideBackwardRange = 60
    private let lostThreshold = 3

    func setWords(_ words: [ScriptWord]) {
        scriptWords = words
        reset()
    }

    func reset() {
        currentWordIndex = -1
        lostCount = 0
        confidence = .high
    }

    /// `heard` is the tail of what was recognised, oldest first. Passes overlap,
    /// so each one matches the whole tail against the script again and takes the
    /// place the tail's last word best lands on.
    ///
    /// Audio is cut off mid-sentence on every pass, so Whisper's final words are
    /// often invented. Up to two of them may be discounted.
    func process(heard: [String]) {
        guard !scriptWords.isEmpty else { return }
        let spoken = Array(
            heard
                .map(ScriptDocument.normalize)
                .filter { !$0.isEmpty }
                .suffix(windowSize)
        )
        guard !spoken.isEmpty else { return }

        let isLost = lostCount > lostThreshold
        let lower = max(0, currentWordIndex - (isLost ? wideBackwardRange : backwardRange))
        let upper = min(scriptWords.count - 1, currentWordIndex + (isLost ? wideForwardRange : forwardRange))
        guard lower <= upper else { return }

        // One comparison per word pair instead of one per pair per candidate.
        // This runs on the main thread, alongside a 120 Hz scroll.
        let firstCompared = max(0, lower - spoken.count - segmentPadding)
        let similarities = spoken.map { word in
            scriptWords[firstCompared...upper].map { StringSimilarity.normalizedSimilarity(word, $0.normalized) }
        }

        let trimLimit = spoken.count >= 4 ? 2 : 0
        var best: (end: Int, score: Double, matched: Int)?
        for trim in 0...trimLimit {
            let rows = spoken.count - trim
            for end in lower...upper {
                let (raw, matched) = score(rows: rows, endingAt: end, firstCompared: firstCompared, similarities: similarities)
                guard matched > 0 else { continue }
                let distance = Double(abs(end - max(currentWordIndex, 0)))
                let penalised = raw - distance * 0.004 - Double(trim) * 0.05
                if best == nil || penalised > best!.score {
                    best = (end, penalised, matched)
                }
            }
        }

        // One word could be anywhere. Only trust it right at the current spot.
        let requiredMatches = spoken.count >= 6 ? 3 : min(2, spoken.count)
        guard let best,
              best.score > 0.3,
              best.matched >= requiredMatches,
              spoken.count >= 2 || best.end <= currentWordIndex + 3
        else {
            registerMiss()
            return
        }

        // Going backwards needs real evidence: the speaker has to have re-read.
        if best.end < currentWordIndex, best.matched < min(5, spoken.count) {
            return
        }

        currentWordIndex = best.end
        lostCount = 0
        confidence = best.score > 0.62 ? .high : best.score > 0.42 ? .medium : .low
    }

    private func registerMiss() {
        lostCount += 1
        confidence = lostCount > lostThreshold ? .lost : .low
    }

    /// Scores the first `rows` heard words against the script words ending at
    /// `end`, tolerating dropped and misheard words. The result is 0...~1, and the
    /// word at `end` has to match the last or second-last word considered.
    private func score(
        rows wordCount: Int,
        endingAt end: Int,
        firstCompared: Int,
        similarities: [[Double]]
    ) -> (Double, Int) {
        guard wordCount > 0 else { return (0, 0) }
        let start = max(0, end - wordCount - segmentPadding + 1)
        let segment = start...end
        let lastColumn = end - firstCompared

        let tailRows = max(0, wordCount - 2)..<wordCount
        guard tailRows.contains(where: { similarities[$0][lastColumn] > similarityThreshold }) else { return (0, 0) }

        let rows = wordCount + 1
        let columns = segment.count + 1
        var values = [Double](repeating: 0, count: rows * columns)
        var matches = [Int](repeating: 0, count: rows * columns)
        let gap = -0.25

        for row in 1..<rows {
            for column in 1..<columns {
                let index = row * columns + column
                let scriptIndex = start + column - 1
                let similarity = similarities[row - 1][scriptIndex - firstCompared]
                let isMatch = similarity > similarityThreshold
                let weight = min(1, Double(scriptWords[scriptIndex].normalized.count) / 4 + 0.25)
                let diagonal = values[(row - 1) * columns + column - 1] + (isMatch ? similarity * weight : -0.35)
                let skipSpoken = values[(row - 1) * columns + column] + gap
                let skipScript = values[row * columns + column - 1] + gap

                if diagonal >= skipSpoken, diagonal >= skipScript {
                    values[index] = diagonal
                    matches[index] = matches[(row - 1) * columns + column - 1] + (isMatch ? 1 : 0)
                } else if skipSpoken >= skipScript {
                    values[index] = skipSpoken
                    matches[index] = matches[(row - 1) * columns + column]
                } else {
                    values[index] = skipScript
                    matches[index] = matches[row * columns + column - 1]
                }
            }
        }

        let last = rows * columns - 1
        return (values[last] / Double(wordCount), matches[last])
    }
}
