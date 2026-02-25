//
//  ScriptEditorView.swift
//  notchprompt
//
//  Created by Codex on 2026-02-23.
//

import AppKit
import SwiftUI

struct ScriptEditorView: View {
    @ObservedObject private var model = PrompterModel.shared
    @State private var fileErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Import...") {
                    Task {
                        await importScriptAsync()
                    }
                }

                Button("Export...") {
                    Task {
                        await exportScriptAsync()
                    }
                }

                Spacer()

                Text("Estimated read time: \(model.formattedEstimatedReadDuration())")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $model.script)
                .font(.system(size: 13, design: .monospaced))
        }
        .padding(14)
        .alert("File Operation Failed", isPresented: Binding(
            get: { fileErrorMessage != nil },
            set: { _ in fileErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileErrorMessage ?? "This file operation could not be completed.")
        }
    }

    @MainActor
    private func importScriptAsync() async {
        let url = await FilePanelCoordinator.presentImportPanel(from: NSApp.keyWindow)
        guard let url else { return }
        do {
            model.script = try await ScriptFileIO.importText(from: url)
        } catch {
            fileErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exportScriptAsync() async {
        let url = await FilePanelCoordinator.presentExportPanel(from: NSApp.keyWindow)
        guard let url else { return }
        do {
            try await ScriptFileIO.exportText(model.script, to: url)
        } catch {
            fileErrorMessage = error.localizedDescription
        }
    }
}

