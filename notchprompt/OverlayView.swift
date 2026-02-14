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
    @State private var isHovering: Bool = false

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
                .fill(Color.notchBlack)

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
                hasStartedSession: model.hasStartedSession,
                resetToken: model.resetToken,
                jumpBackToken: model.jumpBackToken,
                jumpBackDistancePoints: model.jumpBackDistancePoints,
                fadeFraction: CGFloat(model.edgeFadeFraction),
                isHovering: isHovering
            )
            .padding(.horizontal, 18)
            .padding(.top, 36) // Clearance for notch (approx 32pt) + minimal padding
            .padding(.bottom, 8)
            .clipShape(Rectangle())

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
            isHovering = hovering
            model.isHovering = hovering
        }
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
