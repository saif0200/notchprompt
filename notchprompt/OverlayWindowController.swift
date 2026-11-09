//
//  OverlayWindowController.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Key status has to be in place before the event reaches SwiftUI, or buttons
    /// in a non-activating panel ignore real clicks. Only a click takes focus:
    /// showing the island never does.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if !isKeyWindow { makeKey() }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let view = contentView else { return }
        let model = PrompterModel.shared
        let menu = NSMenu()
        let playing = model.isRunning || model.isCountingDown
        addItem(to: menu, playing ? "Pause" : "Start", #selector(toggleRunning))
        menu.addItem(.separator())
        addItem(to: menu, "Paste Script", #selector(pasteScript))
        addItem(to: menu, "Clear Script", #selector(clearScript))
        menu.addItem(.separator())
        addItem(to: menu, "Script Editor\u{2026}", #selector(openEditor))
        addItem(to: menu, "Settings\u{2026}", #selector(openSettings))
        menu.addItem(.separator())
        addItem(to: menu, "Hide Island", #selector(hideIsland))
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleRunning() { PrompterModel.shared.toggleRunning() }
    @objc private func pasteScript() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        PrompterModel.shared.pasteScript(text)
    }
    @objc private func clearScript() { PrompterModel.shared.clearScript() }
    @objc private func openEditor() { NSApp.sendAction(#selector(AppDelegate.openScriptEditorFromOverlay), to: nil, from: nil) }
    @objc private func openSettings() { NSApp.sendAction(#selector(AppDelegate.openSettingsFromOverlay), to: nil, from: nil) }
    @objc private func hideIsland() { PrompterModel.shared.isOverlayVisible = false }
}

/// The first click on a window that isn't key would otherwise only focus it.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayWindowController {
    /// Long enough for the SwiftUI spring to finish inside the larger frame.
    private static let shrinkDelay: TimeInterval = 0.55

    private let model: PrompterModel
    private let panel: OverlayPanel
    private let placement: IslandPlacement
    private var cancellables: Set<AnyCancellable> = []
    private var shrinkWork: DispatchWorkItem?
    private var panelForm: IslandForm

    init(model: PrompterModel) {
        self.model = model
        panelForm = model.islandForm
        placement = IslandPlacement(layout: Self.makeLayout(for: model, on: Self.targetScreen(for: model)))

        let frame = placement.layout.panelFrame(for: panelForm)
        panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.sharingType = model.privacyModeEnabled ? .none : .readOnly

        let hosting = FirstClickHostingView(rootView: OverlayView(model: model, placement: placement))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting

        wireModel()
    }

    private func wireModel() {
        model.$islandForm
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] form in self?.apply(form: form) }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$overlayWidth, model.$overlayHeight)
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reposition() }
            .store(in: &cancellables)

        model.$selectedScreenID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        model.$islandAttachment
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        model.$islandVerticalNudge
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        model.$privacyModeEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.panel.sharingType = enabled ? .none : .readOnly
            }
            .store(in: &cancellables)

        model.$isOverlayVisible
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in self?.setVisible(isVisible) }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible {
            reposition()
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    /// Re-reads the display and places the island on its camera.
    func reposition() {
        let layout = Self.makeLayout(for: model, on: Self.targetScreen(for: model))
        if placement.layout != layout { placement.layout = layout }
        shrinkWork?.cancel()
        panelForm = model.islandForm
        setPanelFrame(layout.panelFrame(for: panelForm))
    }

    /// The window grows first so the animation has room, and shrinks only after
    /// it has finished. It never animates itself: that's what made resizing judder.
    private func apply(form: IslandForm) {
        let layout = placement.layout
        let target = layout.panelFrame(for: form)
        shrinkWork?.cancel()

        if target.width >= panel.frame.width, target.height >= panel.frame.height {
            panelForm = form
            setPanelFrame(target)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.panelForm = form
            self.setPanelFrame(self.placement.layout.panelFrame(for: form))
        }
        shrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkDelay, execute: work)
    }

    private func setPanelFrame(_ frame: CGRect) {
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true, animate: false)
    }

    private static func makeLayout(for model: PrompterModel, on screen: NSScreen?) -> IslandLayout {
        let requested = CGSize(width: model.overlayWidth, height: model.overlayHeight)
        guard let screen else {
            return IslandLayout(
                edge: DisplayTopEdge(
                    screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                    cutout: nil,
                    menuBarHeight: IslandLayout.fallbackBandHeight,
                    backingScale: 2
                ),
                requestedAttachment: model.islandAttachment,
                requestedExpandedSize: requested,
                verticalNudge: CGFloat(model.islandVerticalNudge)
            )
        }

        let edge = DisplayTopEdge(
            screenFrame: screen.frame,
            cutout: DisplayTopEdge.cutout(
                screenFrame: screen.frame,
                auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                auxiliaryTopRight: screen.auxiliaryTopRightArea
            ),
            menuBarHeight: max(0, screen.frame.maxY - screen.visibleFrame.maxY),
            backingScale: screen.backingScaleFactor
        )
        return IslandLayout(
            edge: edge,
            requestedAttachment: model.islandAttachment,
            requestedExpandedSize: requested,
            verticalNudge: CGFloat(model.islandVerticalNudge)
        )
    }

    private static func targetScreen(for model: PrompterModel) -> NSScreen? {
        let screens = NSScreen.screens
        let descriptors = screens.compactMap { screen -> ScreenDescriptor? in
            guard let id = displayID(for: screen) else { return nil }
            return ScreenDescriptor(
                id: id,
                localizedName: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMenuBarScreen: id == CGMainDisplayID()
            )
        }

        guard let targetID = ScreenSelection.chooseScreenID(
            selectedScreenID: model.selectedScreenID,
            screens: descriptors
        ) else {
            return NSScreen.main ?? screens.first
        }
        return screens.first { displayID(for: $0) == targetID }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

#if DEBUG
    var debugWindow: NSWindow { panel }
#endif
}
