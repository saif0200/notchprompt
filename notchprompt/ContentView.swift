//
//  ContentView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import CoreGraphics
import SwiftUI

struct ContentView: View {
    @ObservedObject private var model = PrompterModel.shared

    var body: some View {
        Form {
            playbackSection
            voiceSection
            textSection
            islandSection
            readingGuideSection
            privacySection
            shortcutsSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 460)
    }

    // MARK: - Playback

    private var playbackSection: some View {
        Section("Playback") {
            Toggle("Finish at a set time", isOn: Binding(
                get: { model.timedScrollEnabled },
                set: { model.timedScrollEnabled = $0 }
            ))

            if model.timedScrollEnabled {
                durationRow
                LabeledContent("Pace needed", value: "\(Int(model.effectiveWordsPerMinute)) words per minute")
            } else {
                sliderRow(
                    "Reading pace",
                    value: "\(Int(model.wordsPerMinute)) wpm",
                    slider: Slider(
                        value: Binding(
                            get: { model.wordsPerMinute },
                            set: { model.setSpeed($0) }
                        ),
                        in: PrompterModel.wordsPerMinuteRange,
                        step: PrompterModel.speedStep
                    )
                )
                Picker("Preset", selection: Binding(
                    get: { model.wordsPerMinute },
                    set: { model.applySpeedPreset($0) }
                )) {
                    Text("Relaxed").tag(PrompterModel.speedPresetSlow)
                    Text("Natural").tag(PrompterModel.speedPresetNormal)
                    Text("Brisk").tag(PrompterModel.speedPresetFast)
                    if ![PrompterModel.speedPresetSlow, PrompterModel.speedPresetNormal, PrompterModel.speedPresetFast].contains(model.wordsPerMinute) {
                        Text("Custom").tag(model.wordsPerMinute)
                    }
                }
                .pickerStyle(.segmented)
            }

            LabeledContent("Script length", value: "\(model.wordCount) words, \(model.formattedEstimatedReadDuration())")

            Picker("At the end", selection: Binding(
                get: { model.scrollMode },
                set: { model.setScrollMode($0) }
            )) {
                Text("Stop").tag(PrompterModel.ScrollMode.stopAtEnd)
                Text("Loop").tag(PrompterModel.ScrollMode.infinite)
            }
            .pickerStyle(.segmented)

            Picker("Countdown", selection: $model.countdownBehavior) {
                ForEach(PrompterModel.CountdownBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.label).tag(behavior)
                }
            }

            sliderRow(
                "Countdown length",
                value: "\(model.countdownSeconds)s",
                slider: Slider(
                    value: Binding(
                        get: { Double(model.countdownSeconds) },
                        set: { model.countdownSeconds = Int($0.rounded()) }
                    ),
                    in: 1...10,
                    step: 1
                )
            )
            .disabled(model.countdownBehavior == .never)

            Toggle("Show elapsed and remaining time", isOn: $model.showTimeDisplay)
        }
    }

    private var durationRow: some View {
        let minutes = Binding<Int>(
            get: { Int(model.targetDurationSeconds) / 60 },
            set: { model.targetDurationSeconds = Double($0 * 60 + Int(model.targetDurationSeconds) % 60) }
        )
        let seconds = Binding<Int>(
            get: { Int(model.targetDurationSeconds) % 60 },
            set: { model.targetDurationSeconds = Double(Int(model.targetDurationSeconds) / 60 * 60 + $0) }
        )
        return LabeledContent("Finish in") {
            HStack(spacing: 12) {
                Stepper("\(minutes.wrappedValue) min", value: minutes, in: 0...60)
                Stepper("\(seconds.wrappedValue) sec", value: seconds, in: 0...59)
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            Toggle("Scroll only while I'm talking", isOn: Binding(
                get: { model.voiceScrollEnabled },
                set: { model.setVoiceScrollEnabled($0) }
            ))
            if let message = model.voiceScrollStatus.failureMessage {
                failureRow(message)
            }

            Toggle("Follow my voice word by word", isOn: Binding(
                get: { model.voiceTrackingEnabled },
                set: { model.setVoiceTrackingEnabled($0) }
            ))

            if SpeechEngineChoice.available.count > 1 {
                Picker("Speech engine", selection: Binding(
                    get: { model.speechEngine },
                    set: { model.setSpeechEngine($0) }
                )) {
                    ForEach(SpeechEngineChoice.available, id: \.self) { engine in
                        Text(engine.label).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
            }

            if model.voiceTrackingEnabled {
                modelStatusRow
                if let message = model.voiceTrackingStatus.failureMessage {
                    failureRow(message)
                }
                ColorPicker("Highlight colour", selection: colorBinding(\.highlightColorHex), supportsOpacity: false)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(voiceFooter)
                .foregroundStyle(.secondary)
        }
    }

    private var voiceFooter: String {
        let microphone = "The microphone is only on while the script is playing."
        guard SpeechEngineChoice.isAppleAvailable else {
            return "\(microphone) Whisper is built in, runs offline and understands English."
        }
        return "\(microphone) Apple Speech follows your Mac's language, and macOS may download it once. Whisper is built in, runs offline and understands English."
    }

    private var modelStatusRow: some View {
        LabeledContent("Speech model") {
            switch model.speechModelState {
            case .notLoaded:
                Text("Not loaded").foregroundStyle(.secondary)
            case .loading(let progress):
                if progress > 0 {
                    HStack(spacing: 8) {
                        ProgressView(value: progress).frame(width: 110)
                        Text("\(Int(progress * 100))%").foregroundStyle(.secondary).monospacedDigit()
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Getting ready").foregroundStyle(.secondary)
                    }
                }
            case .loaded:
                Text("Ready").foregroundStyle(.secondary)
            case .failed(let message):
                Text(message).foregroundStyle(.red).multilineTextAlignment(.trailing)
            }
        }
    }

    private func failureRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
    }

    // MARK: - Text

    private var textSection: some View {
        Section("Text") {
            Picker("Font", selection: $model.fontFamily) {
                ForEach(PrompterModel.FontFamily.allCases, id: \.self) { family in
                    Text(family.label).tag(family)
                }
            }

            sliderRow(
                "Size",
                value: "\(Int(model.fontSize))",
                slider: Slider(value: $model.fontSize, in: PrompterModel.fontSizeRange, step: 1)
            )

            sliderRow(
                "Line spacing",
                value: String(format: "%.1fx", model.lineSpacing),
                slider: Slider(value: $model.lineSpacing, in: 1...3, step: 0.05)
            )

            sliderRow(
                "Side margins",
                value: "\(Int(model.horizontalMargin))",
                slider: Slider(value: $model.horizontalMargin, in: 10...120, step: 2)
            )

            Picker("Alignment", selection: $model.textAlignment) {
                ForEach(PrompterModel.TextAlignmentOption.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Mirror text for a beam-splitter", isOn: $model.mirrorMode)
        }
    }

    // MARK: - Island

    private var islandSection: some View {
        Section {
            Picker("Show on", selection: screenSelection) {
                Text("Automatic (built-in display)").tag(CGDirectDisplayID(0))
                ForEach(NSScreen.screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(screenID(for: screen))
                }
            }

            Picker("Shape", selection: $model.islandAttachment) {
                ForEach(IslandAttachment.allCases, id: \.self) { attachment in
                    Text(attachment.label).tag(attachment)
                }
            }
            .pickerStyle(.segmented)

            sliderRow(
                "Fine-tune position",
                value: model.islandVerticalNudge == 0 ? "0" : String(format: "%+.0f", model.islandVerticalNudge),
                slider: Slider(value: $model.islandVerticalNudge, in: PrompterModel.islandNudgeRange, step: 1)
            )
            .disabled(model.islandAttachment == .attached)

            sliderRow(
                "Width",
                value: "\(Int(model.overlayWidth))",
                slider: Slider(
                    value: $model.overlayWidth,
                    in: Double(IslandLayout.minimumExpandedSize.width)...Double(IslandLayout.maximumExpandedSize.width),
                    step: 10
                )
            )

            sliderRow(
                "Height",
                value: "\(Int(model.overlayHeight))",
                slider: Slider(
                    value: $model.overlayHeight,
                    in: Double(IslandLayout.minimumExpandedSize.height)...Double(IslandLayout.maximumExpandedSize.height),
                    step: 10
                )
            )

            Picker("Colours", selection: themeSelection) {
                ForEach(PrompterModel.ColorTheme.allCases, id: \.self) { theme in
                    Text(theme.label).tag(Optional(theme))
                }
                if themeSelection.wrappedValue == nil {
                    Text("Custom").tag(PrompterModel.ColorTheme?.none)
                }
            }

            ColorPicker("Text colour", selection: colorBinding(\.textColorHex), supportsOpacity: false)
            ColorPicker("Background colour", selection: colorBinding(\.backgroundColorHex), supportsOpacity: false)

            sliderRow(
                "Background opacity",
                value: "\(Int((model.backgroundOpacity * 100).rounded()))%",
                slider: Slider(value: $model.backgroundOpacity, in: 0.3...1, step: 0.05)
            )
        } header: {
            Text("Island")
        } footer: {
            Text("Drag the island's bottom corners to resize it. A pure black background blends with the camera.")
                .foregroundStyle(.secondary)
        }
    }

    private var screenSelection: Binding<CGDirectDisplayID> {
        Binding(
            get: {
                // A display that's been unplugged has no row to show.
                let known = NSScreen.screens.contains { screenID(for: $0) == model.selectedScreenID }
                return known ? model.selectedScreenID : 0
            },
            set: { model.selectedScreenID = $0 }
        )
    }

    private var themeSelection: Binding<PrompterModel.ColorTheme?> {
        Binding(
            get: {
                PrompterModel.ColorTheme.allCases.first {
                    $0.textHex == model.textColorHex && $0.backgroundHex == model.backgroundColorHex
                }
            },
            set: { theme in
                if let theme { model.applyColorTheme(theme) }
            }
        )
    }

    // MARK: - Reading guide

    private var readingGuideSection: some View {
        Section {
            sliderRow(
                "Reading line",
                value: "\(Int((model.cueLinePosition * 100).rounded()))%",
                slider: Slider(value: $model.cueLinePosition, in: 0.1...0.9, step: 0.01)
            )

            Toggle("Show markers at the reading line", isOn: $model.cueLineEnabled)

            ColorPicker("Marker colour", selection: colorBinding(\.cueLineColorHex), supportsOpacity: false)
                .disabled(!model.cueLineEnabled)

            sliderRow(
                "Marker opacity",
                value: "\(Int((model.cueLineOpacity * 100).rounded()))%",
                slider: Slider(value: $model.cueLineOpacity, in: 0.1...1, step: 0.05)
            )
            .disabled(!model.cueLineEnabled)

            Toggle("Dim everything but the reading line", isOn: $model.focusModeEnabled)

            sliderRow(
                "Lines in focus",
                value: "\(model.focusVisibleLines)",
                slider: Slider(
                    value: Binding(
                        get: { Double(model.focusVisibleLines) },
                        set: { model.focusVisibleLines = Int($0.rounded()) }
                    ),
                    in: 1...10,
                    step: 1
                )
            )
            .disabled(!model.focusModeEnabled)

            sliderRow(
                "Dim amount",
                value: "\(Int((model.focusDimOpacity * 100).rounded()))%",
                slider: Slider(value: $model.focusDimOpacity, in: 0.1...0.95, step: 0.05)
            )
            .disabled(!model.focusModeEnabled)
        } header: {
            Text("Reading Guide")
        } footer: {
            Text("Keep the reading line high: the closer to the camera, the more it looks like you're looking at the lens.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Toggle("Show island", isOn: $model.isOverlayVisible)
            Toggle("Hide from screen sharing", isOn: $model.privacyModeEnabled)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Some apps can still capture hidden windows. Do a test share with the app you'll present in.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shortcuts

    private var shortcutsSection: some View {
        Section("Keyboard Shortcuts") {
            shortcutRow(.startPause, "Start or pause")
            shortcutRow(.reset, "Back to top")
            shortcutRow(.jumpBack, "Jump back 5 seconds")
            shortcutRow(.speedUp, "Faster")
            shortcutRow(.speedDown, "Slower")
            shortcutRow(.toggleOverlay, "Show or hide the island")
            shortcutRow(.togglePrivacy, "Hide from screen sharing")
        }
    }

    private func shortcutRow(_ command: ShortcutCommand, _ title: String) -> some View {
        LabeledContent(title, value: command.displayShortcut)
    }

    // MARK: - Helpers

    private func sliderRow<SliderView: View>(_ title: String, value: String, slider: SliderView) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                slider.labelsHidden()
                Text(value)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<PrompterModel, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: model[keyPath: keyPath]) },
            set: { model[keyPath: keyPath] = $0.hexString }
        )
    }

    private func screenID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
