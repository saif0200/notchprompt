//
//  ContentView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import SwiftUI
import AppKit
import CoreGraphics

struct ContentView: View {
    @ObservedObject private var model = PrompterModel.shared

    private let rowLabelWidth: CGFloat = 150

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                playbackSection
                appearanceSection
                displaySection
                privacySection
                footerSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 540)
    }

    private var playbackSection: some View {
        GroupBox("Playback") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Speed")
                        .frame(width: rowLabelWidth, alignment: .leading)
                    Slider(value: $model.speedPointsPerSecond, in: 10...300, step: 5)
                    Text("\(Int(model.speedPointsPerSecond))")
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }

                HStack {
                    Text("Scroll mode")
                        .frame(width: rowLabelWidth, alignment: .leading)
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.scrollMode },
                            set: { model.setScrollMode($0) }
                        )
                    ) {
                        Text("Infinite").tag(PrompterModel.ScrollMode.infinite)
                        Text("Stop at end").tag(PrompterModel.ScrollMode.stopAtEnd)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                HStack {
                    Text("Countdown")
                        .frame(width: rowLabelWidth, alignment: .leading)
                    Picker("", selection: $model.countdownBehavior) {
                        ForEach(PrompterModel.CountdownBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.label).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Spacer(minLength: 0)
                }

                HStack {
                    Text("Countdown duration")
                        .frame(width: rowLabelWidth, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(model.countdownSeconds) },
                            set: { model.countdownSeconds = Int($0.rounded()) }
                        ),
                        in: 0...10,
                        step: 1
                    )
                    .disabled(model.countdownBehavior == .never)
                    Text("\(model.countdownSeconds)s")
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    private var appearanceSection: some View {
        GroupBox("Appearance") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Font size")
                        .frame(width: rowLabelWidth, alignment: .leading)
                    Slider(value: $model.fontSize, in: 12...40, step: 1)
                    Text("\(Int(model.fontSize))")
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }

                HStack {
                    Text("Overlay width")
                        .frame(width: rowLabelWidth, alignment: .leading)
                    Slider(value: $model.overlayWidth, in: 400...1200, step: 10)
                    Text("\(Int(model.overlayWidth))")
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }

                HStack {
                    Text("Overlay height")
                        .frame(width: rowLabelWidth, alignment: .leading)
                    Slider(value: $model.overlayHeight, in: 120...300, step: 2)
                    Text("\(Int(model.overlayHeight))")
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    private var displaySection: some View {
        GroupBox("Display") {
            HStack {
                Text("Show overlay on")
                    .frame(width: rowLabelWidth, alignment: .leading)
                Picker("", selection: $model.selectedScreenID) {
                    Text("Auto (Built-in)").tag(CGDirectDisplayID(0))
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(screenID(for: screen))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer(minLength: 0)
            }
        }
    }

    private var privacySection: some View {
        GroupBox("Privacy") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show overlay", isOn: $model.isOverlayVisible)
                Toggle("Limit screen sharing capture", isOn: $model.privacyModeEnabled)
                Text("Best effort only. Capture behavior can vary by app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Spacer()
            Text("Open Script Editor and runtime controls from the menu bar.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func screenID(for screen: NSScreen) -> CGDirectDisplayID {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return 0
        }
        return CGDirectDisplayID(n.uint32Value)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewDisplayName("Default")

        ContentView()
            .frame(width: 560, height: 360)
            .previewDisplayName("Small Height Scroll")
    }
}
#endif
