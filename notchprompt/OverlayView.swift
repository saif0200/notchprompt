//
//  OverlayView.swift
//  notchprompt
//
//  The Dynamic Island: idle, compact and expanded are one black shape changing
//  size around the camera. On OLED, pure black and the camera cutout are the same
//  colour, so the hardware disappears into it.
//

import AppKit
import SwiftUI

@MainActor
final class IslandPlacement: ObservableObject {
    @Published var layout: IslandLayout

    init(layout: IslandLayout) {
        self.layout = layout
    }
}

struct OverlayView: View {
    @ObservedObject var model: PrompterModel
    @ObservedObject var placement: IslandPlacement

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPointerInside = false
    @State private var showsControls = false
    @State private var hideControlsTask: Task<Void, Never>?

    private var layout: IslandLayout { placement.layout }
    private var form: IslandForm { model.islandForm }

    private var islandAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.44, dampingFraction: 0.82)
    }

    var body: some View {
        let size = layout.size(for: form)
        let corners = layout.corners(for: form)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: corners.top,
            bottomLeadingRadius: corners.bottom,
            bottomTrailingRadius: corners.bottom,
            topTrailingRadius: corners.top,
            style: .continuous
        )

        ZStack(alignment: .top) {
            shape.fill(islandFill)

            // A real Button: gestures miss clicks in a non-activating panel.
            Button {
                model.expandIsland()
            } label: {
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(form == .expanded)
            .accessibilityLabel("Open prompter")

            expandedContent
                .frame(width: layout.expandedSize.width, height: layout.expandedSize.height, alignment: .top)
                .opacity(form == .expanded ? 1 : 0)
                .allowsHitTesting(form == .expanded)

            compactContent
                .frame(width: layout.size(for: .compact).width, height: layout.compactHeight)
                .opacity(form == .compact ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .padding(.top, layout.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            IslandHoverTracker(
                onHoverChange: handleHover,
                onMove: handlePointerMove
            )
        )
        .animation(islandAnimation, value: form)
        .animation(islandAnimation, value: layout.expandedSize)
        .animation(.easeOut(duration: 0.18), value: showsControls)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.isRunning) { _, _ in scheduleControlsHide() }
    }

    /// Only the expanded form takes the theme. Compact stays true black so it
    /// keeps blending with the camera whatever the colours are set to.
    private var islandFill: Color {
        form == .expanded ? model.backgroundColor.opacity(model.backgroundOpacity) : .black
    }

    // MARK: - Compact

    private var compactContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: compactStatusSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                Text(compactLeadingText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: IslandLayout.compactLobeWidth, alignment: .center)

            Color.clear.frame(width: layout.cutoutWidth)

            HStack(spacing: 6) {
                ProgressRing(progress: model.progress)
                    .frame(width: 13, height: 13)
                Text(model.formattedTime(model.remainingSeconds))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(width: IslandLayout.compactLobeWidth, alignment: .center)
        }
        .foregroundStyle(.white.opacity(0.88))
    }

    private var compactStatusSymbol: String {
        if model.isRunning { return "play.fill" }
        if model.hasStartedSession { return "pause.fill" }
        return "text.alignleft"
    }

    private var compactLeadingText: String {
        model.hasStartedSession ? model.formattedTime(model.elapsedSeconds) : "Ready"
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        ZStack(alignment: .top) {
            if model.document.isEmpty {
                emptyScriptMessage
                    .padding(.top, layout.expandedHeaderHeight)
            } else {
                PrompterTextView(
                    configuration: textConfiguration,
                    scroller: model.scroller,
                    onScroll: { model.handleManualScroll(deltaPoints: $0) }
                )
                .frame(
                    width: layout.expandedSize.width,
                    height: layout.expandedSize.height - layout.expandedHeaderHeight
                )
                .padding(.top, layout.expandedHeaderHeight)
                .opacity(model.isCountingDown ? 0.14 : 1)
                .animation(.easeOut(duration: 0.2), value: model.isCountingDown)
            }

            if model.isCountingDown {
                countdownDigit
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, layout.expandedHeaderHeight / 2)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            header

            LinearGradient(
                colors: [model.backgroundColor.opacity(0), model.backgroundColor.opacity(model.backgroundOpacity)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .opacity(showsControls ? 1 : 0)
            .allowsHitTesting(false)

            controlsBar
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
                .opacity(showsControls ? 1 : 0)
                .offset(y: showsControls ? 0 : 8)
                .allowsHitTesting(showsControls)

            HStack {
                IslandResizeHandle(side: .left, model: model, layout: layout)
                    .frame(width: 30, height: 30)
                Spacer()
                IslandResizeHandle(side: .right, model: model, layout: layout)
                    .frame(width: 30, height: 30)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var textConfiguration: PrompterTextConfiguration {
        PrompterTextConfiguration(
            text: model.document.displayText,
            sectionRules: model.document.sectionRules,
            wordCount: model.wordCount,
            fontFamily: model.fontFamily,
            fontSize: CGFloat(model.fontSize),
            lineSpacing: CGFloat(model.lineSpacing),
            alignment: model.textAlignment,
            textColorHex: model.textColorHex,
            margin: CGFloat(model.horizontalMargin),
            wordsPerMinute: model.effectiveWordsPerMinute,
            mode: (model.scrollMode == .infinite && !model.voiceTrackingEnabled) ? .loop : .stopAtEnd,
            isMirrored: model.mirrorMode,
            readingPosition: CGFloat(model.cueLinePosition),
            cueEnabled: model.cueLineEnabled,
            cueColorHex: model.cueLineColorHex,
            cueOpacity: CGFloat(model.cueLineOpacity),
            focusEnabled: model.focusModeEnabled,
            focusLines: model.focusVisibleLines,
            focusDim: CGFloat(model.focusDimOpacity),
            highlightColorHex: model.highlightColorHex
        )
    }

    /// Sits in the camera's row, one group each side of it, centred on the lens.
    private var header: some View {
        HStack(spacing: 0) {
            headerLeading
                .frame(width: layout.expandedHeaderSlotWidth(), alignment: .leading)
            Color.clear.frame(width: layout.cutoutWidth + 28)
            headerTrailing
                .frame(width: layout.expandedHeaderSlotWidth(), alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .frame(height: layout.compactHeight)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.55))
        .lineLimit(1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var headerLeading: some View {
        if model.showTimeDisplay, !model.document.isEmpty {
            HStack(spacing: 8) {
                Text(model.formattedTime(model.elapsedSeconds))
                    .foregroundStyle(.white.opacity(0.82))
                Text("−\(model.formattedTime(model.remainingSeconds))")
            }
        }
    }

    private var headerTrailing: some View {
        HStack(spacing: 8) {
            if model.voiceScrollEnabled || model.voiceTrackingEnabled {
                microphoneIndicator
            }
            if model.didReachEnd {
                Text("End of script")
            } else if !model.document.isEmpty {
                Text("\(Int(model.effectiveWordsPerMinute)) wpm")
            }
        }
    }

    private var microphoneIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: model.voiceFailureMessage == nil ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 10, weight: .bold))
            if model.voiceTrackingEnabled, model.voiceTrackingStatus == .listening {
                Circle()
                    .fill(confidenceColor)
                    .frame(width: 6, height: 6)
            }
        }
        .foregroundStyle(model.voiceFailureMessage == nil ? .white.opacity(0.7) : .orange)
        .help(model.voiceFailureMessage ?? "Listening")
    }

    private var confidenceColor: Color {
        switch model.trackingConfidence {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        case .lost: return .red
        }
    }

    private var countdownDigit: some View {
        Text("\(model.countdownRemaining)")
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(model.textColor)
            .contentTransition(.numericText(countsDown: true))
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: model.countdownRemaining)
    }

    private var emptyScriptMessage: some View {
        VStack(spacing: 12) {
            Text("No script yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(model.textColor.opacity(0.85))
            Button("Open Script Editor") {
                sendAppAction(#selector(AppDelegate.openScriptEditorFromOverlay))
            }
            .buttonStyle(IslandCapsuleButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controlsBar: some View {
        ViewThatFits(in: .horizontal) {
            controlsRow(showsSecondary: true)
            controlsRow(showsSecondary: false)
        }
        .padding(.horizontal, 16)
    }

    private func controlsRow(showsSecondary: Bool) -> some View {
        HStack(spacing: 4) {
            if showsSecondary {
                IslandButton(symbol: "backward.end.fill", label: "Back to top") { model.resetScroll() }
            }
            IslandButton(symbol: "gobackward.5", label: "Jump back 5 seconds") { model.jumpBack(seconds: 5) }

            IslandButton(
                symbol: playSymbol,
                label: playLabel,
                size: 36,
                iconSize: 14,
                isProminent: true
            ) { model.toggleRunning() }

            IslandButton(symbol: "minus", label: "Slower", repeatsWhileHeld: true) {
                model.adjustSpeed(delta: -PrompterModel.speedStep)
            }
            Text("\(Int(model.effectiveWordsPerMinute))")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .frame(minWidth: 26)
                .help("Words per minute")
            IslandButton(symbol: "plus", label: "Faster", repeatsWhileHeld: true) {
                model.adjustSpeed(delta: PrompterModel.speedStep)
            }

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 3)

            IslandButton(symbol: "textformat.size.smaller", label: "Smaller text", repeatsWhileHeld: true) {
                model.adjustFontSize(delta: -1)
            }
            IslandButton(symbol: "textformat.size.larger", label: "Larger text", repeatsWhileHeld: true) {
                model.adjustFontSize(delta: 1)
            }

            IslandButton(symbol: "square.and.pencil", label: "Script Editor") {
                sendAppAction(#selector(AppDelegate.openScriptEditorFromOverlay))
            }
            if showsSecondary {
                IslandButton(symbol: "doc.on.clipboard", label: "Paste script from clipboard") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        model.pasteScript(text)
                    }
                }
                IslandButton(symbol: "trash", label: "Clear script") { model.clearScript() }
                IslandButton(symbol: "gearshape.fill", label: "Settings") {
                    sendAppAction(#selector(AppDelegate.openSettingsFromOverlay))
                }
            }
            IslandButton(symbol: "chevron.up", label: "Collapse") { model.collapseIsland() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color(white: 0.13), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .fixedSize()
    }

    private var playSymbol: String {
        if model.isRunning || model.isCountingDown { return "pause.fill" }
        return model.didReachEnd ? "arrow.counterclockwise" : "play.fill"
    }

    private var playLabel: String {
        if model.isRunning || model.isCountingDown { return "Pause" }
        return model.didReachEnd ? "Start again" : "Start"
    }

    private func sendAppAction(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    // MARK: - Pointer

    private func handleHover(_ isInside: Bool) {
        isPointerInside = isInside
        model.setPointerOverIsland(isInside)
        if isInside {
            revealControls()
        } else {
            hideControlsTask?.cancel()
            showsControls = false
        }
    }

    private func handlePointerMove() {
        guard isPointerInside else { return }
        revealControls()
    }

    private func revealControls() {
        if !showsControls { showsControls = true }
        scheduleControlsHide()
    }

    /// While reading, the controls get out of the way once the pointer rests.
    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        guard model.isRunning, isPointerInside else { return }
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, model.isRunning else { return }
            showsControls = false
        }
    }
}

// MARK: - Pieces

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.22), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A real SwiftUI Button rather than a press gesture: gestures miss clicks in a
/// non-activating panel (FB13720950).
private struct IslandButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 28
    var iconSize: CGFloat = 11
    var isProminent = false
    var repeatsWhileHeld = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            if !repeatsWhileHeld { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(isProminent ? Color.black : Color.white.opacity(isHovering ? 1 : 0.82))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(
            IslandButtonStyle(
                isProminent: isProminent,
                isHovering: isHovering,
                repeatAction: repeatsWhileHeld ? action : nil
            )
        )
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAction { action() }
    }
}

private struct IslandButtonStyle: ButtonStyle {
    let isProminent: Bool
    let isHovering: Bool
    let repeatAction: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(fill(isPressed: configuration.isPressed), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .background {
                if let repeatAction {
                    RepeatWhileHeld(isPressed: configuration.isPressed, action: repeatAction)
                }
            }
    }

    private func fill(isPressed: Bool) -> Color {
        if isProminent { return Color.white.opacity(isPressed ? 0.75 : 1) }
        if isPressed { return Color.white.opacity(0.22) }
        return isHovering ? Color.white.opacity(0.12) : Color.clear
    }
}

/// Fires on press-down, then keeps firing until released.
private struct RepeatWhileHeld: View {
    let isPressed: Bool
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: isPressed) { _, pressed in
                repeatTask?.cancel()
                repeatTask = nil
                guard pressed else { return }
                action()
                repeatTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    while !Task.isCancelled {
                        action()
                        try? await Task.sleep(for: .milliseconds(90))
                    }
                }
            }
            .onDisappear {
                repeatTask?.cancel()
                repeatTask = nil
            }
    }
}

private struct IslandCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

/// SwiftUI's `onHover` doesn't reliably fire in a window that isn't key, and this
/// one never is. An always-active tracking area does.
private struct IslandHoverTracker: NSViewRepresentable {
    let onHoverChange: (Bool) -> Void
    let onMove: () -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onHoverChange = onHoverChange
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackerView, context: Context) {
        view.onHoverChange = onHoverChange
        view.onMove = onMove
    }

    final class TrackerView: NSView {
        var onHoverChange: ((Bool) -> Void)?
        var onMove: (() -> Void)?
        private var area: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let newArea = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: self
            )
            addTrackingArea(newArea)
            area = newArea
        }

        override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
        override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
        override func mouseMoved(with event: NSEvent) { onMove?() }
    }
}

