//
//  ScriptLibraryWindowController.swift
//  notchprompt
//

import AppKit
import SwiftUI

@MainActor
final class ScriptLibraryWindowController: NSWindowController {
    init() {
        let root = ScriptLibraryView()
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Script Library"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)
        window.setFrameAutosaveName("NotchpromptScriptLibraryWindow")
        // Sit above the overlay panel (.screenSaver) so the notch never blocks this window.
        window.level = NSWindow.Level(Int(NSWindow.Level.screenSaver.rawValue) + 1)
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
