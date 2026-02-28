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
    private let shortcutModifiers: NSEvent.ModifierFlags = [.command, .option]

    private let model = PrompterModel.shared

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var scriptEditorWindowController: ScriptEditorWindowController?
    private var cancellables: Set<AnyCancellable> = []

    private var startPauseItem: NSMenuItem?
    private var showOverlayItem: NSMenuItem?
    private var privacyModeItem: NSMenuItem?
    private var speedUpItem: NSMenuItem?
    private var speedDownItem: NSMenuItem?
    private var shortcutWarningItem: NSMenuItem?
    private var shortcutWarningDetailItem: NSMenuItem?
    private var shortcutWarningSeparator: NSMenuItem?
    private lazy var hotkeyManager = GlobalHotkeyManager { [weak self] command in
        self?.performShortcut(command)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.loadFromDefaults()
        overlayController = OverlayWindowController(model: model)
        overlayController?.setVisible(model.isOverlayVisible)

#if DEBUG
        ScreenSelectionSelfTests.run()
        runShortcutSelfChecks()
#endif

        wireModel()
        hotkeyManager.registerAll()
        setupStatusBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveToDefaults()
        hotkeyManager.unregisterAll()
        cancellables.removeAll()
    }

    private func wireModel() {
        model.$privacyModeEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.overlayController?.setPrivacyMode(enabled)
            }
            .store(in: &cancellables)
        
        model.$isOverlayVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                self?.overlayController?.setVisible(isVisible)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$overlayWidth, model.$overlayHeight)
            .removeDuplicates { lhs, rhs in
                Int(lhs.0) == Int(rhs.0) && Int(lhs.1) == Int(rhs.1)
            }
            .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)

        model.$selectedScreenID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
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

        Publishers.MergeMany(
            model.$script.map { _ in () }.eraseToAnyPublisher(),
            model.$isRunning.map { _ in () }.eraseToAnyPublisher(),
            model.$privacyModeEnabled.map { _ in () }.eraseToAnyPublisher(),
            model.$speedPointsPerSecond.map { _ in () }.eraseToAnyPublisher(),
            model.$fontSize.map { _ in () }.eraseToAnyPublisher(),
            model.$overlayWidth.map { _ in () }.eraseToAnyPublisher(),
            model.$overlayHeight.map { _ in () }.eraseToAnyPublisher(),
            model.$countdownSeconds.map { _ in () }.eraseToAnyPublisher(),
            model.$countdownBehavior.map { _ in () }.eraseToAnyPublisher(),
            model.$scrollMode.map { _ in () }.eraseToAnyPublisher(),
            model.$selectedScreenID.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.model.saveToDefaults()
        }
        .store(in: &cancellables)
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "NP"
        item.button?.toolTip = "Notchprompt"

        let menu = NSMenu()

        let startPause = NSMenuItem(
            title: "Start/Pause (Option+Command+P)",
            action: #selector(toggleRunning),
            keyEquivalent: ShortcutCommand.startPause.keyEquivalent
        )
        startPause.target = self
        startPause.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(startPause)
        startPauseItem = startPause

        let reset = NSMenuItem(
            title: "Reset Scroll (Option+Command+R)",
            action: #selector(resetScroll),
            keyEquivalent: ShortcutCommand.reset.keyEquivalent
        )
        reset.target = self
        reset.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(reset)

        let jumpBack = NSMenuItem(
            title: "Jump Back 5s (Option+Command+J)",
            action: #selector(jumpBack),
            keyEquivalent: ShortcutCommand.jumpBack.keyEquivalent
        )
        jumpBack.target = self
        jumpBack.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(jumpBack)

        let privacyMode = NSMenuItem(
            title: "Privacy Mode (Option+Command+H)",
            action: #selector(togglePrivacyMode),
            keyEquivalent: ShortcutCommand.togglePrivacy.keyEquivalent
        )
        privacyMode.target = self
        privacyMode.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(privacyMode)
        privacyModeItem = privacyMode

        let showOverlay = NSMenuItem(
            title: "Show Overlay (Option+Command+O)",
            action: #selector(toggleOverlayVisibility),
            keyEquivalent: ShortcutCommand.toggleOverlay.keyEquivalent
        )
        showOverlay.target = self
        showOverlay.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(showOverlay)
        showOverlayItem = showOverlay

        let speedUp = NSMenuItem(
            title: "Increase Speed (Option+Command+=)",
            action: #selector(increaseSpeed),
            keyEquivalent: ShortcutCommand.speedUp.keyEquivalent
        )
        speedUp.target = self
        speedUp.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(speedUp)
        speedUpItem = speedUp

        let speedDown = NSMenuItem(
            title: "Decrease Speed (Option+Command+-)",
            action: #selector(decreaseSpeed),
            keyEquivalent: ShortcutCommand.speedDown.keyEquivalent
        )
        speedDown.target = self
        speedDown.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(speedDown)
        speedDownItem = speedDown

        refreshShortcutWarningItems(in: menu)

        menu.addItem(.separator())

        let openScriptEditor = NSMenuItem(title: "Script Editor…", action: #selector(openScriptEditorWindow), keyEquivalent: "")
        openScriptEditor.target = self
        menu.addItem(openScriptEditor)

        menu.addItem(.separator())

        let open = NSMenuItem(title: "Settings…", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Notchprompt", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    // MARK: - Actions

    @objc private func toggleRunning() {
        model.toggleRunning()
    }

    @objc private func resetScroll() {
        model.resetScroll()
    }

    @objc private func jumpBack() {
        model.jumpBack(seconds: 5)
    }

    @objc private func togglePrivacyMode() {
        model.privacyModeEnabled.toggle()
    }
    
    @objc private func toggleOverlayVisibility() {
        model.isOverlayVisible.toggle()
    }

    @objc private func increaseSpeed() {
        model.adjustSpeed(delta: PrompterModel.speedStep)
    }

    @objc private func decreaseSpeed() {
        model.adjustSpeed(delta: -PrompterModel.speedStep)
    }

    @objc private func openMainWindow() {
        Task { @MainActor in
            if settingsWindowController == nil {
                settingsWindowController = SettingsWindowController()
            }
            settingsWindowController?.show()
        }
    }
    
    @objc private func openScriptEditorWindow() {
        Task { @MainActor in
            if scriptEditorWindowController == nil {
                scriptEditorWindowController = ScriptEditorWindowController()
            }
            scriptEditorWindowController?.show()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func performShortcut(_ command: ShortcutCommand) {
        switch command {
        case .startPause:
            model.toggleRunning()
        case .reset:
            model.resetScroll()
        case .jumpBack:
            model.jumpBack(seconds: 5)
        case .togglePrivacy:
            model.privacyModeEnabled.toggle()
        case .toggleOverlay:
            model.isOverlayVisible.toggle()
        case .speedUp:
            model.adjustSpeed(delta: PrompterModel.speedStep)
        case .speedDown:
            model.adjustSpeed(delta: -PrompterModel.speedStep)
        }
    }

    private func refreshShortcutWarningItems(in menu: NSMenu) {
        if let shortcutWarningItem {
            menu.removeItem(shortcutWarningItem)
            self.shortcutWarningItem = nil
        }
        if let shortcutWarningDetailItem {
            menu.removeItem(shortcutWarningDetailItem)
            self.shortcutWarningDetailItem = nil
        }
        if let shortcutWarningSeparator {
            menu.removeItem(shortcutWarningSeparator)
            self.shortcutWarningSeparator = nil
        }

        let unavailable = hotkeyManager.failedRegistrations
        guard !unavailable.isEmpty else { return }

        if unavailable.count == 1, let first = unavailable.first {
            let warning = NSMenuItem(
                title: "Shortcut unavailable: \(first.displayShortcut) (in use by another app)",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.insertItem(warning, at: 0)
            shortcutWarningItem = warning
        } else {
            let warning = NSMenuItem(
                title: "Shortcuts unavailable (\(unavailable.count))",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.insertItem(warning, at: 0)
            shortcutWarningItem = warning

            let detail = unavailable
                .map(\.displayShortcut)
                .joined(separator: ", ")
            let detailItem = NSMenuItem(
                title: "In use by another app: \(detail)",
                action: nil,
                keyEquivalent: ""
            )
            detailItem.isEnabled = false
            menu.insertItem(detailItem, at: 1)
            shortcutWarningDetailItem = detailItem
        }

        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: unavailable.count == 1 ? 1 : 2)
        shortcutWarningSeparator = separator
    }

#if DEBUG
    private func runShortcutSelfChecks() {
        GlobalHotkeyManager.runSelfChecks()
    }
#endif

    // MARK: - Menu Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === startPauseItem {
            menuItem.title = model.isRunning ? "Pause (Option+Command+P)" : "Start (Option+Command+P)"
            return true
        }

        if menuItem === privacyModeItem {
            menuItem.state = model.privacyModeEnabled ? .on : .off
            return true
        }
        
        if menuItem === showOverlayItem {
            menuItem.state = model.isOverlayVisible ? .on : .off
            return true
        }

        if menuItem === speedUpItem || menuItem === speedDownItem {
            return true
        }

        return true
    }
}
