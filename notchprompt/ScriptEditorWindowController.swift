//
//  ScriptEditorWindowController.swift
//  notchprompt
//
//  Created by Codex on 2026-02-23.
//

import AppKit
import SwiftUI

@MainActor
final class ScriptEditorWindowController: NSWindowController {
    init() {
        let root = ScriptEditorView()
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notchprompt Script Editor"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 460)
        window.setFrameAutosaveName("NotchpromptScriptEditorWindow")
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}

