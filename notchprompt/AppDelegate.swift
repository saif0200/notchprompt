//
//  AppDelegate.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let model = PrompterModel.shared

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    private var startPauseItem: NSMenuItem?
    private var clickThroughItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlayController = OverlayWindowController(model: model)
        // Default behavior: always show and always cover the notch / menu bar area.
        overlayController?.setVisible(true)

        wireModel()
        setupStatusBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancellables.removeAll()
    }

    private func wireModel() {
        model.$isClickThrough
            .receive(on: RunLoop.main)
            .sink { [weak self] isClickThrough in
                self?.overlayController?.setClickThrough(isClickThrough)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$overlayWidth, model.$overlayHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
#if DEBUG
                print("[Notchprompt] didChangeScreenParametersNotification")
#endif
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "NP"
        item.button?.toolTip = "Notchprompt"

        let menu = NSMenu()

        let startPause = NSMenuItem(title: "Start", action: #selector(toggleRunning), keyEquivalent: "s")
        startPause.target = self
        menu.addItem(startPause)
        startPauseItem = startPause

        let reset = NSMenuItem(title: "Reset Scroll", action: #selector(resetScroll), keyEquivalent: "r")
        reset.target = self
        menu.addItem(reset)

        let clickThrough = NSMenuItem(title: "Click-Through", action: #selector(toggleClickThrough), keyEquivalent: "c")
        clickThrough.target = self
        menu.addItem(clickThrough)
        clickThroughItem = clickThrough

        menu.addItem(.separator())

        let open = NSMenuItem(title: "Settings…", action: #selector(openMainWindow), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Notchprompt", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    // MARK: - Actions

    @objc private func toggleRunning() {
        model.isRunning.toggle()
    }

    @objc private func resetScroll() {
        model.resetScroll()
    }

    @objc private func toggleClickThrough() {
        model.isClickThrough.toggle()
    }

    @objc private func openMainWindow() {
        Task { @MainActor in
            if settingsWindowController == nil {
                settingsWindowController = SettingsWindowController()
            }
            settingsWindowController?.show()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Menu Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === startPauseItem {
            menuItem.title = model.isRunning ? "Pause" : "Start"
            return true
        }

        if menuItem === clickThroughItem {
            menuItem.state = model.isClickThrough ? .on : .off
            return true
        }

        return true
    }
}
