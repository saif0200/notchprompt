//
//  ContentView.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var model = PrompterModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notchprompt")
                .font(.system(size: 18, weight: .semibold))

            Toggle("Click-through overlay (no cursor blocking)", isOn: $model.isClickThrough)

            HStack(spacing: 12) {
                Button(model.isRunning ? "Pause" : "Start") {
                    model.isRunning.toggle()
                }

                Button("Reset") {
                    model.resetScroll()
                }
            }

            GroupBox("Script") {
                TextEditor(text: $model.script)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 240)
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


                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 560)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
