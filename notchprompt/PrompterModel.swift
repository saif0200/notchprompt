//
//  PrompterModel.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import Foundation
import Combine

@MainActor
final class PrompterModel: ObservableObject {
    static let shared = PrompterModel()

    @Published var script: String = """
Paste your script here.

Tip: Use the menu bar icon to start/pause or reset the scroll.
"""

    @Published var isRunning: Bool = false
    @Published var isClickThrough: Bool = true
    @Published var isHovering: Bool = false

    // Visual / behavior tuning
    @Published var speedPointsPerSecond: Double = 80
    @Published var fontSize: Double = 20
    @Published var overlayWidth: Double = 600
    @Published var overlayHeight: Double = 150
    // Fraction of the viewport height to fade at top and bottom.
    let edgeFadeFraction: Double = 0.20

    // Used to signal an immediate reset to the scrolling view.
    @Published private(set) var resetToken: UUID = UUID()

    private init() {}

    func resetScroll() {
        resetToken = UUID()
    }
}
