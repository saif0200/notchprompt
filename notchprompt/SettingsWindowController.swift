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

        // Cap the initial window height to the available screen space so it
        // fits on smaller MacBook screens (e.g. 13" with ~800pt visible height).
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 860
        let windowHeight = min(860, availableHeight - 40)
        let minHeight = min(760, windowHeight)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notchprompt Settings"
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: minHeight)
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
