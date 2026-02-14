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
    let isHovering: Bool

    private static let loopGap: CGFloat = 24

    @State private var contentHeight: CGFloat = 1
    @State private var phase: CGFloat = 0
    @State private var lastTickDate: Date?
    @State private var targetSpeedMultiplier: Double = 1.0
    @State private var currentSpeedMultiplier: Double = 1.0

    // Smooth deceleration/acceleration rate (0-1, higher = faster)
    private let speedLerpFactor: Double = 8.0

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var effectiveOffsetY: CGFloat {
        guard hasContent else { return 0 }
        return -(phase.truncatingRemainder(dividingBy: cycleLength))
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
            TimelineView(.animation) { timeline in
                ZStack(alignment: .topLeading) {
                    if hasContent && hasStartedSession {
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
                    resetPhase()
                }
                .onChange(of: resetToken) { _ in
                    resetPhase()
                }
                .onChange(of: text) { _ in
                    resetPhase()
                }
                .onChange(of: jumpBackToken) { _ in
                    guard hasContent else { return }
                    phase = max(phase - max(0, jumpBackDistancePoints), 0)
                }
                .onChange(of: fontSize) { _ in
                    resetPhase()
                }
                .onChange(of: isRunning) { running in
                    targetSpeedMultiplier = running ? 1.0 : 0.0
                    lastTickDate = timeline.date
                }
                .onChange(of: isHovering) { hovering in
                    targetSpeedMultiplier = hovering ? 0.0 : 1.0
                }
                .onPreferenceChange(ContentHeightPreferenceKey.self) { measured in
                    contentHeight = max(measured, 1)
                }
                .onChange(of: timeline.date) { date in
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
                    colors: [Color.black.opacity(0.9), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bandHeight)
                .blur(radius: 2.8)

                Spacer(minLength: 0)

                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.9)],
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
        phase = 0
        lastTickDate = nil
        currentSpeedMultiplier = 1.0
        targetSpeedMultiplier = 1.0
    }

    private func tick(at date: Date) {
        guard hasContent else {
            lastTickDate = date
            return
        }

        let dt: CGFloat
        if let lastTickDate {
            dt = max(0, min(CGFloat(date.timeIntervalSince(lastTickDate)), 0.05))
        } else {
            dt = 1.0 / 60.0
        }

        self.lastTickDate = date

        // Smoothly interpolate current speed toward target speed
        let diff = targetSpeedMultiplier - currentSpeedMultiplier
        if abs(diff) > 0.001 {
            currentSpeedMultiplier += diff * min(1.0, speedLerpFactor * dt)
        } else {
            currentSpeedMultiplier = targetSpeedMultiplier
        }

        // Only update phase if actually running (speed > 0)
        phase += CGFloat(speedPointsPerSecond) * CGFloat(currentSpeedMultiplier) * dt

        if phase >= cycleLength * 8 {
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
