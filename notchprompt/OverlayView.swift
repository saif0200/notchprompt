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

/// Notch-like silhouette: subtly squared top corners, rounder bottom corners.
/// This tends to read closer to the MacBook notch than a uniformly-rounded rect.
private struct NotchShape: InsettableShape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 22
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)

        // Clamp radii to a sensible range.
        let tr = max(0, min(topRadius, min(r.width, r.height) / 2))
        let br = max(0, min(bottomRadius, min(r.width, r.height) / 2))

        var p = Path()

        // Start at the top-left corner. If `tr == 0`, the top is perfectly straight with sharp corners.
        p.move(to: CGPoint(x: r.minX + tr, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
        if tr > 0 {
            // Top-right corner (rounded)
            p.addArc(
                center: CGPoint(x: r.maxX - tr, y: r.minY + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
        } else {
            // Top-right corner (square)
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }

        // Right edge
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
        // Bottom-right corner (large)
        p.addArc(
            center: CGPoint(x: r.maxX - br, y: r.maxY - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // Bottom edge
        p.addLine(to: CGPoint(x: r.minX + br, y: r.maxY))
        // Bottom-left corner (large)
        p.addArc(
            center: CGPoint(x: r.minX + br, y: r.maxY - br),
            radius: br,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        // Left edge
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + tr))
        if tr > 0 {
            // Top-left corner (rounded)
            p.addArc(
                center: CGPoint(x: r.minX + tr, y: r.minY + tr),
                radius: tr,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            // Top-left corner (square)
            p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        }
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

    var body: some View {
        // Make the top feel like it blends into the notch by:
        // - using a smaller top radius (less "pill" look)
        // - avoiding bright borders right at the top edge
        let shape = NotchShape(topRadius: 0, bottomRadius: 22)
        let hideTopStrokeHeight: CGFloat = 3

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

            ScrollingTextView(
                text: model.script,
                fontSize: CGFloat(model.fontSize),
                speedPointsPerSecond: model.speedPointsPerSecond,
                isRunning: model.isRunning,
                resetToken: model.resetToken
            )
            .padding(.horizontal, 18)
            .padding(.top, 40) // Clearance for notch (approx 32pt) + padding
            .padding(.bottom, 12)
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(width: model.overlayWidth, height: model.overlayHeight)
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
