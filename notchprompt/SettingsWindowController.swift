//
//  SettingsWindowController.swift
//  notchprompt
//
//  Created by Saif on 2026-02-09.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init() {
        let root = ContentView()
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notchprompt Settings"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("NotchpromptSettingsWindow")
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
        // Last-resort if another always-on-top window exists.
        window?.orderFrontRegardless()
    }
}

