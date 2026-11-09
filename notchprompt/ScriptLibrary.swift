//
//  ScriptLibrary.swift
//  notchprompt
//

import Foundation

struct SavedScript: Codable, Identifiable {
    var id: UUID
    var title: String
    var content: String
    var createdAt: Date
    var modifiedAt: Date

    init(title: String, content: String) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

@MainActor
final class ScriptLibraryManager: ObservableObject {
    static let shared = ScriptLibraryManager()

    @Published var scripts: [SavedScript] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Notchprompt", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("scripts.json")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            scripts = try JSONDecoder().decode([SavedScript].self, from: Data(contentsOf: fileURL))
        } catch {
            // Keep the unreadable file: the next save would otherwise replace it
            // with an empty library.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("scripts-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(scripts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Saving the same text again freshens the existing entry instead of adding a twin.
    func save(content: String) {
        if let index = scripts.firstIndex(where: { $0.content == content }) {
            scripts[index].modifiedAt = Date()
        } else {
            scripts.insert(SavedScript(title: Self.title(from: content), content: content), at: 0)
        }
        persist()
    }

    func deleteScript(id: UUID) {
        scripts.removeAll { $0.id == id }
        persist()
    }

    func renameScript(id: UUID, newTitle: String) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = scripts.firstIndex(where: { $0.id == id }) else { return }
        scripts[index].title = title
        scripts[index].modifiedAt = Date()
        persist()
    }

    private static func title(from text: String) -> String {
        let firstLine = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
        return firstLine.isEmpty ? "Untitled Script" : String(firstLine.prefix(50))
    }
}
