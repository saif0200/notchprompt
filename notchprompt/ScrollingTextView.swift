//
//  ScrollingTextView.swift
//  notchprompt
//
//  The script, drawn once into bitmaps and slid by Core Animation at the
//  display's own refresh rate. Scrolling costs no text drawing and no SwiftUI
//  work, and the display link stops whenever nothing is moving.
//

import AppKit
import QuartzCore
import SwiftUI

/// The bridge between the model and whichever view is on screen.
@MainActor
final class PrompterScroller {
    fileprivate(set) var engine = ScrollEngine()
    fileprivate weak var view: PrompterTextNSView?

    var onProgress: ((Double) -> Void)?
    var onReachedEnd: (() -> Void)?

    var highlightRange: NSRange? {
        didSet {
            guard highlightRange != oldValue else { return }
            view?.highlightDidChange()
            view?.wake()
        }
    }

    var speedScale: CGFloat {
        get { engine.speedScale }
        set {
            engine.speedScale = newValue
            view?.wake()
        }
    }

    func setRunning(_ running: Bool) {
        engine.isRunning = running
        view?.wake()
    }

    func resetToTop() {
        engine.reset()
        highlightRange = nil
        view?.renderNow()
    }

    func nudge(by delta: CGFloat) {
        engine.nudge(by: delta)
        view?.renderNow()
    }

    func jumpBack(seconds: Double) {
        engine.jump(by: -engine.speed * CGFloat(seconds))
        view?.wake()
    }
}

struct PrompterTextConfiguration: Equatable {
    var text: String
    var sectionRules: [NSRange]
    var wordCount: Int
    var fontFamily: PrompterModel.FontFamily
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var alignment: PrompterModel.TextAlignmentOption
    var textColorHex: String
    var margin: CGFloat
    var wordsPerMinute: Double
    var mode: ScrollEngine.Mode
    var isMirrored: Bool
    var readingPosition: CGFloat
    var cueEnabled: Bool
    var cueColorHex: String
    var cueOpacity: CGFloat
    var focusEnabled: Bool
    var focusLines: Int
    var focusDim: CGFloat
    var highlightColorHex: String

    /// Anything here changes where glyphs land or what colour they're baked in.
    func needsNewLayout(comparedTo other: Self) -> Bool {
        text != other.text
            || sectionRules != other.sectionRules
            || fontFamily != other.fontFamily
            || fontSize != other.fontSize
            || lineSpacing != other.lineSpacing
            || alignment != other.alignment
            || textColorHex != other.textColorHex
            || margin != other.margin
    }
}

struct PrompterTextView: NSViewRepresentable {
    let configuration: PrompterTextConfiguration
    let scroller: PrompterScroller
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> PrompterTextNSView {
        let view = PrompterTextNSView(scroller: scroller)
        view.onScroll = onScroll
        view.apply(configuration)
        return view
    }

    func updateNSView(_ view: PrompterTextNSView, context: Context) {
        view.onScroll = onScroll
        view.apply(configuration)
    }
}

final class PrompterTextNSView: NSView {
    private static let topFade: CGFloat = 24
    private static let bottomFade: CGFloat = 42
    private static let minimumPageHeight: CGFloat = 640

    var onScroll: ((CGFloat) -> Void)?

    private let scroller: PrompterScroller
    private var configuration: PrompterTextConfiguration?

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer()

    private let contentLayer = CALayer()
    private let fadeMask = CAGradientLayer()
    private let highlightLayer = CALayer()
    private let cueLayerLeft = CALayer()
    private let cueLayerRight = CALayer()

    /// Bitmaps of the script, one per page. Two copies of the script on screen at
    /// a loop point share the same ones.
    private var pageImages: [Int: CGImage] = [:]
    private var visiblePageLayers: [PageKey: CALayer] = [:]
    private var reusableLayers: [CALayer] = []
    private var pageHeight = minimumPageHeight
    private var contentHeight: CGFloat = 0
    private var firstLineMid: CGFloat = 0
    private var layoutWidth: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval?
    private var lastProgressReport: CFTimeInterval = 0
    private var highlightDocRect: CGRect?
    private var highlightTargetRect: CGRect?

    private struct PageKey: Hashable {
        let copy: Int
        let page: Int
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    init(scroller: PrompterScroller) {
        self.scroller = scroller
        super.init(frame: .zero)

        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = true

        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)

        fadeMask.startPoint = CGPoint(x: 0.5, y: 1)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.mask = fadeMask
        layer?.addSublayer(contentLayer)

        highlightLayer.cornerRadius = 6
        highlightLayer.cornerCurve = .continuous
        highlightLayer.isHidden = true
        contentLayer.addSublayer(highlightLayer)

