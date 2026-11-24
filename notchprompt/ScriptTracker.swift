//
//  ScriptTracker.swift
//  notchprompt
//

import Foundation

/// Finds where in the script the user is, from the trailing words of a speech transcript.
struct ScriptTracker {
    struct Word {
        let text: String
        /// Character offset of the word in the original script.
        let offset: Int
    }

    static let tailLength = 4
    /// Ad-libs and misrecognitions can't drag the position outside this window.
    static let backWindow = 3
    static let forwardWindow = 25
    /// A lone short word ("the") matches far too many places to move on its own.
    static let longWordLength = 6

    private let words: [Word]
    private let scriptLength: Int
    /// Index of the last word the user was heard saying, -1 before the first.
    private(set) var currentWordIndex = -1

    init(script: String) {
        words = Self.tokenize(script)
        scriptLength = max(1, script.count)
    }

    var progress: Double {
        // Position on the word to be read next, so a pause after a line's last word already shows the next line.
        let next = min(currentWordIndex + 1, words.count - 1)
        guard words.indices.contains(next) else { return 0 }
        let word = words[next]
        return Double(word.offset) / Double(scriptLength)
    }

    mutating func reset() { currentWordIndex = -1 }

    /// Takes the whole partial transcription; returns the new word index only when it changed.
    mutating func update(recognized: String) -> Int? {
        let tail = Self.tokenize(recognized).suffix(Self.tailLength).map(\.text)
        let words = self.words
        guard !tail.isEmpty, !words.isEmpty else { return nil }

        let current = currentWordIndex
        func qualifies(_ p: Int) -> Bool {
            var k = 0
            while k < tail.count, p - k >= 0, Self.sameWord(words[p - k].text, tail[tail.count - 1 - k]) { k += 1 }
            // The very next word is the likeliest thing said, so one ordinary word is enough to step onto it.
            let isNext = p == current + 1 && words[p].text.count >= 3
            return k >= 2 || (k == 1 && (words[p].text.count >= Self.longWordLength || isNext))
        }

        // The recognizer re-sending words we already matched must not hop to a repeat further on.
        if currentWordIndex >= 0, qualifies(currentWordIndex) { return nil }

        let hi = min(words.count - 1, currentWordIndex + Self.forwardWindow)
        let lo = max(0, currentWordIndex - Self.backWindow)
        let forward = stride(from: currentWordIndex + 1, through: hi, by: 1)
        let back = stride(from: currentWordIndex - 1, through: lo, by: -1)
        // Lost the user (read ahead, or started mid-script): a full 4-word run that appears exactly once is safe to jump to.
        func relocate() -> Int? {
            guard tail.count >= Self.tailLength else { return nil }
            let hits = words.indices.filter { p in p >= tail.count - 1 && (0..<tail.count).allSatisfy { k in words[p - k].text == tail[tail.count - 1 - k] } }
            return hits.count == 1 ? hits[0] : nil
        }
        guard let hit = forward.first(where: qualifies) ?? back.first(where: qualifies) ?? relocate(), hit != currentWordIndex else { return nil }
        currentWordIndex = hit
        return hit
    }

    /// Lowercased words with punctuation stripped; apostrophes stay inside words.
    static func tokenize(_ text: String) -> [Word] {
        var out: [Word] = []
        var buffer = ""
        var start = 0

        func flush() {
            while buffer.hasSuffix("'") { buffer.removeLast() }
            if !buffer.isEmpty { out.append(Word(text: buffer, offset: start)) }
            buffer = ""
        }

        for (i, ch) in text.enumerated() {
            if ch.isLetter || ch.isNumber {
                if buffer.isEmpty { start = i }
                buffer += ch.lowercased()
            } else if (ch == "'" || ch == "\u{2019}"), !buffer.isEmpty {
                buffer += "'"
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    /// The recognizer often returns near-misses ("lines" for "line", "lime"): one edit apart counts for words of 4+ letters.
    static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        guard min(a.count, b.count) >= 4, abs(a.count - b.count) <= 1 else { return false }
        let x = Array(a), y = Array(b)
        var i = 0, j = 0, edits = 0
        while i < x.count && j < y.count {
            if x[i] == y[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if x.count > y.count { i += 1 } else if y.count > x.count { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (x.count - i) + (y.count - j) <= 1
    }
}
