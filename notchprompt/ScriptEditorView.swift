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
    @ObservedObject private var library = ScriptLibraryManager.shared
    @State private var fileErrorMessage: String?
    @State private var didJustSave = false

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $model.script)
                .font(.system(size: 15))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            Divider()

            HStack(spacing: 12) {
                Text("\(model.wordCount) words")
                Text("About \(model.formattedEstimatedReadDuration()) at \(Int(model.effectiveWordsPerMinute)) wpm")
                Spacer()
                Text("A line of three dashes (---) starts a new section")
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await importScript() }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import a text, Word, PDF or PowerPoint file")

                Button {
                    Task { await exportScript() }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export this script")

                Button {
                    saveToLibrary()
                } label: {
                    Label(didJustSave ? "Saved" : "Save to Library", systemImage: didJustSave ? "checkmark" : "bookmark")
                }
                .help("Save this script to your library")

                Button {
                    NSApp.sendAction(#selector(AppDelegate.openScriptLibraryFromEditor), to: nil, from: nil)
                } label: {
                    Label("Library", systemImage: "books.vertical")
                }
                .help("Open your script library")
            }
        }
        .alert("That didn't work", isPresented: Binding(
            get: { fileErrorMessage != nil },
            set: { if !$0 { fileErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileErrorMessage ?? "")
        }
    }

    private func saveToLibrary() {
        library.save(content: model.script)
        didJustSave = true
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            didJustSave = false
        }
    }

    @MainActor
    private func importScript() async {
        guard let url = await FilePanelCoordinator.presentImportPanel(from: NSApp.keyWindow) else { return }
        do {
            model.loadScript(try await ScriptFileIO.importText(from: url))
        } catch {
            fileErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exportScript() async {
        guard let url = await FilePanelCoordinator.presentExportPanel(from: NSApp.keyWindow) else { return }
        do {
            try await ScriptFileIO.exportText(model.script, to: url)
        } catch {
            fileErrorMessage = error.localizedDescription
        }
    }
}
