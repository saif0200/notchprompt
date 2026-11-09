//
//  ColorUtilities.swift
//  notchprompt
//

import AppKit
import SwiftUI

private func rgbComponents(fromHex hex: String) -> (CGFloat, CGFloat, CGFloat) {
    let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
    var rgb: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&rgb)
    return (
        CGFloat((rgb >> 16) & 0xFF) / 255,
        CGFloat((rgb >> 8) & 0xFF) / 255,
        CGFloat(rgb & 0xFF) / 255
    )
}

extension NSColor {
    convenience init(hex: String) {
        let (r, g, b) = rgbComponents(fromHex: hex)
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    init(hex: String) {
        let (r, g, b) = rgbComponents(fromHex: hex)
        self.init(.sRGB, red: Double(r), green: Double(g), blue: Double(b), opacity: 1)
    }

    var hexString: String {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(
            format: "#%02X%02X%02X",
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded())
        )
    }
}

extension PrompterModel {
    var textColor: Color { Color(hex: textColorHex) }
    var backgroundColor: Color { Color(hex: backgroundColorHex) }
}
