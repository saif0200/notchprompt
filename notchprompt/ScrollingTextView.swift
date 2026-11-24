//
//  ScrollingTextView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import SwiftUI

struct ScrollingTextView: View {
    let text: String
    let fontSize: CGFloat
    let speedPointsPerSecond: Double
    let isRunning: Bool
    let voiceGateOpen: Bool
    let hasStartedSession: Bool
    let resetToken: UUID
    let jumpBackToken: UUID
    let jumpBackDistancePoints: CGFloat
    let manualScrollToken: UUID
    let manualScrollDeltaPoints: CGFloat
    let fadeFraction: CGFloat
    let backgroundOpacity: Double
    let isHovering: Bool
    let scrollMode: PrompterModel.ScrollMode
    /// Non-nil while following the user's speech: the script glides to this fraction instead of scrolling at a fixed speed.
    let followProgress: Double?
    let savedScrollPhaseForResume: CGFloat?
    let onSaveScrollPhaseForResume: ((CGFloat) -> Void)?
    let onReachedEnd: (() -> Void)?

    private static let loopGap: CGFloat = 24
    private static let activeTickInterval: TimeInterval = 1.0 / 60.0
    private static let idleTickInterval: TimeInterval = 1.0 / 8.0

    @State private var contentHeight: CGFloat = 1
    @State private var viewportHeight: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var wordLayout = WordLayout()
    @State private var phase: CGFloat = 0
    @State private var lastTickDate: Date?
    @State private var targetSpeedMultiplier: Double = 1.0
    @State private var currentSpeedMultiplier: Double = 1.0
    @State private var hasReachedEndInStopMode: Bool = false
    @State private var hasMeasuredContentHeight: Bool = false
    @State private var deferredStopTargetPhase: CGFloat? = nil

    // Smooth deceleration/acceleration rate (0-1, higher = faster)
    private let speedLerpFactor: Double = 8.0

    // Following maps progress onto one copy of the script, so it renders like stop-at-end.
    private var mode: PrompterModel.ScrollMode {
        followProgress == nil ? scrollMode : .stopAtEnd
    }

    let followGlideSpeed: CGFloat
    let followJumpBoost: CGFloat
    let followReadingLine: CGFloat

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var isActivelyAnimating: Bool {
        (isRunning && !isHovering && hasContent) || currentSpeedMultiplier > 0.002
    }
    
    private var tickInterval: TimeInterval {
        isActivelyAnimating ? Self.activeTickInterval : Self.idleTickInterval
    }

    private var emptyStateMessage: String {
        "No script yet.\nOpen Settings and paste your script to begin."
    }

    private var initialStateMessage: String {
        "Ready to prompt.\nPress Start to begin countdown."
    }

    private var clampedFadeFraction: CGFloat {
        min(max(fadeFraction, 0), 0.49)
    }

    private var cycleLength: CGFloat {
        max(contentHeight + Self.loopGap, 1)
    }

    private var topFadeClearInset: CGFloat {
        guard viewportHeight > 1 else { return 0 }
        return viewportHeight * clampedFadeFraction
    }

    private var readabilityPadding: CGFloat {
        max(2, fontSize * 0.12)
    }

    private var startAnchorOffset: CGFloat {
        let fallback = max(8, min(fontSize * 0.45, 22))
        guard viewportHeight > 1 else { return fallback }

        let raw = topFadeClearInset + readabilityPadding
        let capped = min(raw, max(18, viewportHeight * 0.38))
        return max(capped, fallback)
    }

    private var topOfScriptPhaseFloor: CGFloat {
        -startAnchorOffset
    }

    private var topNormalizationThreshold: CGFloat {
        max(12, fontSize * 1.6)
    }

    private var effectiveOffsetY: CGFloat {
        guard hasContent else { return 0 }
        // Always use truncating remainder so we can keep the multi-copy VStack
        // rendering in every mode. This avoids structural view changes on mode switch.
        return -(phase.truncatingRemainder(dividingBy: cycleLength))
    }

    private var endPhase: CGFloat {
        let bottomReadabilityInset = topFadeClearInset + readabilityPadding
        let lastLinePhase = contentHeight - max(0, viewportHeight - bottomReadabilityInset)
        return max(topOfScriptPhaseFloor, lastLinePhase)
    }