        for cue in [cueLayerLeft, cueLayerRight] {
            cue.cornerRadius = 1.5
            layer?.addSublayer(cue)
        }

        disableImplicitAnimations(on: [contentLayer, fadeMask, highlightLayer, cueLayerLeft, cueLayerRight])
        scroller.view = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Configuration

    func apply(_ newConfiguration: PrompterTextConfiguration) {
        guard newConfiguration != configuration else { return }
        let previous = configuration
        configuration = newConfiguration

        if previous.map({ newConfiguration.needsNewLayout(comparedTo: $0) }) ?? true {
            rebuildTextLayout()
        }
        refreshEngineSettings()
        refreshGuides()
        highlightDidChange()
        renderNow()
        wake()
    }

    private func refreshEngineSettings() {
        guard let configuration else { return }
        scroller.engine.mode = configuration.mode
        scroller.engine.speed = ScrollEngine.speed(
            wordsPerMinute: configuration.wordsPerMinute,
            wordCount: configuration.wordCount,
            travel: scroller.engine.travel
        )
    }

    private func rebuildTextLayout() {
        guard let configuration, bounds.width > 0 else { return }

        // Keep whatever word is on the reading line there through the change.
        let anchor = currentReadingCharacter()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = configuration.alignment.nsAlignment
        paragraph.lineSpacing = max(0, (configuration.lineSpacing - 1) * configuration.fontSize)

        let textColor = NSColor(hex: configuration.textColorHex)
        let attributed = NSMutableAttributedString(
            string: configuration.text,
            attributes: [
                .font: configuration.fontFamily.font(size: configuration.fontSize),
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )

        let ruleParagraph = NSMutableParagraphStyle()
        ruleParagraph.alignment = .center
        ruleParagraph.paragraphSpacing = configuration.fontSize * 0.5
        ruleParagraph.paragraphSpacingBefore = configuration.fontSize * 0.5
        for range in configuration.sectionRules where NSMaxRange(range) <= attributed.length {
            attributed.addAttributes([
                .foregroundColor: textColor.withAlphaComponent(0.3),
                .paragraphStyle: ruleParagraph
            ], range: range)
        }

        layoutWidth = bounds.width
        textContainer.size = NSSize(
            width: max(1, bounds.width - 2 * configuration.margin),
            height: .greatestFiniteMagnitude
        )
        textStorage.setAttributedString(attributed)
        layoutManager.ensureLayout(for: textContainer)
        measureLayout()
        pageImages.removeAll()
        highlightDocRect = nil

        if let anchor {
            scroller.engine.setPosition(readingPosition(forCharacter: anchor))
        }
        refreshEngineSettings()
    }

    private func measureLayout() {
        let text = textStorage.string as NSString
        let lastVisible = text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted, options: .backwards)
        guard lastVisible.location != NSNotFound, layoutManager.numberOfGlyphs > 0 else {
            contentHeight = 0
            firstLineMid = 0
            scroller.engine.setLength(travel: 0, cycle: 0)
            return
        }

        contentHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        let firstVisible = text.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted).location
        firstLineMid = lineMid(forCharacter: firstVisible)

        let travel = max(0, lineMid(forCharacter: lastVisible.location) - firstLineMid)
        let cycle = contentHeight + max(48, (configuration?.fontSize ?? 24) * 2)
        scroller.engine.setLength(travel: travel, cycle: cycle)
    }

