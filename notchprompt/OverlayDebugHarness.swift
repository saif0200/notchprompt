//
//  OverlayDebugHarness.swift
//  notchprompt
//
//  Debug builds only. With NOTCHPROMPT_SNAPSHOT=<folder> set, walks the island
//  through its forms, writes each to a PNG and quits. The PNGs come from the
//  window's own layers, so this needs no Screen Recording permission.
//

#if DEBUG
import AppKit

@MainActor
enum OverlayDebugHarness {
    static func runIfRequested(model: PrompterModel, controller: OverlayWindowController) -> Bool {
        guard let folder = ProcessInfo.processInfo.environment["NOTCHPROMPT_SNAPSHOT"] else { return false }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let script = ProcessInfo.processInfo.environment["NOTCHPROMPT_SCRIPT"]
        if let script {
            model.loadScript(script)
        }
        model.countdownBehavior = .never

        Task { @MainActor in
            @MainActor func capture(_ name: String) async {
                try? await Task.sleep(for: .milliseconds(900))
                write(controller.debugWindow, to: directory.appendingPathComponent("\(name).png"))
            }
            @MainActor func wait(_ seconds: Double) async {
                try? await Task.sleep(for: .seconds(seconds))
            }
            func expect(_ condition: Bool, _ label: String) {
                print("[Harness] \(condition ? "ok  " : "FAIL") \(label)")
            }

            let window = controller.debugWindow
            await capture("1-idle")

            // A real click on the idle island, through the window, not the model.
            click(window, at: CGPoint(x: window.frame.width / 2, y: window.frame.height - 18))
            await wait(0.8)
            expect(model.islandForm == .expanded, "clicking the idle island expands it")
            expect(window.frame.width == 560, "panel grew to the expanded width, got \(window.frame.width)")
            await capture("3-expanded-ready")

            hover(window, entered: true)
            await capture("6-expanded-controls")
            let playPoint = CGPoint(x: window.frame.width / 2 - 128, y: 28)
            click(window, at: playPoint)
            await wait(0.3)
            expect(model.isRunning, "clicking play starts the script")

            await wait(2.5)
            let usageBefore = cpuSeconds()
            let before = model.scroller.engine.position
            await wait(3)
            let after = model.scroller.engine.position
            let cpu = (cpuSeconds() - usageBefore) / 3 * 100
            expect(after > before, "text moves while running")
            print("[Harness] running: \(String(format: "%.1f", (after - before) / 3)) pt/s of \(String(format: "%.1f", model.scroller.engine.speed)), CPU \(String(format: "%.1f", cpu))%")
            await capture("4-expanded-running")

            // Fingers up on a trackpad (natural): content up, position forward.
            let target = firstView(of: PrompterTextNSView.self, in: window.contentView!)!
            model.resetScroll()
            await wait(0.6)
            let beforeWheel = model.scroller.engine.position
            target.scrollWheel(with: scrollEvent(deltaY: -40))
            await wait(0.1)
            expect(model.scroller.engine.position > beforeWheel, "scrolling up moves the script forward")
            expect(!model.isRunning, "paused stays paused after scrolling")

            model.start()
            await wait(0.5)
            target.scrollWheel(with: scrollEvent(deltaY: 40))
            await wait(0.1)
            expect(model.isRunning, "scrolling mid-read doesn't stop the read")
            model.stop()

            let middle = window.contentView!.convert(CGPoint(x: 280, y: 120), to: nil)
            let hit = window.contentView!.hitTest(middle)
            expect(hit is PrompterTextNSView, "the trackpad reaches the script, hit \(hit.map { String(describing: Swift.type(of: $0)) } ?? "nil")")

            let idleBefore = cpuSeconds()
            await wait(3)
            print("[Harness] paused CPU \(String(format: "%.2f", (cpuSeconds() - idleBefore) / 3 * 100))%")

            let widthBefore = model.fontSize
            let wpmDuration = model.estimatedReadDuration
            model.fontSize = widthBefore + 10
            await wait(0.4)
            expect(model.estimatedReadDuration == wpmDuration, "font size doesn't change read time")
            model.fontSize = widthBefore

            hover(window, entered: false)
            model.collapseIsland()
            await capture("5-compact-session")
            expect(window.frame.width < 560, "panel shrank after collapse, got \(window.frame.width)")

            // Long-script stress: about 25,000 words.
            let paragraph = String(repeating: "The quick brown fox jumps over the lazy dog while the morning sun climbs. ", count: 40)
            let huge = Array(repeating: paragraph, count: 45).joined(separator: "\n\n")
            let loadStart = Date()
            model.loadScript(huge)
            model.expandIsland()
            await wait(1)
            print("[Harness] 25k-word script: \(model.wordCount) words, travel \(Int(model.scroller.engine.travel)) pt, load took under \(String(format: "%.2f", Date().timeIntervalSince(loadStart) - 1))s past the 1s wait")
            model.fontSize = 18
            await wait(0.3)
            model.scroller.nudge(by: model.scroller.engine.travel - 200)
            model.start()
            await wait(0.4)
            let hugeBefore = cpuSeconds()
            await wait(3)
            print("[Harness] 25k-word CPU \(String(format: "%.1f", (cpuSeconds() - hugeBefore) / 3 * 100))%, position \(Int(model.scroller.engine.position))/\(Int(model.scroller.engine.travel))")
            await capture("7-long-script-end")
            model.stop()

            // Reach the end through the real pace.
            model.wordsPerMinute = 400
            model.loadScript("Short and sweet.\nTwo lines only here.")
            model.countdownBehavior = .never
            model.start()
            await wait(4)
            expect(model.didReachEnd, "a short script reaches the end")
            expect(!model.isRunning, "and stops there")
            let endTarget = firstView(of: PrompterTextNSView.self, in: window.contentView!)!
            endTarget.scrollWheel(with: scrollEvent(deltaY: -40))
            await wait(0.1)
            expect(model.didReachEnd, "scrolling at the very end stays finished")
            model.start()
            await wait(0.2)
            expect(model.isRunning && model.progress < 0.5, "Start after the end restarts from the top")
            model.stop()
            await capture("8-finished")

            for (name, selector) in [
                ("9-settings", #selector(AppDelegate.openSettingsFromOverlay)),
                ("10-editor", #selector(AppDelegate.openScriptEditorFromOverlay)),
                ("11-library", #selector(AppDelegate.openScriptLibraryFromEditor))
            ] {
                model.loadScript(script ?? "Sample script")
                NSApp.sendAction(selector, to: nil, from: nil)
                await wait(1.2)
                if let front = NSApp.windows.first(where: { $0.isVisible && $0 !== window && $0.title != "" && $0.isKeyWindow }) ?? NSApp.windows.first(where: { $0.isVisible && $0 !== window && $0.frame.width > 300 }) {
                    write(front, to: directory.appendingPathComponent("\(name).png"))
                    front.close()
                }
            }

            if let path = ProcessInfo.processInfo.environment["NOTCHPROMPT_SPEECH_AUDIO"],
               let text = ProcessInfo.processInfo.environment["NOTCHPROMPT_SPEECH_TEXT"],
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                let samples = data.dropFirst(4092).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                for choice in SpeechEngineChoice.available {
                    await model.debugRunSpeechCheck(choice: choice, samples: samples, script: text, sampleRate: 16_000)
                }
            }

            NSApp.terminate(nil)
        }
        return true
    }

    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private static func firstView<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = firstView(of: type, in: subview) { return match }
        }
        return nil
    }

