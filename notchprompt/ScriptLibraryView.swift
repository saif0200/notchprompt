//
//  ScriptLibraryView.swift
//  notchprompt
//

import SwiftUI

struct ScriptLibraryView: View {
    @ObservedObject private var library = ScriptLibraryManager.shared
    @ObservedObject private var model = PrompterModel.shared
    @State private var searchText = ""
    @State private var sortByDate = true
    @State private var renaming: SavedScript?
    @State private var renameText = ""
    @State private var pendingDelete: SavedScript?

    private var visibleScripts: [SavedScript] {
        var result = library.scripts
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || $0.content.localizedCaseInsensitiveContains(searchText)
            }
        }
        if sortByDate {
            result.sort { $0.modifiedAt > $1.modifiedAt }
        } else {
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return result
    }

    var body: some View {
        Group {
            if library.scripts.isEmpty {
                ContentUnavailableView(
                    "No Saved Scripts",
                    systemImage: "books.vertical",
                    description: Text("Save the current script to keep it here.")
                )
            } else if visibleScripts.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(visibleScripts) { script in
                    row(for: script)
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
            }
        }
        .searchable(text: $searchText, prompt: "Search scripts")
        .toolbar {
            ToolbarItemGroup {
                Picker("Sort", selection: $sortByDate) {
                    Text("Recent").tag(true)
                    Text("A to Z").tag(false)
                }
                .pickerStyle(.segmented)

                Button {
                    library.save(content: model.script)
                } label: {
                    Label("Save Current Script", systemImage: "plus")
                }
                .help("Save the current script to your library")
            }
        }
        .alert("Rename Script", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let renaming { library.renameScript(id: renaming.id, newTitle: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete \"\(pendingDelete?.title ?? "")\"?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { library.deleteScript(id: pendingDelete.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func row(for script: SavedScript) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(script.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(script.content.prefix(120).replacingOccurrences(of: "\n", with: " "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(script.modifiedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Load") { model.loadScript(script.content) }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Load") { model.loadScript(script.content) }
            Button("Rename…") {
                renameText = script.title
                renaming = script
            }
            Divider()
            Button("Delete…", role: .destructive) { pendingDelete = script }
        }
    }
}
