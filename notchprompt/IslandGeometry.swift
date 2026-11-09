//
//  IslandGeometry.swift
//  notchprompt
//
//  Everything the overlay needs to know about the top of a display, as plain
//  values. macOS reports the free space on either side of the camera
//  (`auxiliaryTopLeftArea` / `auxiliaryTopRightArea`), so the camera is whatever
//  sits between them. That holds for the OLED MacBook Pro's Dynamic Island
//  (59 x 40 pt at the default scale), for the older notch, and at every scaled
//  resolution, so nothing here is keyed to a model name.
//

import CoreGraphics

/// How the island meets the top of the display.
enum IslandAttachment: String, CaseIterable {
    /// A free-floating pill with a sliver of screen above it, like the iPhone.
    case floating
    /// Joined to the top edge of the display.
    case attached

    var label: String {
        switch self {
        case .floating: return "Floating"
        case .attached: return "Joined to top edge"
        }
    }
}

enum IslandForm: Equatable {
    /// Barely wider than the camera. Nothing lit, so nothing to burn in.
    case idle
    /// Status either side of the camera.
    case compact
    /// The prompter itself.
    case expanded
}

struct DisplayTopEdge: Equatable {
    var screenFrame: CGRect
    /// Camera housing in global AppKit coordinates, nil on displays without one.
    var cutout: CGRect?
    var menuBarHeight: CGFloat
    var backingScale: CGFloat

    /// The camera is what's left between the two usable strips of the menu bar.
    static func cutout(
        screenFrame: CGRect,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) -> CGRect? {
        guard let left = auxiliaryTopLeft, let right = auxiliaryTopRight else { return nil }
        let width = right.minX - left.maxX
        let height = max(left.height, right.height)
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: left.maxX, y: screenFrame.maxY - height, width: width, height: height)
    }
}

struct IslandCorners: Equatable {
    var top: CGFloat
    var bottom: CGFloat
}

struct IslandLayout: Equatable {
    static let defaultExpandedSize = CGSize(width: 560, height: 260)
    static let minimumExpandedSize = CGSize(width: 400, height: 160)
    static let maximumExpandedSize = CGSize(width: 1000, height: 640)

    /// The notch reaches the bezel, so an island can't float over it. The Dynamic
    /// Island is far narrower than any notch at any display scale.
    static let widestFloatingCutout: CGFloat = 120
    static let floatingTopInset: CGFloat = 4
    /// Height of the status band on displays with no camera to measure.
    static let fallbackBandHeight: CGFloat = 37

    /// Width of the status area each side of the camera.
    static let compactLobeWidth: CGFloat = 78
    static let idleLobeWidth: CGFloat = 14
    /// A camera-less display still needs something to centre on.
    static let fallbackCutoutWidth: CGFloat = 40

    var edge: DisplayTopEdge
    var requestedAttachment: IslandAttachment
    var requestedExpandedSize: CGSize
    /// Points to shift a floating island down (or up, if negative) to sit true on
    /// the camera. macOS reports the housing's box, not the pill inside it.
    var verticalNudge: CGFloat = 0

    var isDynamicIsland: Bool {
        guard let cutout = edge.cutout else { return false }
        return cutout.width < Self.widestFloatingCutout
    }

    var attachment: IslandAttachment {
        if let cutout = edge.cutout, cutout.width >= Self.widestFloatingCutout { return .attached }
        return requestedAttachment
    }

    /// Everything above this line of the screen belongs to the camera's row.
    var bandHeight: CGFloat {
        if let cutout = edge.cutout { return cutout.height }
        return max(32, min(edge.menuBarHeight, Self.fallbackBandHeight))
    }

    var cutoutWidth: CGFloat { edge.cutout?.width ?? Self.fallbackCutoutWidth }
    var topInset: CGFloat { attachment == .floating ? max(0, Self.floatingTopInset + verticalNudge) : 0 }
    var centerX: CGFloat { edge.cutout?.midX ?? edge.screenFrame.midX }
    /// A floating island ends level with the bottom of the camera.
    var compactHeight: CGFloat { bandHeight - (attachment == .floating ? Self.floatingTopInset : 0) }

    var expandedSize: CGSize {
        let maxWidth = min(Self.maximumExpandedSize.width, edge.screenFrame.width - 48)
        let maxHeight = min(Self.maximumExpandedSize.height, (edge.screenFrame.height * 0.7).rounded())
        return CGSize(
            width: min(max(requestedExpandedSize.width, Self.minimumExpandedSize.width), maxWidth).rounded(),
            height: min(max(requestedExpandedSize.height, Self.minimumExpandedSize.height), maxHeight).rounded()
        )
    }

    /// Top of the expanded island down to where the script may be drawn.
    var expandedHeaderHeight: CGFloat { bandHeight - topInset + 6 }

    func size(for form: IslandForm) -> CGSize {
        switch form {
        case .idle:
            return CGSize(width: (cutoutWidth + 2 * Self.idleLobeWidth).rounded(), height: compactHeight)
        case .compact:
            return CGSize(width: (cutoutWidth + 2 * Self.compactLobeWidth).rounded(), height: compactHeight)
        case .expanded:
            return expandedSize
        }
    }

    func corners(for form: IslandForm) -> IslandCorners {
        let attached = attachment == .attached
        switch form {
        case .idle, .compact:
            return attached
                ? IslandCorners(top: 0, bottom: min(14, compactHeight / 2))
                : IslandCorners(top: compactHeight / 2, bottom: compactHeight / 2)
        case .expanded:
            return attached ? IslandCorners(top: 0, bottom: 30) : IslandCorners(top: 30, bottom: 30)
        }
    }

    /// The panel exactly wraps the island so it never blocks clicks around it.
    /// Always centred on the camera, always touching the top of the display.
    func panelFrame(for form: IslandForm) -> CGRect {
        let size = size(for: form)
        let height = size.height + topInset
        let x = snap(centerX - size.width / 2)
        return CGRect(x: x, y: edge.screenFrame.maxY - height, width: size.width, height: height)
    }

    /// The slot either side of the camera inside the expanded header.
    func expandedHeaderSlotWidth(cornerClearance: CGFloat = 20, cameraClearance: CGFloat = 14) -> CGFloat {
        max(0, (expandedSize.width - cutoutWidth) / 2 - cornerClearance - cameraClearance)
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        let scale = max(edge.backingScale, 1)
        return (value * scale).rounded() / scale
    }
}
