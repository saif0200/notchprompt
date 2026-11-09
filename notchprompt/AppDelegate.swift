//
//  AppDelegate.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let model = PrompterModel.shared

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var scriptEditorWindowController: ScriptEditorWindowController?
    private var scriptLibraryWindowController: ScriptLibraryWindowController?
    private var cancellables: Set<AnyCancellable> = []

    private var startPauseItem: NSMenuItem?
    private var showOverlayItem: NSMenuItem?
    private var privacyModeItem: NSMenuItem?
    private var shortcutWarningItems: [NSMenuItem] = []

    private lazy var hotkeyManager = GlobalHotkeyManager { [weak self] command in
        self?.performShortcut(command)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.loadFromDefaults()
        let controller = OverlayWindowController(model: model)
        overlayController = controller
        controller.setVisible(model.isOverlayVisible)

#if DEBUG
        GlobalHotkeyManager.runSelfChecks()
        if OverlayDebugHarness.runIfRequested(model: model, controller: controller) {
            return
        }
#endif

        // Any setting change lands within a moment, without a list to keep in step.
        // Playback ticks hold this off until the read pauses.
        model.objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.model.saveToDefaults() }
            .store(in: &cancellables)

        hotkeyManager.registerAll()
        setupStatusBar()
        installMainMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveToDefaults()
        model.shutDownVoiceInput()
        hotkeyManager.unregisterAll()
        cancellables.removeAll()
    }

    // MARK: - Status item

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.makeStatusIcon()
        item.button?.toolTip = "Notchprompt"
        item.button?.setAccessibilityLabel("Notchprompt")

        let menu = NSMenu()
        startPauseItem = addShortcutItem(to: menu, title: "Start", command: .startPause, action: #selector(toggleRunning))
        addShortcutItem(to: menu, title: "Back to Top", command: .reset, action: #selector(resetScroll))
        addShortcutItem(to: menu, title: "Jump Back 5 Seconds", command: .jumpBack, action: #selector(jumpBack))
        menu.addItem(.separator())
        addShortcutItem(to: menu, title: "Faster", command: .speedUp, action: #selector(increaseSpeed))
        addShortcutItem(to: menu, title: "Slower", command: .speedDown, action: #selector(decreaseSpeed))
        menu.addItem(.separator())
        showOverlayItem = addShortcutItem(to: menu, title: "Show Island", command: .toggleOverlay, action: #selector(toggleOverlayVisibility))
        privacyModeItem = addShortcutItem(to: menu, title: "Hide from Screen Sharing", command: .togglePrivacy, action: #selector(togglePrivacyMode))
        menu.addItem(.separator())
        addItem(to: menu, title: "Script Editor…", action: #selector(openScriptEditorWindow))
        addItem(to: menu, title: "Script Library…", action: #selector(openScriptLibraryWindow))
        addItem(to: menu, title: "Settings…", action: #selector(openSettingsWindow), key: ",", modifiers: [.command])
        menu.addItem(.separator())
        addItem(to: menu, title: "Quit Notchprompt", action: #selector(quitApp), key: "q", modifiers: [.command])

        refreshShortcutWarning(in: menu)
        item.menu = menu
        statusItem = item
    }

    @discardableResult
    private func addShortcutItem(to menu: NSMenu, title: String, command: ShortcutCommand, action: Selector) -> NSMenuItem {
        addItem(to: menu, title: title, action: action, key: command.keyEquivalent, modifiers: command.modifierFlags)
    }

    @discardableResult
    private func addItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
        return item
    }

    /// A small island with lines of script under it.
    private static func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 5, y: 1.5, width: 8, height: 3.5), xRadius: 1.75, yRadius: 1.75).fill()
            for (y, inset) in [(7.75, 1.5), (11.75, 4.0)] as [(CGFloat, CGFloat)] {
                NSBezierPath(
                    roundedRect: NSRect(x: inset, y: y, width: 18 - 2 * inset, height: 1.75),
                    xRadius: 0.875,
                    yRadius: 0.875
                ).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Notchprompt"
        return image
    }

    private func refreshShortcutWarning(in menu: NSMenu) {
        shortcutWarningItems.forEach(menu.removeItem)
        shortcutWarningItems = []

        let unavailable = hotkeyManager.failedRegistrations
        guard !unavailable.isEmpty else { return }

        let keys = unavailable.map(\.displayShortcut).joined(separator: ", ")
        let warning = NSMenuItem(title: "Shortcut in use by another app: \(keys)", action: nil, keyEquivalent: "")
        warning.isEnabled = false
        let separator = NSMenuItem.separator()
        menu.insertItem(warning, at: 0)
        menu.insertItem(separator, at: 1)
        shortcutWarningItems = [warning, separator]
    }

    /// An accessory app has no menu bar of its own, but its windows still need
    /// these for ⌘C, ⌘V, ⌘Z and ⌘W to work.
    private func installMainMenu() {
        let mainMenu = NSApp.mainMenu ?? NSMenu()

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Actions

    @objc private func toggleRunning() { model.toggleRunning() }
    @objc private func resetScroll() { model.resetScroll() }
    @objc private func jumpBack() { model.jumpBack(seconds: 5) }
    @objc private func togglePrivacyMode() { model.privacyModeEnabled.toggle() }
    @objc private func toggleOverlayVisibility() { model.isOverlayVisible.toggle() }
    @objc private func increaseSpeed() { model.adjustSpeed(delta: PrompterModel.speedStep) }
    @objc private func decreaseSpeed() { model.adjustSpeed(delta: -PrompterModel.speedStep) }
    @objc private func quitApp() { NSApp.terminate(nil) }

    @objc func openScriptLibraryFromEditor() { openScriptLibraryWindow() }
    @objc func openScriptEditorFromOverlay() { openScriptEditorWindow() }
    @objc func openSettingsFromOverlay() { openSettingsWindow() }

    @objc private func openSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.show()
    }

    @objc private func openScriptLibraryWindow() {
        if scriptLibraryWindowController == nil {
            scriptLibraryWindowController = ScriptLibraryWindowController()
        }
        scriptLibraryWindowController?.show()
    }

    @objc private func openScriptEditorWindow() {
        if scriptEditorWindowController == nil {
            scriptEditorWindowController = ScriptEditorWindowController()
        }
        scriptEditorWindowController?.show()
    }

    private func performShortcut(_ command: ShortcutCommand) {
        switch command {
        case .startPause: model.toggleRunning()
        case .reset: model.resetScroll()
        case .jumpBack: model.jumpBack(seconds: 5)
        case .togglePrivacy: model.privacyModeEnabled.toggle()
        case .toggleOverlay: model.isOverlayVisible.toggle()
        case .speedUp: model.adjustSpeed(delta: PrompterModel.speedStep)
        case .speedDown: model.adjustSpeed(delta: -PrompterModel.speedStep)
        }
    }

    // MARK: - Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === startPauseItem {
            menuItem.title = (model.isRunning || model.isCountingDown) ? "Pause" : "Start"
        } else if menuItem === privacyModeItem {
            menuItem.state = model.privacyModeEnabled ? .on : .off
        } else if menuItem === showOverlayItem {
            menuItem.state = model.isOverlayVisible ? .on : .off
        }
        return true
    }
}