/// Bottom-corner grips. Both sides move, so the island stays centred on the camera.
private struct IslandResizeHandle: NSViewRepresentable {
    enum Side {
        case left, right
    }

    let side: Side
    let model: PrompterModel
    let layout: IslandLayout

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.side = side
        view.model = model
        view.layout = layout
        return view
    }

    func updateNSView(_ view: HandleView, context: Context) {
        view.side = side
        view.layout = layout
    }

    final class HandleView: NSView {
        var side: Side = .right
        weak var model: PrompterModel?
        var layout: IslandLayout?

        private var startMouse: NSPoint = .zero
        private var startSize: CGSize = .zero
        private var area: NSTrackingArea?

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        private var cursor: NSCursor {
            if #available(macOS 15.0, *) {
                return NSCursor.frameResize(position: side == .right ? .bottomRight : .bottomLeft, directions: .all)
            }
            return .crosshair
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let newArea = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .cursorUpdate, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
            addTrackingArea(newArea)
            area = newArea
        }

        override func cursorUpdate(with event: NSEvent) { cursor.set() }
        override func mouseEntered(with event: NSEvent) { cursor.set() }
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

        override func mouseDown(with event: NSEvent) {
            startMouse = NSEvent.mouseLocation
            startSize = layout?.expandedSize ?? .zero
        }

        override func mouseDragged(with event: NSEvent) {
            guard let model else { return }
            let mouse = NSEvent.mouseLocation
            let dx = (mouse.x - startMouse.x) * (side == .right ? 1 : -1)
            let dy = startMouse.y - mouse.y
            model.setOverlaySize(
                width: Double(startSize.width + 2 * dx),
                height: Double(startSize.height + dy)
            )
        }
    }
}
