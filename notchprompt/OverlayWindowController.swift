//
//  OverlayWindowController.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let model: PrompterModel
    private let panel: NSPanel
    // Keep this at 0 to hug the notch/menu bar boundary like other notch-adjacent apps.
    // We still position using `visibleFrame` so we never enter the reserved top strip.
    private let padding: CGFloat = 0
    private let inMenuBarStrip: Bool = true

    init(model: PrompterModel) {
        self.model = model

        let hosting = NSHostingView(rootView: OverlayView(model: model))

        let initialFrame = NSRect(x: 0, y: 0, width: model.overlayWidth, height: model.overlayHeight)
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        // Use .screenSaver level to ensure it sits above the menu bar and covers the notch area.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        // panel.isFloatingPanel = true // This overrides level to .floating (3)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = model.isClickThrough
        panel.sharingType = model.privacyModeEnabled ? .none : .readOnly

        panel.contentView = hosting
        self.panel = panel

        reposition()

#if DEBUG
        debugDump(reason: "init-after-reposition", intendedScreen: Self.mainDisplayScreen(), calc: nil)
#endif
    }

    func setVisible(_ isVisible: Bool) {
#if DEBUG
        debugDump(reason: "setVisible-before isVisible=\(isVisible)", intendedScreen: Self.mainDisplayScreen(), calc: nil)
#endif
        if isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
#if DEBUG
        debugDump(reason: "setVisible-after isVisible=\(isVisible)", intendedScreen: Self.mainDisplayScreen(), calc: nil)
#endif
    }

    func reposition() {
        // Always place on the system "main display" (the one that owns the menu bar),
        // not on an extended display.
        guard let screen = Self.mainDisplayScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let width = CGFloat(model.overlayWidth)
        let desiredHeight = CGFloat(model.overlayHeight)

        let x = screen.frame.midX - (width / 2)

        // Always pin to the very top of the physical screen so we cover the notch/menu bar
        // even when macOS auto-hides the menu bar (reservedTop may report as 0).
        let height = desiredHeight
        let topRefY = screen.frame.maxY
        let y = topRefY - height - padding

#if DEBUG
        debugDump(
            reason: "reposition-pre",
            intendedScreen: screen,
            calc: Calc(width: width, height: height, padding: padding, x: x, y: y, topSafeY: topRefY)
        )
#endif

        // Use standard setFrame but force it.
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        
        // Ensure level is re-applied in case something reset it
        panel.level = .screenSaver

#if DEBUG
        debugDump(
            reason: "reposition-post",
            intendedScreen: screen,
            calc: Calc(width: width, height: height, padding: padding, x: x, y: y, topSafeY: topRefY)
        )
#endif
    }

    func setClickThrough(_ isClickThrough: Bool) {
        panel.ignoresMouseEvents = isClickThrough
#if DEBUG
        debugDump(
            reason: "setClickThrough isClickThrough=\(isClickThrough) ignoresMouseEvents=\(panel.ignoresMouseEvents)",
            intendedScreen: Self.mainDisplayScreen(),
            calc: nil
        )
#endif
    }

    func setPrivacyMode(_ enabled: Bool) {
        panel.sharingType = enabled ? .none : .readOnly
#if DEBUG
        debugDump(
            reason: "setPrivacyMode enabled=\(enabled) sharingType=\(panel.sharingType.rawValue)",
            intendedScreen: Self.mainDisplayScreen(),
            calc: nil
        )
#endif
    }

    private static func mainDisplayScreen() -> NSScreen? {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.first(where: { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(n.uint32Value) == mainID
        })
    }
}

#if DEBUG
private extension OverlayWindowController {
    struct Calc {
        let width: CGFloat
        let height: CGFloat
        let padding: CGFloat
        let x: CGFloat
        let y: CGFloat
        let topSafeY: CGFloat
    }

    func debugDump(reason: String, intendedScreen: NSScreen?, calc: Calc?) {
        let level = panel.level

        let intendedName = intendedScreen?.localizedName ?? "nil"
        let intendedFrame = intendedScreen?.frame.debugDescription ?? "nil"
        let intendedVisible = intendedScreen?.visibleFrame.debugDescription ?? "nil"
        let reservedTop: CGFloat = {
            guard let s = intendedScreen else { return .nan }
            return max(0, s.frame.maxY - s.visibleFrame.maxY)
        }()

        let panelFrame = panel.frame
        let panelMaxY = panelFrame.maxY

        let actualScreen = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: panelFrame.midX, y: panelFrame.midY))
        }
        let actualName = actualScreen?.localizedName ?? "nil"
        let actualFrame = actualScreen?.frame.debugDescription ?? "nil"
        let actualVisible = actualScreen?.visibleFrame.debugDescription ?? "nil"
        let actualVisibleMaxY = actualScreen?.visibleFrame.maxY ?? intendedScreen?.visibleFrame.maxY

        print("[Notchprompt][Overlay] reason=\(reason)")
        print("level=\(String(describing: level))(raw=\(level.rawValue)) ignoresMouseEvents=\(panel.ignoresMouseEvents)")
        print("panel.frame=\(panelFrame.debugDescription) panel.maxY=\(panelMaxY)")
        print("screen(name=\(intendedName), frame=\(intendedFrame), visible=\(intendedVisible), reservedTop=\(reservedTop))")
        if let calc {
            print("calc(width=\(calc.width), height=\(calc.height), padding=\(calc.padding), x=\(calc.x), y=\(calc.y), topSafeY=\(calc.topSafeY))")
        } else {
            print("calc(nil)")
        }
        print("actualScreen(name=\(actualName), frame=\(actualFrame), visible=\(actualVisible))")
        // Overlapping the reserved top region is expected when we intentionally cover the notch/menu bar area.
    }
}
#endif
