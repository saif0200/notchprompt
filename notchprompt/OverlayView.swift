//
//  OverlayView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import SwiftUI

private extension Color {
    /// `#000000` (darkest black for seamless notch blending)
    static let notchBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1.0)
}

/// MacBook-style notch contour:
/// - flat top edge with square top corners
/// - straight side walls
/// - rounded lower corners
private struct AppleNotchShape: InsettableShape {
    /// Lower corner radius relative to height.
    var bottomCornerRadiusRatio: CGFloat = 0.18
    /// Portion of total height used by the straight side wall.
    var sideWallDepthRatio: CGFloat = 0.82
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }

        let w = r.width
        let h = r.height

        // sideWallDepthRatio controls how much vertical wall exists before lower arcs.
        let depthRatio = max(0.60, min(sideWallDepthRatio, 0.95))
        let lowerArcStartY = r.minY + (h * depthRatio)
        let maxBottomRadiusFromDepth = max(0, r.maxY - lowerArcStartY)
        let maxBottomRadiusFromWidth = w * 0.5
        let targetBottomRadius = h * bottomCornerRadiusRatio
        let bottomRadius = max(
            0,
            min(targetBottomRadius, min(maxBottomRadiusFromDepth, maxBottomRadiusFromWidth))
        )

        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))

        // Right side wall into large lower corner.
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottomRadius))
        if bottomRadius > 0 {
            p.addArc(
                center: CGPoint(x: r.maxX - bottomRadius, y: r.maxY - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }

        p.addLine(to: CGPoint(x: r.minX + bottomRadius, y: r.maxY))
        if bottomRadius > 0 {
            p.addArc(
                center: CGPoint(x: r.minX + bottomRadius, y: r.maxY - bottomRadius),
                radius: bottomRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        } else {
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }

        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()

        return p
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var s = self
        s.insetAmount += amount
        return s
    }
}

struct OverlayView: View {
    @ObservedObject var model: PrompterModel
    @State private var showControls = false
    private var controlsShown: Bool { showControls || !model.autoHideControls }

    var body: some View {
        // Ratio-driven contour tuned to Apple notch geometry and scaled to the
        // current overlay dimensions.
        let shape = AppleNotchShape()
        let hideTopStrokeHeight: CGFloat = 2

        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(shape)
                // Blur can brighten the surface; keep it effectively off for notch matching.
                .opacity(0.0)

            shape
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: model.backgroundOpacity))

            shape
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                // Hard-cut the stroke off at the very top so the edge blends into the notch.
                .mask(
                    VStack(spacing: 0) {
                        Color.clear.frame(height: hideTopStrokeHeight)
                        Color.white
                    }
                )

            // The scroller is hard-clipped (so text truly "cuts off") and we add
            // subtle blur bands at the top/bottom to soften the exit.
            ScrollingTextView(
                text: model.script,
                fontSize: CGFloat(model.fontSize),
                speedPointsPerSecond: model.speedPointsPerSecond,
                isRunning: model.isRunning,
                voiceGateOpen: model.isVoiceGateOpen,
                hasStartedSession: model.hasStartedSession,
                resetToken: model.resetToken,
                jumpBackToken: model.jumpBackToken,
                jumpBackDistancePoints: model.jumpBackDistancePoints,
                manualScrollToken: model.manualScrollToken,
                manualScrollDeltaPoints: model.manualScrollDeltaPoints,
                fadeFraction: CGFloat(model.edgeFadeFraction),
                backgroundOpacity: model.backgroundOpacity,
                isHovering: showControls && model.pauseOnHover,
                scrollMode: model.scrollMode,
                followProgress: model.isFollowingWords ? model.followProgress : nil,
                savedScrollPhaseForResume: model.savedScrollPhaseForResume,
                onSaveScrollPhaseForResume: { phase in
                    model.saveScrollPhaseForResume(phase)
                },
                onReachedEnd: {
                    if model.isRunning {
                        model.markReachedEndInStopMode()
                    }
                },
                followGlideSpeed: CGFloat(model.followGlideSpeed),
                followJumpBoost: CGFloat(model.followJumpBoost),
                followReadingLine: CGFloat(model.followReadingLine)
            )
            // Clear of the side button columns; the top only needs to clear the camera notch.
            // Wider now the controls hide, but still well short of the edges so reading looks like eye contact.
            // Always-visible side buttons reach ~52pt in from the edge.
            .padding(.horizontal, model.autoHideControls ? model.textSideMargin : max(model.textSideMargin, 52))
            .padding(.top, model.textTopOffset)
            .padding(.bottom, 12)
            .clipShape(Rectangle())
            .overlay {
                TrackpadScrollCaptureView { delta in
                    model.handleManualScroll(deltaPoints: delta)
                }
            }
            
            if model.glowEnabled && model.voiceMode != .off && model.isRunning && (model.voiceIsSpeaking || model.glowRestingLine) {
                // Light rising from the floor: half of a feathered ellipse sits below the bottom edge and is clipped,
                // so it fades up from a flat base. It swells with loudness like Voice Memos; silent, it is a thin line.
                let level = model.voiceIsSpeaking ? max(model.voiceLevel, 0.15) : 0
                let glowHeight = (8 + 26 * level) * model.glowIntensity
                Ellipse()
                    .fill(model.glowColor)
                    .frame(width: model.overlayWidth * (0.30 + 0.12 * level) * model.glowWidth, height: level > 0 ? glowHeight : 4)
                    .blur(radius: level > 0 ? 7 + 5 * level : 0.5)
                    .opacity(min(1, (level > 0 ? 0.45 + 0.55 * level : 0.85) * model.glowIntensity))
                    .offset(y: level > 0 ? glowHeight / 2 : 2)
                    .animation(.easeOut(duration: 0.12), value: level)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .clipped()
                    .allowsHitTesting(false)
            }

            if !model.isCountingDown {
                // Controls run down both sides so the notch keeps the top clear and the text sits in the middle.
                HStack(alignment: .center) {
                    VStack(spacing: 4) {
                        OverlayControlButton(
                            symbol: (model.isRunning || model.isCountingDown) ? "hand.draw.fill" : "play.fill"
                        ) {
                            model.switchPlaybackModeFromOverlayControl()
                        }
                        .help((model.isRunning || model.isCountingDown) ? "Pause and switch to manual trackpad scroll" : "Start auto scroll")

                        OverlayControlButton(symbol: model.isFollowingWords ? "arrow.counterclockwise" : "gobackward.5") {
                            model.jumpBack(seconds: 5)
                        }
                        .help(model.isFollowingWords ? "Restart from the top" : "Jump back 5 seconds")

                        OverlayControlButton(symbol: "gearshape") {
                            NotificationCenter.default.post(name: .openNotchpromptSettings, object: nil)
                        }
                        .help("Settings")
                    }
                    .modifier(OverlayControlColumn())
                    .offset(x: controlsShown ? 0 : -64)
                    .opacity(controlsShown ? 1 : 0)

                    Spacer(minLength: 8)

                    VStack(spacing: 3) {
                        OverlayControlButton(symbol: "doc.on.clipboard") {
                            if let text = NSPasteboard.general.string(forType: .string) {
                                model.pasteScript(text)
                            }
                        }
                        .help("Paste script from clipboard")

                        OverlayControlButton(symbol: "trash") {
                            model.script = ""
                        }
                        .help("Clear script")

                        OverlayControlButton(symbol: "minus", repeatWhilePressed: true) {
                            model.adjustSpeed(delta: -PrompterModel.speedStep)
                        }
                        .help("Decrease speed")

                        OverlayControlButton(symbol: "plus", repeatWhilePressed: true) {
                            model.adjustSpeed(delta: PrompterModel.speedStep)
                        }
                        .help("Increase speed")

                        OverlayControlButton(symbol: "xmark") {
                            NSApp.terminate(nil)
                        }
                        .help("Quit Notchprompt")
                    }
                    .modifier(OverlayControlColumn())
                    .offset(x: controlsShown ? 0 : 64)
                    .opacity(controlsShown ? 1 : 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if model.isCountingDown {
                ZStack {
                    Color.black.opacity(0.92)
                    Text("\(model.countdownRemaining)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
        }
        .frame(width: model.overlayWidth, height: model.overlayHeight)
        .onHover { hovering in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showControls = hovering }
        }
    }
}

private struct OverlayControlButton: View {
    let symbol: String
    var isActive: Bool = false
    var repeatWhilePressed: Bool = false
    let action: () -> Void

    var body: some View {
        // Use SwiftUI Button (not onLongPressGesture) so we benefit from
        // the macOS 15 click-through fix for non-activating panels (FB13720950).
        Button {
            if !repeatWhilePressed { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(
            OverlayCircleButtonStyle(
                isActive: isActive,
                repeatWhilePressed: repeatWhilePressed,
                repeatAction: action
            )
        )
    }
}

/// Button style that provides press-highlight and optional repeat-while-held.
private struct OverlayCircleButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var repeatWhilePressed: Bool = false
    var repeatAction: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed || isActive ? 0.18 : 0.10))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .background {
                if repeatWhilePressed {
                    RepeatWhileHeldHelper(
                        isPressed: configuration.isPressed,
                        action: repeatAction ?? {}
                    )
                }
            }
    }
}

/// Zero-size helper that fires an action on press-down and repeats while held.
private struct RepeatWhileHeldHelper: View {
    let isPressed: Bool
    let action: () -> Void

    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: isPressed) { _, pressed in
                if pressed {
                    action()
                    startRepeating()
                } else {
                    stopRepeating()
                }
            }
            .onDisappear { stopRepeating() }
    }

    private func startRepeating() {
        stopRepeating()
        repeatTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            while !Task.isCancelled {
                await MainActor.run { action() }
                try? await Task.sleep(nanoseconds: 85_000_000)
            }
        }
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct TrackpadScrollCaptureView: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> ScrollCaptureNSView {
        let view = ScrollCaptureNSView()
        view.onScroll = context.coordinator.handleScroll
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureNSView, context: Context) {
        nsView.onScroll = context.coordinator.handleScroll
    }

    final class Coordinator {
        let onScroll: (CGFloat) -> Void

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
        }

        func handleScroll(_ event: NSEvent) {
            let rawDelta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 10
            let semanticDelta = event.isDirectionInvertedFromDevice ? rawDelta : -rawDelta
            onScroll(semanticDelta)
        }
    }
}

final class ScrollCaptureNSView: NSView {
    var onScroll: ((NSEvent) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }
}

private struct OverlayControlColumn: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.7), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}