    private func lineMid(forCharacter index: Int) -> CGFloat {
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil).midY
    }

    private func readingPosition(forCharacter index: Int) -> CGFloat {
        let length = textStorage.length
        guard length > 0 else { return 0 }
        return lineMid(forCharacter: min(index, length - 1)) - firstLineMid
    }

    private func currentReadingCharacter() -> Int? {
        guard textStorage.length > 0, layoutManager.numberOfGlyphs > 0, scroller.engine.position > 0 else { return nil }
        let y = scroller.engine.position + firstLineMid
        let glyph = layoutManager.glyphIndex(for: CGPoint(x: textContainer.size.width / 2, y: y), in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    // MARK: - Sizing

    override func setFrameSize(_ newSize: NSSize) {
        let previousHeight = bounds.height
        super.setFrameSize(newSize)
        guard newSize.width > 0, newSize.height > 0 else { return }

        if abs(newSize.width - layoutWidth) > 0.5 {
            rebuildTextLayout()
        }
        if abs(newSize.height - previousHeight) > 0.5 {
            pageHeight = max(Self.minimumPageHeight, ceil(newSize.height * 1.5))
            pageImages.removeAll()
        }

        withoutAnimations {
            contentLayer.frame = bounds
            fadeMask.frame = bounds
        }
        refreshEngineSettings()
        refreshGuides()
        renderNow()
        wake()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        pageImages.removeAll()
        renderNow()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = nil
        guard window != nil else { return }

        let link = displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        link.isPaused = !scroller.engine.needsFrames
        displayLink = link
        renderNow()
    }

    // MARK: - Frames

    func wake() {
        guard let displayLink, displayLink.isPaused, scroller.engine.needsFrames else { return }
        lastFrameTimestamp = nil
        displayLink.isPaused = false
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let delta = lastFrameTimestamp.map { now - $0 } ?? link.duration
        lastFrameTimestamp = now

        let result = scroller.engine.advance(by: CGFloat(delta))
        advanceHighlight(by: CGFloat(delta))
        renderNow()
        reportProgress(at: now)

        if result.reachedEnd {
            reportProgress(at: .greatestFiniteMagnitude)
            scroller.onReachedEnd?()
        }
        if !scroller.engine.needsFrames, highlightIsSettled {
            reportProgress(at: .greatestFiniteMagnitude)
            link.isPaused = true
        }
    }

    private func reportProgress(at time: CFTimeInterval) {
        guard time - lastProgressReport >= 0.25 else { return }
        lastProgressReport = time == .greatestFiniteMagnitude ? 0 : time
        scroller.onProgress?(scroller.engine.progress)
    }

    /// Lays out the page layers for the current position. Pixel-snapped: at a
    /// slow pace a fractional offset would shimmer as the text resampled.
    func renderNow() {
        guard let configuration, bounds.height > 0, contentHeight > 0 else {
            removeAllPageLayers()
            return
        }

        let scale = backingScale
        let height = bounds.height
        let readingY = height * configuration.readingPosition
        let exactTop = scroller.engine.position + firstLineMid - readingY
        let documentTop = (exactTop * scale).rounded() / scale
        let documentBottom = documentTop + height

        let cycle = scroller.engine.cycle
        let isLooping = configuration.mode == .loop && cycle > 0
        let firstCopy = isLooping ? Int(floor(documentTop / cycle)) : 0
        let lastCopy = isLooping ? Int(floor(documentBottom / cycle)) : 0

        var needed: [PageKey: CGRect] = [:]
        for copy in firstCopy...lastCopy {
            let copyOffset = CGFloat(copy) * cycle
            let lower = max(documentTop - copyOffset, 0)
            let upper = min(documentBottom - copyOffset, contentHeight)
            guard lower < upper else { continue }

            for page in Int(floor(lower / pageHeight))...Int(floor(upper / pageHeight)) {
                let pageTop = copyOffset + CGFloat(page) * pageHeight
                let y = height - (pageTop - documentTop) - pageHeight
                needed[PageKey(copy: copy, page: page)] = CGRect(x: 0, y: y, width: bounds.width, height: pageHeight)
            }
        }

        withoutAnimations {
            for (key, layer) in visiblePageLayers where needed[key] == nil {
                layer.isHidden = true
                reusableLayers.append(layer)
                visiblePageLayers[key] = nil
            }

            for (key, frame) in needed {
                let layer = visiblePageLayers[key] ?? dequeuePageLayer()
                visiblePageLayers[key] = layer
                layer.contents = image(forPage: key.page)
                layer.contentsScale = scale
                layer.frame = frame
                layer.isHidden = false
            }

            contentLayer.sublayerTransform = configuration.isMirrored
                ? CATransform3DConcat(CATransform3DMakeScale(-1, 1, 1), CATransform3DMakeTranslation(bounds.width, 0, 0))
                : CATransform3DIdentity
            positionHighlight(documentTop: documentTop)
        }

        trimPageCache(around: needed.keys.map(\.page))
    }

    private func dequeuePageLayer() -> CALayer {
        let layer = reusableLayers.popLast() ?? CALayer()
        if layer.superlayer == nil {
            layer.anchorPoint = .zero
            disableImplicitAnimations(on: [layer])
            contentLayer.insertSublayer(layer, below: highlightLayer)
        }
        return layer
    }

    private func removeAllPageLayers() {
        withoutAnimations {
            for layer in visiblePageLayers.values {
                layer.isHidden = true
                reusableLayers.append(layer)
            }
            visiblePageLayers.removeAll()
            highlightLayer.isHidden = true
        }
    }

    private func trimPageCache(around pages: [Int]) {
        guard pageImages.count > 8, let low = pages.min(), let high = pages.max() else { return }
        for page in pageImages.keys where page < low - 2 || page > high + 2 {
            pageImages[page] = nil
        }
    }

    private func image(forPage page: Int) -> CGImage? {
        if let cached = pageImages[page] { return cached }
        guard let configuration else { return nil }

        let scale = backingScale
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(pageHeight * scale))
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: pageHeight)
        context.scaleBy(x: 1, y: -1)

        let pageTop = CGFloat(page) * pageHeight
        let rect = CGRect(x: 0, y: pageTop, width: textContainer.size.width, height: pageHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: configuration.margin, y: -pageTop))
        NSGraphicsContext.restoreGraphicsState()

        let image = context.makeImage()
        pageImages[page] = image
        return image
    }

    // MARK: - Word highlight

    private var highlightIsSettled: Bool {
        guard let highlightDocRect, let highlightTargetRect else { return true }
        return abs(highlightDocRect.minX - highlightTargetRect.minX) < 0.5
            && abs(highlightDocRect.minY - highlightTargetRect.minY) < 0.5
            && abs(highlightDocRect.width - highlightTargetRect.width) < 0.5
    }

    func highlightDidChange() {
        guard let configuration else { return }
        withoutAnimations {
            highlightLayer.backgroundColor = NSColor(hex: configuration.highlightColorHex).withAlphaComponent(0.34).cgColor
        }

        guard let range = scroller.highlightRange, NSMaxRange(range) <= textStorage.length else {
            highlightTargetRect = nil
            highlightDocRect = nil
            scroller.engine.followTarget = nil
            withoutAnimations { highlightLayer.isHidden = true }
            return
        }

        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        highlightTargetRect = rect
        if highlightDocRect == nil { highlightDocRect = rect }
        scroller.engine.followTarget = lineMid(forCharacter: range.location) - firstLineMid
    }

    private func advanceHighlight(by delta: CGFloat) {
        guard let current = highlightDocRect, let target = highlightTargetRect else { return }
        let blend = 1 - exp(-18 * delta)
        highlightDocRect = CGRect(
            x: current.minX + (target.minX - current.minX) * blend,
            y: current.minY + (target.minY - current.minY) * blend,
            width: current.width + (target.width - current.width) * blend,
            height: target.height
        )
    }

    private func positionHighlight(documentTop: CGFloat) {
        guard let configuration, let rect = highlightDocRect else {
            highlightLayer.isHidden = true
            return
        }
        // Highlight the glyphs, not the line spacing below them.
        let glyphHeight = configuration.fontSize * 1.25
        highlightLayer.isHidden = false
        highlightLayer.frame = CGRect(
            x: configuration.margin + rect.minX - 4,
            y: bounds.height - (rect.minY - documentTop) - glyphHeight - 1,
            width: rect.width + 8,
            height: glyphHeight + 2
        )
    }

    // MARK: - Guides

    private func refreshGuides() {
        guard let configuration, bounds.height > 0 else { return }

        let height = bounds.height
        let readingY = height * configuration.readingPosition
        let lineHeight = configuration.fontSize * max(configuration.lineSpacing, 1.15)

        var stops: [(CGFloat, CGFloat)]
        let resting: CGFloat = configuration.focusEnabled ? 1 - configuration.focusDim : 1
        stops = [(0, 0), (Self.topFade, resting)]

        if configuration.focusEnabled {
            let half = lineHeight * CGFloat(configuration.focusLines) / 2
            let soft = lineHeight * 0.5
            let bandTop = max(Self.topFade, readingY - half)
            let bandBottom = min(height - Self.bottomFade, readingY + half)
            stops += [
                (max(Self.topFade, bandTop - soft), resting),
                (bandTop, 1),
                (bandBottom, 1),
                (min(height - Self.bottomFade, bandBottom + soft), resting)
            ]
        }
        stops += [(height - Self.bottomFade, resting), (height, 0)]

        withoutAnimations {
            fadeMask.colors = stops.map { NSColor.white.withAlphaComponent($0.1).cgColor }
            fadeMask.locations = stops.map { NSNumber(value: Double($0.0 / height)) }

            let cueColor = NSColor(hex: configuration.cueColorHex).withAlphaComponent(configuration.cueOpacity).cgColor
            let cueY = height - readingY - 1.5
            let cueWidth = max(8, min(configuration.margin - 10, 18))
            cueLayerLeft.frame = CGRect(x: 6, y: cueY, width: cueWidth, height: 3)
            cueLayerRight.frame = CGRect(x: bounds.width - 6 - cueWidth, y: cueY, width: cueWidth, height: 3)
            for cue in [cueLayerLeft, cueLayerRight] {
                cue.backgroundColor = cueColor
                cue.isHidden = !configuration.cueEnabled
            }
        }
    }

    // MARK: - Input

    override func scrollWheel(with event: NSEvent) {
        // `scrollingDeltaY` already has the user's natural-scrolling choice in it.
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        onScroll?(-delta)
    }

    private func withoutAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private func disableImplicitAnimations(on layers: [CALayer]) {
        let none: [String: CAAction] = [
            "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull(),
            "hidden": NSNull(), "backgroundColor": NSNull(), "sublayerTransform": NSNull()
        ]
        layers.forEach { $0.actions = none }
    }
}
