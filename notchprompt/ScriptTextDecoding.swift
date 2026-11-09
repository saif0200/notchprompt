//
//  ScriptTextDecoding.swift
//  notchprompt
//

import Foundation

enum ScriptTextDecoding {
    /// Latin-1 "decodes" any bytes at all, so without this a ZIP or a scanned
    /// PDF lands in the prompter as screens of garbage instead of an error.
    static func looksLikeText(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let sample = data.prefix(8192)
        if hasUTF16ByteOrderMark(data) { return true }
        if sample.contains(0) { return false }
        let controls = sample.filter { $0 < 0x20 && $0 != 0x09 && $0 != 0x0A && $0 != 0x0C && $0 != 0x0D }
        return Double(controls.count) / Double(sample.count) < 0.02
    }

    static func decode(_ data: Data) -> String? {
        guard looksLikeText(data) else { return nil }
        let encodings: [String.Encoding] = hasUTF16ByteOrderMark(data)
            ? [.utf16]
            : [.utf8, .windowsCP1252, .isoLatin1, .macOSRoman]
        for encoding in encodings {
            if let decoded = String(data: data, encoding: encoding),
               !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return decoded
            }
        }
        return nil
    }

    /// `notesSlide10.xml` has to come after `notesSlide2.xml`.
    static func sortedByNumber(_ names: [String]) -> [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The speaker notes of one PowerPoint notes-slide XML, one line per paragraph.
    static func pptxNoteText(xml: Data) -> String {
        let collector = NotesCollector()
        let parser = XMLParser(data: xml)
        parser.delegate = collector
        parser.parse()
        return collector.paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            // PowerPoint stores the slide number as a text run of its own.
            .filter { !$0.isEmpty && Int($0) == nil }
            .joined(separator: "\n")
    }

    private static func hasUTF16ByteOrderMark(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
    }

    private final class NotesCollector: NSObject, XMLParserDelegate {
        var paragraphs: [String] = []
        private var current = ""
        private var isInTextRun = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "a:t" { isInTextRun = true }
            if elementName == "a:p" { current = "" }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if isInTextRun { current += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "a:t" { isInTextRun = false }
            if elementName == "a:p" { paragraphs.append(current) }
        }
    }
}
