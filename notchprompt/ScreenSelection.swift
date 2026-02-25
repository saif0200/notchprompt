//
//  ScreenSelection.swift
//  notchprompt
//

import Foundation
import CoreGraphics

struct ScreenDescriptor: Equatable {
    let id: CGDirectDisplayID
    let localizedName: String
    let isBuiltIn: Bool
    let isMenuBarScreen: Bool
}

enum ScreenSelection {
    static func chooseScreenID(
        selectedScreenID: CGDirectDisplayID,
        screens: [ScreenDescriptor]
    ) -> CGDirectDisplayID? {
        guard !screens.isEmpty else { return nil }

        if selectedScreenID != 0,
           let selected = screens.first(where: { $0.id == selectedScreenID }) {
            return selected.id
        }

        if let builtIn = screens.first(where: { $0.isBuiltIn }) {
            return builtIn.id
        }

        if let namedBuiltIn = screens.first(where: { looksBuiltIn($0.localizedName) }) {
            return namedBuiltIn.id
        }

        if let menuBar = screens.first(where: { $0.isMenuBarScreen }) {
            return menuBar.id
        }

        return screens.first?.id
    }

    private static func looksBuiltIn(_ localizedName: String) -> Bool {
        let normalized = localizedName.lowercased()
        return normalized.contains("built-in") || normalized.contains("built in")
    }
}
