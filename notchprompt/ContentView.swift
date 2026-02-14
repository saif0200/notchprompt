//
//  ContentView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var model = PrompterModel.shared
    @State private var fileErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notchprompt")
                .font(.system(size: 18, weight: .semibold))

            Toggle("Click-through overlay (no cursor blocking)", isOn: $model.isClickThrough)

            HStack(spacing: 12) {
                Button(model.isRunning ? "Pause" : (model.isCountingDown ? "Counting..." : "Start")) {
                    model.toggleRunning()
                }
                .disabled(model.isCountingDown)

                Button("Reset") {
                    model.resetScroll()
                }

                Button("Jump Back 5s") {
                    model.jumpBack(seconds: 5)
                }
            }

            GroupBox("Script") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button("Import...") {
                            Task {
                                await importScriptAsync()
                            }
                        }

                        Button("Export...") {
                            Task {
                                await exportScriptAsync()
                            }
                        }
                    }

                    HStack {
                        Text("Estimated read time: \(model.formattedEstimatedReadDuration())")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    TextEditor(text: $model.script)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 240)
                }
            }

            GroupBox("Prompter") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Speed")
                            .frame(width: 72, alignment: .leading)
                        Slider(value: $model.speedPointsPerSecond, in: 10...300, step: 5)
                        Text("\(Int(model.speedPointsPerSecond))")
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack(spacing: 8) {
                        Text("Presets")
                            .frame(width: 72, alignment: .leading)
                        Button("Slow") {
                            model.applySpeedPreset(PrompterModel.speedPresetSlow)
                        }
                        Button("Normal") {
                            model.applySpeedPreset(PrompterModel.speedPresetNormal)
                        }
                        Button("Fast") {
                            model.applySpeedPreset(PrompterModel.speedPresetFast)
                        }
                    }

                    HStack {
                        Text("Font")
                            .frame(width: 72, alignment: .leading)
                        Slider(value: $model.fontSize, in: 12...40, step: 1)
                        Text("\(Int(model.fontSize))")
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack {
                        Text("Width")
                            .frame(width: 72, alignment: .leading)
                        Slider(value: $model.overlayWidth, in: 400...1200, step: 10)
                        Text("\(Int(model.overlayWidth))")
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack {
                        Text("Height")
                            .frame(width: 72, alignment: .leading)
                        Slider(value: $model.overlayHeight, in: 120...300, step: 2)
                        Text("\(Int(model.overlayHeight))")
                            .frame(width: 44, alignment: .trailing)
                    }

                    HStack {
                        Text("Countdown")
                            .frame(width: 72, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { Double(model.countdownSeconds) },
                                set: { model.countdownSeconds = Int($0.rounded()) }
                            ),
                            in: 0...10,
                            step: 1
                        )
                        Text("\(model.countdownSeconds)s")
                            .frame(width: 44, alignment: .trailing)
                    }

                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 560)
        .alert("File Operation Failed", isPresented: Binding(
            get: { fileErrorMessage != nil },
            set: { _ in fileErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fileErrorMessage ?? "This file operation could not be completed.")
        }
    }

    @MainActor
    private func importScriptAsync() async {
        let url = await FilePanelCoordinator.presentImportPanel(from: NSApp.keyWindow)
        guard let url else { return }
        do {
            model.script = try await ScriptFileIO.importText(from: url)
        } catch {
            fileErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func exportScriptAsync() async {
        let url = await FilePanelCoordinator.presentExportPanel(from: NSApp.keyWindow)
        guard let url else { return }
        do {
            try await ScriptFileIO.exportText(model.script, to: url)
        } catch {
            fileErrorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
