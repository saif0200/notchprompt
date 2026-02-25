//
//  ScreenSelectionSelfTests.swift
//  notchprompt
//

import Foundation
import CoreGraphics

enum ScreenSelectionSelfTests {
    static func run() {
        assertBuiltInPreferredByDefault()
        assertUserSelectionRespected()
        assertFallsBackToMenuBarWhenNoBuiltIn()
        assertFallsBackToNameHeuristic()
    }

    private static func assertBuiltInPreferredByDefault() {
        let screens = [
            ScreenDescriptor(id: 100, localizedName: "External", isBuiltIn: false, isMenuBarScreen: true),
            ScreenDescriptor(id: 200, localizedName: "MacBook Pro Display", isBuiltIn: true, isMenuBarScreen: false)
        ]
        let chosen = ScreenSelection.chooseScreenID(selectedScreenID: 0, screens: screens)
        assert(chosen == 200, "Expected built-in display to be preferred")
    }

    private static func assertUserSelectionRespected() {
        let screens = [
            ScreenDescriptor(id: 1, localizedName: "Built-in", isBuiltIn: true, isMenuBarScreen: false),
            ScreenDescriptor(id: 2, localizedName: "Studio Display", isBuiltIn: false, isMenuBarScreen: true)
        ]
        let chosen = ScreenSelection.chooseScreenID(selectedScreenID: 2, screens: screens)
        assert(chosen == 2, "Expected explicit user selection to be respected")
    }

    private static func assertFallsBackToMenuBarWhenNoBuiltIn() {
        let screens = [
            ScreenDescriptor(id: 1, localizedName: "External A", isBuiltIn: false, isMenuBarScreen: false),
            ScreenDescriptor(id: 2, localizedName: "External B", isBuiltIn: false, isMenuBarScreen: true)
        ]
        let chosen = ScreenSelection.chooseScreenID(selectedScreenID: 0, screens: screens)
        assert(chosen == 2, "Expected menu bar display fallback when no built-in display exists")
    }

    private static func assertFallsBackToNameHeuristic() {
        let screens = [
            ScreenDescriptor(id: 7, localizedName: "External", isBuiltIn: false, isMenuBarScreen: true),
            ScreenDescriptor(id: 8, localizedName: "Built-in Retina Display", isBuiltIn: false, isMenuBarScreen: false)
        ]
        let chosen = ScreenSelection.chooseScreenID(selectedScreenID: 0, screens: screens)
        assert(chosen == 8, "Expected built-in name heuristic fallback")
    }
}
