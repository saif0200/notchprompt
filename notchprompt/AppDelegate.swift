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
    private var cancellables: Set<AnyCancellable> = []

    private var startPauseItem: NSMenuItem?
    private var showOverlayItem: NSMenuItem?
    private var privacyModeItem: NSMenuItem?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.loadFromDefaults()
        overlayController = OverlayWindowController(model: model)
        overlayController?.setVisible(model.isOverlayVisible)

#if DEBUG
        ScreenSelectionSelfTests.run()
#endif

        wireModel()
        setupStatusBar()
        setupKeyboardShortcuts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveToDefaults()
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
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

        let startPause = NSMenuItem(title: "Start/Pause (Opt+Cmd+P)", action: #selector(toggleRunning), keyEquivalent: "p")
        startPause.target = self
        startPause.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(startPause)
        startPauseItem = startPause

        let reset = NSMenuItem(title: "Reset Scroll (Opt+Cmd+R)", action: #selector(resetScroll), keyEquivalent: "r")
        reset.target = self
        reset.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(reset)

        let jumpBack = NSMenuItem(title: "Jump Back 5s (Opt+Cmd+J)", action: #selector(jumpBack), keyEquivalent: "j")
        jumpBack.target = self
        jumpBack.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(jumpBack)

        let privacyMode = NSMenuItem(title: "Privacy Mode", action: #selector(togglePrivacyMode), keyEquivalent: "h")
        privacyMode.target = self
        privacyMode.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(privacyMode)
        privacyModeItem = privacyMode
        
        let showOverlay = NSMenuItem(title: "Show Overlay (Opt+Cmd+O)", action: #selector(toggleOverlayVisibility), keyEquivalent: "o")
        showOverlay.target = self
        showOverlay.keyEquivalentModifierMask = [.option, .command]
        menu.addItem(showOverlay)
        showOverlayItem = showOverlay

        menu.addItem(.separator())

        let openScriptEditor = NSMenuItem(title: "Script Editor…", action: #selector(openScriptEditorWindow), keyEquivalent: "e")
        openScriptEditor.target = self
        menu.addItem(openScriptEditor)

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

    private func setupKeyboardShortcuts() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleShortcut(event) == true {
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleShortcut(event)
        }
    }

    @discardableResult
    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let required: NSEvent.ModifierFlags = [.command, .option]
        guard flags.contains(required) else { return false }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p":
            model.toggleRunning()
            return true
        case "r":
            model.resetScroll()
            return true
        case "j":
            model.jumpBack(seconds: 5)
            return true
        case "o":
            model.isOverlayVisible.toggle()
            return true
        case "=":
            model.adjustSpeed(delta: PrompterModel.speedStep)
            return true
        case "-":
            model.adjustSpeed(delta: -PrompterModel.speedStep)
            return true
        default:
            return false
        }
    }

    // MARK: - Menu Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === startPauseItem {
            menuItem.title = model.isRunning ? "Pause (Opt+Cmd+P)" : "Start (Opt+Cmd+P)"
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

        return true
    }
}
