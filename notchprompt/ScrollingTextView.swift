//
//  ScrollingTextView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import SwiftUI

struct ScrollingTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let speedPointsPerSecond: Double
    let isRunning: Bool
    let resetToken: UUID

    private static let loopGap: CGFloat = 32

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // To make looping seamless, we render two copies of the script back-to-back.
        // When the offset exceeds the height of one copy (+gap), we subtract that
        // amount instead of jumping to 0.
        //
        // Important: NSScrollView + documentView behaves best with frame-based layout.
        // Using an Auto Layout stack view here can leave the document height at 0,
        // which clamps scrolling and looks like "it doesn't move".
        let container = FlippedView(frame: .zero)

        let textView1 = Self.makeTextView(text: text, fontSize: fontSize)
        let textView2 = Self.makeTextView(text: text, fontSize: fontSize)

        container.addSubview(textView1)
        container.addSubview(textView2)

        scrollView.documentView = container

        context.coordinator.attach(scrollView: scrollView, container: container, textView1: textView1, textView2: textView2, loopGap: Self.loopGap)
        context.coordinator.setRunning(isRunning, speed: speedPointsPerSecond)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard
            let textView1 = context.coordinator.textView1,
            let textView2 = context.coordinator.textView2
        else { return }

        // Keep the document width matched to our container so line wrapping stays stable.
        Self.updateWrapping(textView: textView1, width: nsView.contentSize.width)
        Self.updateWrapping(textView: textView2, width: nsView.contentSize.width)

        if textView1.string != text {
            textView1.string = text
        }
        if textView2.string != text {
            textView2.string = text
        }

        let desiredFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView1.font != desiredFont {
            textView1.font = desiredFont
        }
        if textView2.font != desiredFont {
            textView2.font = desiredFont
        }

        context.coordinator.setRunning(isRunning, speed: speedPointsPerSecond)

        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.resetToTop()
        }

        context.coordinator.layoutDocument(loopGap: Self.loopGap)
    }

    private static func makeTextView(text: String, fontSize: CGFloat) -> NSTextView {
        let textView = NSTextView()
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textColor = .white
        textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        return textView
    }

    private static func updateWrapping(textView: NSTextView, width: CGFloat) {
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
    }

    // MARK: - Coordinator

    final class Coordinator {
        weak var scrollView: NSScrollView?
        weak var container: NSView?
        weak var textView1: NSTextView?
        weak var textView2: NSTextView?

        private var timer: Timer?
        private var lastTick: CFTimeInterval?

        private(set) var speed: Double = 0
        private(set) var running: Bool = false

        var lastResetToken: UUID?
        private var loopHeight: CGFloat?
        private var loopGap: CGFloat = 0

        func attach(scrollView: NSScrollView, container: NSView, textView1: NSTextView, textView2: NSTextView, loopGap: CGFloat) {
            self.scrollView = scrollView
            self.container = container
            self.textView1 = textView1
            self.textView2 = textView2
            self.loopGap = loopGap
            resetToTop()
        }

        func setRunning(_ isRunning: Bool, speed: Double) {
            self.speed = speed

            if isRunning == running { return }
            running = isRunning

            if running {
                startTimer()
            } else {
                stopTimer()
            }
        }

        func resetToTop() {
            guard let scrollView else { return }
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func layoutDocument(loopGap: CGFloat) {
            guard
                let scrollView,
                let tv1 = textView1,
                let tv2 = textView2,
                let container,
                let tc1 = tv1.textContainer,
                let lm1 = tv1.layoutManager
            else { return }

            let width = max(1, scrollView.contentSize.width)

            // Keep wrapping stable, then force layout so usedRect height is accurate.
            tv1.frame = NSRect(x: 0, y: 0, width: width, height: 1)
            tv2.frame = NSRect(x: 0, y: 0, width: width, height: 1)
            ScrollingTextView.updateWrapping(textView: tv1, width: width)
            ScrollingTextView.updateWrapping(textView: tv2, width: width)
            lm1.ensureLayout(for: tc1)

            // Height for a single copy.
            let h1 = max(1, lm1.usedRect(for: tc1).height)

            tv1.frame = NSRect(x: 0, y: 0, width: width, height: h1)
            tv2.frame = NSRect(x: 0, y: h1 + loopGap, width: width, height: h1)

            // Ensure the document is taller than the viewport so scrolling isn't clamped.
            let total = h1 + loopGap + h1
            let minDocHeight = max(1, scrollView.contentSize.height + 1)
            container.frame = NSRect(x: 0, y: 0, width: width, height: max(total, minDocHeight))

            loopHeight = h1 + loopGap
        }

        private func startTimer() {
            stopTimer()
            lastTick = nil
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.tick()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }

        private func stopTimer() {
            timer?.invalidate()
            timer = nil
            lastTick = nil
        }

        private func tick() {
            guard
                let scrollView,
                let documentView = scrollView.documentView
            else { return }

            // Ensure we have a valid document height + loop height before attempting to scroll.
            if loopHeight == nil {
                layoutDocument(loopGap: loopGap)
            }

            let now = CACurrentMediaTime()
            let dt: Double
            if let lastTick {
                // Cap dt to avoid a visible jump when the run loop stalls (e.g. window dragged).
                dt = min(0.05, max(0, now - lastTick))
            } else {
                dt = 1.0 / 60.0
            }
            lastTick = now

            let increment = CGFloat(speed * dt)
            var origin = scrollView.contentView.bounds.origin
            origin.y += increment

            // Seamless looping: when we pass one full copy, subtract exactly that height.
            if let loopHeight, origin.y >= loopHeight {
                origin.y -= loopHeight
            } else {
                // Fallback safety if loopHeight isn't computed yet.
                let maxOffset = max(0, documentView.bounds.height - scrollView.contentView.bounds.height)
                if origin.y > maxOffset {
                    origin.y = 0
                }
            }

            scrollView.contentView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
