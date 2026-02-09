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

    // Visual / behavior tuning
    @Published var speedPointsPerSecond: Double = 80
    @Published var fontSize: Double = 20
    @Published var overlayWidth: Double = 720
    @Published var overlayHeight: Double = 86

    // Used to signal an immediate reset to the scrolling view.
    @Published private(set) var resetToken: UUID = UUID()

    private init() {}

    func resetScroll() {
        resetToken = UUID()
    }
}
