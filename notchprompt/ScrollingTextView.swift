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
    let hasStartedSession: Bool
    let resetToken: UUID
    let jumpBackToken: UUID
    let jumpBackDistancePoints: CGFloat
    let fadeFraction: CGFloat
    let backgroundOpacity: Double
    let isHovering: Bool
    let scrollMode: PrompterModel.ScrollMode
    let savedScrollPhaseForResume: CGFloat?
    let onSaveScrollPhaseForResume: ((CGFloat) -> Void)?
    let onReachedEnd: (() -> Void)?

    private static let loopGap: CGFloat = 24
    private static let activeTickInterval: TimeInterval = 1.0 / 60.0
    private static let idleTickInterval: TimeInterval = 1.0 / 8.0

    @State private var contentHeight: CGFloat = 1
    @State private var viewportHeight: CGFloat = 0
    @State private var phase: CGFloat = 0
    @State private var lastTickDate: Date?
    @State private var targetSpeedMultiplier: Double = 1.0
    @State private var currentSpeedMultiplier: Double = 1.0
    @State private var hasReachedEndInStopMode: Bool = false
    @State private var hasMeasuredContentHeight: Bool = false
    @State private var deferredStopTargetPhase: CGFloat? = nil

    // Smooth deceleration/acceleration rate (0-1, higher = faster)
    private let speedLerpFactor: Double = 8.0

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
        // Render enough copies to fully cover the viewport and keep the handoff
        // between loops continuous even when the viewport gets taller.
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
                    restoreOrResetPhase()
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
                .onChange(of: fontSize) { _, _ in
                    normalizeTopAnchorIfNearStart()
                }
                .onChange(of: scrollMode) { _, _ in
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
        (isRunning && !isHovering) ? 1.0 : 0.0
    }

    private func tick(at date: Date) {
        guard hasContent else {
            lastTickDate = date
            return
        }

        // Authoritative per-frame run state; don't rely on onChange timing.
        let shouldRun = (isRunning && !isHovering) && !(scrollMode == .stopAtEnd && hasReachedEndInStopMode)
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
            if scrollMode == .stopAtEnd, deferredStopTargetPhase == nil,
               hasMeasuredContentHeight, !hasReachedEndInStopMode {
                let vis = phase.truncatingRemainder(dividingBy: cycleLength)
                let cs = phase - vis
                deferredStopTargetPhase = vis <= endPhase
                    ? cs + endPhase
                    : cs + cycleLength + endPhase
            }

            if scrollMode == .stopAtEnd, hasMeasuredContentHeight,
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

        if scrollMode == .infinite, phase >= cycleLength * 8 {
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