    /// Enters the tracking view the same way AppKit does.
    private static func hover(_ window: NSWindow, entered: Bool) {
        guard let content = window.contentView,
              let tracker = firstView(of: NSView.self, in: content, where: { String(describing: Swift.type(of: $0)).contains("TrackerView") })
        else { return }
        let event = NSEvent.mouseEvent(
            with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        )!
        if entered { tracker.mouseEntered(with: event) } else { tracker.mouseExited(with: event) }
    }

    private static func firstView(of type: NSView.Type, in view: NSView, where predicate: (NSView) -> Bool) -> NSView? {
        if predicate(view) { return view }
        for subview in view.subviews {
            if let match = firstView(of: type, in: subview, where: predicate) { return match }
        }
        return nil
    }

    private static func click(_ window: NSWindow, at point: CGPoint) {
        for (type, pressure) in [(NSEvent.EventType.leftMouseDown, Float(1)), (.leftMouseUp, Float(0))] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: pressure
            )!
            NSApp.sendEvent(event)
        }
    }

    private static func scrollEvent(deltaY: Int32) -> NSEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0)!
        return NSEvent(cgEvent: cg)!
    }

    private static func write(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView, let layer = view.layer else { return }
        let scale = window.backingScaleFactor
        let width = Int(view.bounds.width * scale)
        let height = Int(view.bounds.height * scale)
        // A neutral backdrop, so the transparent parts of the panel read as such.
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.setFillColor(NSColor(srgbRed: 0.34, green: 0.42, blue: 0.56, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        (layer.presentation() ?? layer).render(in: context)
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("[Harness] wrote \(url.lastPathComponent) \(window.frame)")
    }
}
#endif
