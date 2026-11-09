//
//  ScriptFileIO.swift
//  notchprompt
//
//  Created by Codex on 2026-02-14.
//

import AppKit
import Foundation
import PDFKit

enum ScriptFileIOError: LocalizedError {
    case unableToDecode
    case unsupportedImportFormat(String)
    case unsupportedExportFormat(String)
    case documentConversionFailed(String)
    case noTextFound(String)

    var errorDescription: String? {
        switch self {
        case .unableToDecode:
            return "Couldn't read text from this file."
        case .unsupportedImportFormat(let ext):
            return "Import format .\(ext) is not supported."
        case .unsupportedExportFormat(let ext):
            return "Export format .\(ext) is not supported."
        case .documentConversionFailed(let ext):
            return "Couldn't convert the .\(ext) document."
        case .noTextFound(let message):
            return message
        }
    }
}

enum ScriptFileIO {
    static func importText(from url: URL) async throws -> String {
        try await runOnBackgroundQueue {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try importTextSync(from: url)
        }
    }

    static func exportText(_ text: String, to url: URL) async throws {
        try await runOnBackgroundQueue {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try exportTextSync(text, to: url)
            return ()
        }
    }

    private static func importTextSync(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()

        if importPdfExtensions.contains(ext) {
            guard let text = importPDFText(url) else {
                throw ScriptFileIOError.noTextFound("This PDF has no selectable text. A scanned PDF needs OCR first.")
            }
            return text
        }

        if ext == "pptx" {
            guard let text = importPowerPointNotes(url) else {
                throw ScriptFileIOError.noTextFound("This presentation has no speaker notes to import.")
            }
            return text
        }

        if ext == "pages" {
            throw ScriptFileIOError.noTextFound("Pages files can't be read directly. In Pages, choose File, Export To, Word, then import that.")
        }

        if importOfficeExtensions.contains(ext) {
            if let text = importWithTextutil(url) {
                return text
            }
            if let text = importOfficeAttributedText(url) {
                return text
            }
            throw ScriptFileIOError.documentConversionFailed(ext)
        }

        if importRichExtensions.contains(ext), let text = importRichText(url) {
            return text
        }

        if importTextLikeExtensions.contains(ext), let text = importDirectText(url) {
            return text
        }

        if let text = importDirectText(url) {
            return text
        }

        if ext.isEmpty {
            throw ScriptFileIOError.unableToDecode
        }
        throw ScriptFileIOError.unsupportedImportFormat(ext)
    }

    private static func exportTextSync(_ text: String, to url: URL) throws {
        let ext = url.pathExtension.lowercased()
        if exportDirectTextExtensions.contains(ext) {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        if exportRichExtensions.contains(ext) {
            let attributed = NSAttributedString(string: text)
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            try data.write(to: url, options: .atomic)
            return
        }

        if exportTextutilExtensions.contains(ext) {
            try exportWithTextutil(text: text, format: ext, destination: url)
            return
        }

        throw ScriptFileIOError.unsupportedExportFormat(ext)
    }

    private static let importTextLikeExtensions: Set<String> = [
        "", "txt", "text", "md", "markdown", "csv", "json", "xml", "yaml", "yml", "log"
    ]

    private static let importOfficeExtensions: Set<String> = [
        "docx", "doc", "odt"
    ]

    private static let importRichExtensions: Set<String> = [
        "rtf", "rtfd"
    ]

    private static let importPdfExtensions: Set<String> = [
        "pdf"
    ]

    private static let exportDirectTextExtensions: Set<String> = [
        "", "txt", "text", "md", "markdown"
    ]

    private static let exportRichExtensions: Set<String> = [
        "rtf"
    ]

    private static let exportTextutilExtensions: Set<String> = [
        "docx", "odt"
    ]

    private static func importDirectText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ScriptTextDecoding.decode(data)
    }

    private static func importPDFText(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private static func importWithTextutil(_ url: URL) -> String? {
        guard let data = runTextutil(arguments: ["-convert", "txt", "-stdout", url.path]) else {
            return nil
        }

        if let utf8 = String(data: data, encoding: .utf8),
           !utf8.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return utf8
        }
        if let utf16 = String(data: data, encoding: .utf16),
           !utf16.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return utf16
        }
        return nil
    }

    private static func exportWithTextutil(text: String, format: String, destination: URL) throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let inputURL = tempDir.appendingPathComponent("input.txt")
        try text.write(to: inputURL, atomically: true, encoding: .utf8)

        let outputPath = destination.path
        let args = ["-convert", format, inputURL.path, "-output", outputPath]
        guard runTextutil(arguments: args) != nil || FileManager.default.fileExists(atPath: outputPath) else {
            throw ScriptFileIOError.documentConversionFailed(format)
        }
    }

    private static func runTextutil(arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting: textutil blocks once the pipe's buffer fills, so
        // waiting first hangs forever on any document over about 64 KB of text.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }
        return data
    }

    private static func importOfficeAttributedText(_ url: URL) -> String? {
        for type in [
            NSAttributedString.DocumentType.officeOpenXML,
            NSAttributedString.DocumentType.wordML
        ] {
            if let attributed = try? NSAttributedString(
                url: url,
                options: [.documentType: type],
                documentAttributes: nil
            ) {
                let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return attributed.string
                }
            }
        }
        return nil
    }

    private static func importRichText(_ url: URL) -> String? {
        for type in [
            NSAttributedString.DocumentType.rtf,
            NSAttributedString.DocumentType.rtfd
        ] {
            if let attributed = try? NSAttributedString(
                url: url,
                options: [.documentType: type],
                documentAttributes: nil
            ) {
                let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return attributed.string
                }
            }
        }
        return nil
    }

    private static func importPowerPointNotes(_ url: URL) -> String? {
        // .pptx files are ZIP archives. Notes are in ppt/notesSlides/notesSlide*.xml
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Unzip using ditto
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", url.path, tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let notesDir = tempDir.appendingPathComponent("ppt/notesSlides")
        guard let noteFiles = try? FileManager.default.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil) else {
            return nil
        }

        let names = noteFiles
            .filter { $0.pathExtension.lowercased() == "xml" }
            .map(\.lastPathComponent)

        let allNotes = ScriptTextDecoding.sortedByNumber(names).compactMap { name -> String? in
            guard let data = try? Data(contentsOf: notesDir.appendingPathComponent(name)) else { return nil }
            let text = ScriptTextDecoding.pptxNoteText(xml: data)
            return text.isEmpty ? nil : text
        }

        let combined = allNotes.joined(separator: "\n\n---\n\n")
        return combined.isEmpty ? nil : combined
    }

    private static func runOnBackgroundQueue<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try block())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
