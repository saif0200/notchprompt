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
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 520, height: 460)
        window.setFrameAutosaveName("NotchpromptSettingsWindow")
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
        // Colour pickers open from this window and must not land behind it.
        NSColorPanel.shared.level = window?.level ?? .floating
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Last-resort if another always-on-top window exists.
        window?.orderFrontRegardless()
    }
}