    private func repetitionCount(for viewportHeight: CGFloat) -> Int {
        if mode == .stopAtEnd { return 1 }
        let minimumCopies = 3
        let needed = Int(ceil(viewportHeight / cycleLength)) + 2
        return max(minimumCopies, needed)
    }

    var body: some View {
        GeometryReader { viewportProxy in
            TimelineView(.periodic(from: .now, by: tickInterval)) { timeline in
                ZStack(alignment: .topLeading) {
                    if hasContent && hasStartedSession {
                        // Always render repeated copies so toggling between infinite
                        // and stop-at-end never causes a structural view rebuild.
                        let copies = repetitionCount(for: viewportProxy.size.height)
                        VStack(spacing: Self.loopGap) {
                            ForEach(0..<copies, id: \.self) { index in
                                repeatedScrollingContent(at: index)
                            }
                        }
                        .offset(y: effectiveOffsetY)
                    } else if hasContent {
                        Text(initialStateMessage)
                            .font(.system(size: max(fontSize * 0.72, 13), weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.horizontal, 12)
                    } else {
                        Text(emptyStateMessage)
                            .font(.system(size: max(fontSize * 0.72, 13), weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.horizontal, 12)
                    }
                }
                .frame(width: viewportProxy.size.width, height: viewportProxy.size.height, alignment: .topLeading)
                .onAppear {
                    viewportHeight = max(viewportProxy.size.height, 0)
                    viewportWidth = viewportProxy.size.width
                    restoreOrResetPhase()
                }
                .onChange(of: viewportProxy.size.width) { _, newWidth in
                    viewportWidth = newWidth
                }
                .onChange(of: viewportProxy.size.height) { _, newHeight in
                    viewportHeight = max(newHeight, 0)
                    normalizeTopAnchorIfNearStart()
                }
                .onChange(of: resetToken) { _, _ in
                    deferredStopTargetPhase = nil
                    resetPhase()
                }
                .onChange(of: text) { _, _ in
                    hasMeasuredContentHeight = false
                    deferredStopTargetPhase = nil
                    resetPhase()
                }
                .onChange(of: jumpBackToken) { _, _ in
                    guard hasContent else { return }
                    hasReachedEndInStopMode = false
                    deferredStopTargetPhase = nil
                    phase = max(phase - max(0, jumpBackDistancePoints), topOfScriptPhaseFloor)
                }
                .onChange(of: manualScrollToken) { _, _ in
                    guard hasContent else { return }
                    applyManualScrollDelta(manualScrollDeltaPoints)
                }
                .onChange(of: fontSize) { _, _ in
                    normalizeTopAnchorIfNearStart()
                }
                .onChange(of: mode) { _, _ in
                    hasReachedEndInStopMode = false
                    // Clear any stale target; tick() will lazily recompute on the
                    // very first frame it runs in the new mode, avoiding the race
                    // where tick fires before this handler.
                    deferredStopTargetPhase = nil
                }
                .onChange(of: isRunning) { _, isNowRunning in
                    if !isNowRunning {
                        onSaveScrollPhaseForResume?(phase)
                    }
                    lastTickDate = timeline.date
                }
                .onChange(of: isHovering) { _, _ in
                    lastTickDate = timeline.date
                }
                .onPreferenceChange(ContentHeightPreferenceKey.self) { measured in
                    contentHeight = max(measured, 1)
                    hasMeasuredContentHeight = measured > 1
                }
                .onChange(of: timeline.date) { _, date in
                    tick(at: date)
                }
            }
        }
        .mask(edgeFadeMask)
        .overlay(edgeSofteningOverlay)
    }

    @ViewBuilder
    private func repeatedScrollingContent(at index: Int) -> some View {
        if index == 0 {
            scrollingContent
                .measureHeight()
        } else {
            scrollingContent
        }
    }

    private var scrollingContent: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var edgeFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.25), location: clampedFadeFraction * 0.28),
                .init(color: .black.opacity(0.75), location: clampedFadeFraction * 0.68),
                .init(color: .black, location: clampedFadeFraction),
                .init(color: .black, location: 1 - clampedFadeFraction),
                .init(color: .black.opacity(0.75), location: 1 - (clampedFadeFraction * 0.68)),
                .init(color: .black.opacity(0.25), location: 1 - (clampedFadeFraction * 0.28)),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var edgeSofteningOverlay: some View {
        GeometryReader { proxy in
            let bandHeight = max(proxy.size.height * clampedFadeFraction * 0.9, 8)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(backgroundOpacity * 0.9), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bandHeight)
                .blur(radius: 2.8)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(backgroundOpacity * 0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bandHeight)
                .blur(radius: 2.8)
            }
        }
        .allowsHitTesting(false)
    }

    private func resetPhase() {
        phase = topOfScriptPhaseFloor
        hasReachedEndInStopMode = false
        deferredStopTargetPhase = nil
        lastTickDate = nil
        let desired = desiredSpeedMultiplier()
        currentSpeedMultiplier = desired
        targetSpeedMultiplier = desired
    }

    private func restoreOrResetPhase() {
        guard hasStartedSession, let saved = savedScrollPhaseForResume else {
            resetPhase()
            return
        }
        phase = max(saved, topOfScriptPhaseFloor)
        hasReachedEndInStopMode = false
        deferredStopTargetPhase = nil
        lastTickDate = nil
        let desired = desiredSpeedMultiplier()
        currentSpeedMultiplier = desired
        targetSpeedMultiplier = desired
    }

    private func normalizeTopAnchorIfNearStart() {
        guard hasContent else { return }
        guard phase <= topNormalizationThreshold else { return }
        phase = topOfScriptPhaseFloor
    }

    private func desiredSpeedMultiplier() -> Double {
        (isRunning && !isHovering && voiceGateOpen) ? 1.0 : 0.0
    }

    private func applyManualScrollDelta(_ delta: CGFloat) {
        hasReachedEndInStopMode = false
        deferredStopTargetPhase = nil
        phase += delta

        if mode == .stopAtEnd, hasMeasuredContentHeight {
            phase = min(max(phase, topOfScriptPhaseFloor), endPhase)
            return
        }

        if phase >= cycleLength * 8 || phase <= -(cycleLength * 8) {
            phase = phase.truncatingRemainder(dividingBy: cycleLength)
        }
        phase = max(phase, topOfScriptPhaseFloor)
    }

    private func followWords(progress: Double, at date: Date) {
        let dt = lastTickDate.map { max(0, min(CGFloat(date.timeIntervalSince($0)), 0.25)) } ?? CGFloat(Self.activeTickInterval)
        lastTickDate = date
        targetSpeedMultiplier = 0
        currentSpeedMultiplier = 0
        if Int(date.timeIntervalSince1970 * 2) != Int((date.timeIntervalSince1970 - Double(dt)) * 2) {
            followLog.info("view progress=\(progress) running=\(isRunning) hover=\(isHovering) measured=\(hasMeasuredContentHeight) phase=\(Double(phase)) h=\(Double(contentHeight))")
        }
        // Not hasMeasuredContentHeight: editing the script clears it after the new height has already arrived, freezing follow mode.
        guard isRunning, !isHovering, contentHeight > 1 else { return }
        // Paragraph breaks and short lines make offset/length a poor proxy for y, so lay the script out the way the view does.
        let wordY = wordLayout.y(ofOffset: Int((progress * Double(text.count)).rounded()), in: text, fontSize: fontSize, width: viewportWidth, renderedHeight: contentHeight)
        let centreAnchor = max(0, (viewportHeight - fontSize * 1.2) / 2 - startAnchorOffset)
        let anchor = startAnchorOffset + followReadingLine * centreAnchor
        let target = min(max(wordY - anchor, topOfScriptPhaseFloor), endPhase)
        // Line-to-line moves glide; bigger jumps (paragraph breaks) move faster so they don't lag behind the reader.
        let rate = abs(target - phase) > fontSize * 1.5 ? followGlideSpeed * followJumpBoost : followGlideSpeed
        phase += (target - phase) * min(1, rate * dt)
    }

    private func tick(at date: Date) {
        guard hasContent else {
            lastTickDate = date
            return
        }

        if let followProgress {
            followWords(progress: followProgress, at: date)
            return
        }

        // Authoritative per-frame run state; don't rely on onChange timing.
        let shouldRun = (isRunning && !isHovering && voiceGateOpen) && !(mode == .stopAtEnd && hasReachedEndInStopMode)
        targetSpeedMultiplier = shouldRun ? 1.0 : 0.0

        let totalDt: CGFloat
        if let lastTickDate {
            totalDt = max(0, min(CGFloat(date.timeIntervalSince(lastTickDate)), 0.25))
        } else {
            totalDt = CGFloat(Self.activeTickInterval)
        }

        self.lastTickDate = date

        // Integrate in short fixed steps to avoid jitter/jumps at very slow/fast speeds.
        var remaining = totalDt
        let maxStep: CGFloat = CGFloat(Self.activeTickInterval)

        while remaining > 0 {
            let step = min(remaining, maxStep)

            let diff = targetSpeedMultiplier - currentSpeedMultiplier
            if abs(diff) > 0.001 {
                currentSpeedMultiplier += diff * min(1.0, speedLerpFactor * step)
            } else {
                currentSpeedMultiplier = targetSpeedMultiplier
            }

            phase += CGFloat(speedPointsPerSecond) * CGFloat(currentSpeedMultiplier) * step

            // Lazily compute the stop target on the first tick after entering
            // stopAtEnd mode. This runs in the same code path that checks the
            // threshold, so there is no race with onChange timing.
            if mode == .stopAtEnd, deferredStopTargetPhase == nil,
               hasMeasuredContentHeight, !hasReachedEndInStopMode {
                let vis = phase.truncatingRemainder(dividingBy: cycleLength)
                let cs = phase - vis
                deferredStopTargetPhase = vis <= endPhase
                    ? cs + endPhase
                    : cs + cycleLength + endPhase
            }

            if mode == .stopAtEnd, hasMeasuredContentHeight,
               let target = deferredStopTargetPhase, phase >= target {
                phase = target
                targetSpeedMultiplier = 0
                currentSpeedMultiplier = 0
                deferredStopTargetPhase = nil
                remaining = 0

                if !hasReachedEndInStopMode {
                    hasReachedEndInStopMode = true
                    onReachedEnd?()
                }
                break
            }

            remaining -= step
        }

        if !isRunning, currentSpeedMultiplier < 0.002 {
            currentSpeedMultiplier = 0
        }

        if mode == .infinite, phase >= cycleLength * 8 {
            phase = phase.truncatingRemainder(dividingBy: cycleLength)
        }
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func measureHeight() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: ContentHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }
}

