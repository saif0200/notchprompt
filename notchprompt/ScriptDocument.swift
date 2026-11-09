//
//  ScriptDocument.swift
//  notchprompt
//
//  A script as the prompter reads it: the text to draw, and every spoken word
//  with its exact place in that text. A line holding only `---` is a section
//  break: it's drawn as a rule and never counted as a word.
//

import Foundation

struct ScriptWord: Equatable {
    let index: Int
    let text: String
    let normalized: String
    /// Where this word sits in `ScriptDocument.displayText`.
    let range: NSRange
}

struct ScriptDocument: Equatable {
    static let sectionRule = "\u{2015}\u{2015}\u{2015}"

    let displayText: String
    let words: [ScriptWord]
    /// Ranges of the section rules within `displayText`.
    let sectionRules: [NSRange]

    var wordCount: Int { words.count }
    var isEmpty: Bool { words.isEmpty }

    init(script: String) {
        let normalized = script
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var display = ""
        var rules: [NSRange] = []
        var wordRanges: [NSRange] = []
        var utf16Offset = 0

        let lines = normalized.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            let isRule = line.trimmingCharacters(in: .whitespaces) == "---"
            let drawn = isRule ? Self.sectionRule : line
            if isRule {
                rules.append(NSRange(location: utf16Offset, length: (drawn as NSString).length))
            } else {
                for range in Self.wordRanges(in: drawn) {
                    wordRanges.append(NSRange(location: utf16Offset + range.location, length: range.length))
                }
            }
            display += drawn
            utf16Offset += (drawn as NSString).length
            if lineIndex < lines.count - 1 {
                display += "\n"
                utf16Offset += 1
            }
        }

        let nsDisplay = display as NSString
        displayText = display
        sectionRules = rules
        words = wordRanges.enumerated().map { index, range in
            let text = nsDisplay.substring(with: range)
            return ScriptWord(index: index, text: text, normalized: Self.normalize(text), range: range)
        }
    }

    private static let wordExpression = try! NSRegularExpression(pattern: "\\S+")

    private static func wordRanges(in line: String) -> [NSRange] {
        let whole = NSRange(location: 0, length: (line as NSString).length)
        return wordExpression.matches(in: line, range: whole).map(\.range)
    }

    /// Lowercase, apostrophes dropped (straight or curly, so "don’t" pasted from
    /// Word matches the "don't" Whisper hears), surrounding punctuation trimmed.
    static func normalize(_ word: String) -> String {
        word.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
    }
}
