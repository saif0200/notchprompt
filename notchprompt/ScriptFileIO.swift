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

        if importPdfExtensions.contains(ext), let text = importPDFText(url) {
            return text
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
        "docx", "doc", "odt", "pages"
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
        if let data = try? Data(contentsOf: url) {
            for encoding in [String.Encoding.utf8, .utf16, .unicode, .isoLatin1, .macOSRoman] {
                if let decoded = String(data: data, encoding: encoding) {
                    let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return decoded
                    }
                }
            }
        }
        return nil
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
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }
        return output.fileHandleForReading.readDataToEndOfFile()
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