/// Top y of the line holding a script character, from an AppKit layout that mirrors the on-screen Text.
final class WordLayout {
    private var key: (text: String, fontSize: CGFloat, width: CGFloat)?
    private var manager = NSLayoutManager()
    // NSLayoutManager holds its text storage weakly; without this the layout is empty and every word maps to y = 0.
    private var storage = NSTextStorage()
    private var totalHeight: CGFloat = 1

    func y(ofOffset offset: Int, in text: String, fontSize: CGFloat, width: CGFloat, renderedHeight: CGFloat) -> CGFloat {
        if key?.text != text || key?.fontSize != fontSize || key?.width != width {
            storage = NSTextStorage(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)])
            let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            manager = NSLayoutManager()
            manager.addTextContainer(container)
            storage.addLayoutManager(manager)
            manager.ensureLayout(for: container)  // usedRect is 0 until layout has run
            totalHeight = max(manager.usedRect(for: container).height, 1)
            key = (text, fontSize, width)
        }
        let index = text.index(text.startIndex, offsetBy: min(offset, text.count))
        let utf16 = min(text.utf16.distance(from: text.utf16.startIndex, to: index), max(0, manager.numberOfGlyphs - 1))
        guard manager.numberOfGlyphs > 0 else { return 0 }
        let glyph = manager.glyphIndexForCharacter(at: utf16)
        let lineY = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        // SwiftUI's line height can differ slightly from AppKit's; rescale to the height actually rendered.
        return lineY * renderedHeight / totalHeight
    }
}
