//
//  FilePanelCoordinator.swift
//  notchprompt
//
//  Created by Codex on 2026-02-14.
//

import AppKit
import UniformTypeIdentifiers

@MainActor
enum FilePanelCoordinator {
    static func presentImportPanel(from window: NSWindow?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.prompt = "Import"
        panel.message = "Choose a script file. Notchprompt will try to extract text from common document formats."
        return await present(panel: panel, from: window)
    }

    static func presentExportPanel(from window: NSWindow?) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "script.txt"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = exportTypes
        panel.prompt = "Export"
        panel.message = "Export as TXT, MD, RTF, DOCX, or ODT."
        return await present(panel: panel, from: window)
    }

    static var exportTypes: [UTType] {
        [
            .plainText,
            .utf8PlainText,
            .text,
            .rtf,
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "odt") ?? .data
        ]
    }

    private static func present(panel: NSSavePanel, from window: NSWindow?) async -> URL? {
        await withCheckedContinuation { continuation in
            let handler: (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }

            if let window {
                panel.beginSheetModal(for: window, completionHandler: handler)
            } else {
                panel.begin(completionHandler: handler)
            }
        }
    }
}
