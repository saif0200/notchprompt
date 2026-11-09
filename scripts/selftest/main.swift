// Logic tests for the parts of Notchprompt with no UI. No XCTest target: run scripts/test.sh.
import CoreGraphics
import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if !condition() { failures += 1; print("FAIL [line \(line)]: \(message)") }
}
func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.51) -> Bool { abs(a - b) <= tolerance }

// MARK: Island geometry, using values measured on a Mac17,10 (16" OLED) at the default scale

let oled = CGRect(x: 0, y: 0, width: 1736, height: 1133)
let oledCutout = DisplayTopEdge.cutout(
    screenFrame: oled,
    auxiliaryTopLeft: CGRect(x: 0, y: 1093, width: 838.5, height: 40),
    auxiliaryTopRight: CGRect(x: 897.5, y: 1093, width: 838.5, height: 40)
)
check(oledCutout == CGRect(x: 838.5, y: 1093, width: 59, height: 40), "OLED cutout should be 59x40 at centre")

let edge = DisplayTopEdge(screenFrame: oled, cutout: oledCutout, menuBarHeight: 45, backingScale: 2)
var layout = IslandLayout(edge: edge, requestedAttachment: .floating, requestedExpandedSize: CGSize(width: 560, height: 260))
check(layout.isDynamicIsland, "59pt cutout is a Dynamic Island")
check(layout.attachment == .floating, "Dynamic Island may float")
for form in [IslandForm.idle, .compact, .expanded] {
    let frame = layout.panelFrame(for: form)
    check(near(frame.midX, 868), "\(form) must be centred on the camera, got \(frame.midX)")
    check(frame.maxY == oled.maxY, "\(form) must touch the top of the screen")
    check(frame.width >= 59, "\(form) must cover the camera")
}
check(layout.size(for: .idle).width < layout.size(for: .compact).width, "idle is narrower than compact")
check(layout.panelFrame(for: .compact).minY == oledCutout!.minY, "floating island ends level with the camera's bottom edge")
var nudged = layout
nudged.verticalNudge = 2
check(nudged.panelFrame(for: .compact).minY == oledCutout!.minY - 2, "nudge moves the island down")
check(nudged.panelFrame(for: .compact).maxY == oled.maxY, "the panel still reaches the top of the screen")
nudged.verticalNudge = -9
check(nudged.topInset == 0, "nudge can't push the island off the top")
check(layout.expandedHeaderHeight >= layout.bandHeight - layout.topInset, "script starts below the camera band")
check(layout.expandedHeaderSlotWidth() > 100, "header slots must have room at the default width")

let classicNotch = DisplayTopEdge(
    screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    cutout: DisplayTopEdge.cutout(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 664, height: 32),
        auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32)
    ),
    menuBarHeight: 37,
    backingScale: 2
)
let notchLayout = IslandLayout(edge: classicNotch, requestedAttachment: .floating, requestedExpandedSize: CGSize(width: 560, height: 260))
check(!notchLayout.isDynamicIsland, "185pt cutout is a notch")
check(notchLayout.attachment == .attached, "a notch reaches the bezel so the island must attach")
check(notchLayout.corners(for: .expanded).top == 0, "attached island has square top")

let external = DisplayTopEdge(screenFrame: CGRect(x: 1736, y: 200, width: 2560, height: 1440), cutout: nil, menuBarHeight: 0, backingScale: 2)
let externalLayout = IslandLayout(edge: external, requestedAttachment: .floating, requestedExpandedSize: CGSize(width: 9000, height: 9000))
check(DisplayTopEdge.cutout(screenFrame: external.screenFrame, auxiliaryTopLeft: nil, auxiliaryTopRight: nil) == nil, "no aux areas, no cutout")
check(externalLayout.panelFrame(for: .expanded).maxY == external.screenFrame.maxY, "secondary display tops are respected")
check(near(externalLayout.panelFrame(for: .expanded).midX, external.screenFrame.midX), "falls back to screen centre")
check(externalLayout.expandedSize.width <= IslandLayout.maximumExpandedSize.width, "clamped to max width")
check(externalLayout.bandHeight >= 32, "band height falls back when the menu bar is hidden")

layout.requestedExpandedSize = CGSize(width: 10, height: 10)
check(layout.expandedSize == IslandLayout.minimumExpandedSize, "clamped to min size")

// MARK: Scroll engine

func run(_ engine: inout ScrollEngine, seconds: Double, fps: Double = 120) -> Bool {
    var reached = false
    for _ in 0..<Int(seconds * fps) { if engine.advance(by: CGFloat(1 / fps)).reachedEnd { reached = true } }
    return reached
}

check(ScrollEngine.speed(wordsPerMinute: 150, wordCount: 300, travel: 3000) == 25, "300 words at 150wpm over 3000pt takes 120s = 25pt/s")
check(ScrollEngine.speed(wordsPerMinute: 150, wordCount: 0, travel: 3000) == 0, "no words, no speed")

var engine = ScrollEngine()
engine.setLength(travel: 1000, cycle: 1100)
engine.speed = 100
engine.isRunning = true
_ = run(&engine, seconds: 2)
check(engine.position > 170 && engine.position < 200, "ramps up to pace, got \(engine.position)")
check(run(&engine, seconds: 10), "reports the end")
check(engine.position == 1000 && engine.isAtEnd, "stops exactly at the end")
check(engine.needsFrames == false || engine.isRunning, "at end only runs while still flagged running")
engine.isRunning = false
_ = run(&engine, seconds: 1)
check(!engine.needsFrames, "idle engine needs no frames")

engine = ScrollEngine()
engine.setLength(travel: 1000, cycle: 1100)
engine.speed = 100
engine.isRunning = true
var count = 0
for _ in 0..<(120 * 20) { if engine.advance(by: 1.0 / 120).reachedEnd { count += 1 } }
check(count == 1, "end fires once, fired \(count)")

engine = ScrollEngine()
engine.setLength(travel: 1000, cycle: 1100)
engine.mode = .loop
engine.speed = 500
engine.isRunning = true
check(!run(&engine, seconds: 5), "loop mode never ends")
check(engine.position >= 0 && engine.position < 1100, "wraps inside the cycle")
engine.nudge(by: -5000)
check(engine.position >= 0 && engine.position < 1100, "backwards wraps too")

engine = ScrollEngine()
engine.setLength(travel: 1000, cycle: 1100)
engine.setPosition(500)
engine.jump(by: -400)
_ = run(&engine, seconds: 2)
check(near(engine.position, 100), "jump settles on target, got \(engine.position)")
check(!engine.needsFrames, "jump finishes")
engine.jump(by: -400)
_ = run(&engine, seconds: 2)
check(engine.position == 0, "jump clamps at the top")
engine.nudge(by: 5000)
check(engine.position == 1000, "nudge clamps at the end")
engine.nudge(by: -10)
check(!engine.isAtEnd, "leaving the end clears the flag")

engine = ScrollEngine()
engine.setLength(travel: 1000, cycle: 1100)
engine.speed = 100
engine.speedScale = 0
engine.isRunning = true
_ = run(&engine, seconds: 3)
check(engine.position == 0, "voice scroll holds still in silence")

engine = ScrollEngine()
engine.setLength(travel: 1000, cycle: 1100)
engine.speed = 100
engine.isRunning = true
engine.followTarget = 300
_ = run(&engine, seconds: 3)
check(near(engine.position, 300, 1), "follows the spoken word, got \(engine.position)")
engine.followTarget = 1000
check(!run(&engine, seconds: 3), "following never trips the end stop")

engine = ScrollEngine()
engine.setLength(travel: 100, cycle: 200)
engine.setPosition(90)
engine.setLength(travel: 50, cycle: 120)
check(engine.position == 50, "shrinking the script keeps the position valid")
engine.advance(by: 500)
check(engine.position == 50, "a long gap can't leap")

// MARK: Script document

let doc = ScriptDocument(script: "Hello, world\r\n---\r\nDon’t  stop.")
check(doc.wordCount == 4, "rule isn't a word, got \(doc.wordCount)")
check(doc.sectionRules.count == 1, "one rule")
check(!doc.displayText.contains("---"), "rule is replaced")
check(!doc.displayText.contains("\r"), "line endings normalised")
for word in doc.words {
    check((doc.displayText as NSString).substring(with: word.range) == word.text, "\(word.text) range must point at itself")
}
check(doc.words[2].normalized == "dont", "curly apostrophe normalised, got \(doc.words[2].normalized)")
check(ScriptDocument.normalize("\"Hello,\"") == "hello", "trims punctuation")
check(ScriptDocument(script: "  \n\n ").isEmpty, "whitespace is empty")
let emoji = ScriptDocument(script: "🎬 Action now")
check(emoji.words.last?.text == "now", "UTF-16 ranges survive emoji")

// MARK: Alignment

func uniqueDocForTail() -> ScriptDocument {
    ScriptDocument(script: (0..<300).map { "term\($0 * $0 % 1013)q" }.joined(separator: " "))
}

let script = (0..<400).map { i -> String in
    let bank = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "while", "morning", "sunshine", "drifts", "across", "quiet", "valley", "and", "every", "listener", "waits", "patiently"]
    return bank[(i * 7 + i / 3) % bank.count]
}.joined(separator: " ")
let scriptDoc = ScriptDocument(script: script)
let tokens = scriptDoc.words.map(\.text)

// Clean read: a sliding tail of the last 8 words, one pass per 3 words.
var aligner = ScriptAlignmentEngine()
aligner.setWords(scriptDoc.words)
var i = 2
var worst = 0
while i < tokens.count {
    aligner.process(heard: Array(tokens[max(0, i - 7)...i]))
    worst = max(worst, abs(aligner.currentWordIndex - i))
    i += 3
}
check(worst <= 2, "clean read tracks to within 2 words, worst \(worst)")

// Messy read: every 9th word misheard, every 13th dropped.
aligner = ScriptAlignmentEngine()
aligner.setWords(scriptDoc.words)
var heard: [String] = []
worst = 0
for (index, word) in tokens.enumerated() {
    if index % 13 == 12 { continue }
    heard.append(index % 9 == 8 ? "zzzzq" : word)
    if index % 3 == 2 {
        aligner.process(heard: Array(heard.suffix(8)))
        if index > 16 { worst = max(worst, abs(aligner.currentWordIndex - index)) }
    }
}
check(worst <= 6, "messy read tracks to within 6 words, worst \(worst)")

// Whisper invents the last words of a clipped sentence. That mustn't stall tracking.
aligner = ScriptAlignmentEngine()
aligner.setWords(uniqueDocForTail().words)
let tailTokens = uniqueDocForTail().words.map(\.text)
var tailWorst = 0
for end in stride(from: 11, to: 200, by: 4) {
    aligner.process(heard: Array(tailTokens[max(0, end - 11)...end]) + ["invented", "nonsense"])
    tailWorst = max(tailWorst, abs(aligner.currentWordIndex - end))
}
check(tailWorst <= 2, "tracks through hallucinated tails, worst \(tailWorst)")

// A single common word must not teleport the cursor.
aligner = ScriptAlignmentEngine()
aligner.setWords(scriptDoc.words)
aligner.process(heard: ["waits"])
check(aligner.currentWordIndex < 4, "one distant word doesn't jump, got \(aligner.currentWordIndex)")

// Off-script chatter eventually reports lost, without moving.
aligner = ScriptAlignmentEngine()
aligner.setWords(scriptDoc.words)
aligner.process(heard: Array(tokens[0...7]))
let held = aligner.currentWordIndex
for _ in 0..<6 { aligner.process(heard: ["ummm", "xylophone", "zebra", "qqq", "ppp", "yyy", "www", "kkk"]) }
check(aligner.confidence == .lost, "off-script reports lost")
check(aligner.currentWordIndex == held, "off-script doesn't move")
// ...and it recovers when the speaker picks up later on. Needs text that doesn't
// repeat, or the matching phrase really is right where the cursor already sits.
let uniqueDoc = ScriptDocument(script: (0..<300).map { "word\($0 * $0 % 1009)x" }.joined(separator: " "))
let uniqueTokens = uniqueDoc.words.map(\.text)
aligner = ScriptAlignmentEngine()
aligner.setWords(uniqueDoc.words)
aligner.process(heard: Array(uniqueTokens[0...7]))
for _ in 0..<6 { aligner.process(heard: ["ummm", "xylophone", "zebra", "qqq", "ppp", "yyy", "www", "kkk"]) }
aligner.process(heard: Array(uniqueTokens[60...67]))
check(aligner.currentWordIndex == 67, "recovers from lost, got \(aligner.currentWordIndex)")

// MARK: Screen selection

ScreenSelectionSelfTests.run()

// MARK: File import helpers

check(ScriptTextDecoding.looksLikeText("Hello there\nline two".data(using: .utf8)!), "plain text passes")
check(!ScriptTextDecoding.looksLikeText(Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00, 0x08, 0x00, 0x00, 0x08])), "binary is rejected")
check(ScriptTextDecoding.decode(Data([0x50, 0x4B, 0x00, 0x04, 0xFF, 0x00])) == nil, "binary is not decoded")
check(ScriptTextDecoding.decode("Caf\u{e9}".data(using: .isoLatin1)!) == "Café", "Latin-1 still decodes")
check(ScriptTextDecoding.decode("Héllo".data(using: .utf8)!) == "Héllo", "UTF-8 preferred")
let sorted = ScriptTextDecoding.sortedByNumber(["notesSlide10.xml", "notesSlide2.xml", "notesSlide1.xml"])
check(sorted == ["notesSlide1.xml", "notesSlide2.xml", "notesSlide10.xml"], "slides sort numerically, got \(sorted)")
let notes = ScriptTextDecoding.pptxNoteText(xml: Data("<p:notes xmlns:p='p' xmlns:a='a'><a:p><a:r><a:t>Q&amp;A: it&apos;s</a:t></a:r><a:r><a:t> here</a:t></a:r></a:p><a:p><a:r><a:t>7</a:t></a:r></a:p><a:p><a:r><a:t>Second para</a:t></a:r></a:p></p:notes>".utf8))
check(notes == "Q&A: it's here\nSecond para", "PPTX: entities, runs, paragraphs, slide numbers. Got: \(notes)")

if failures == 0 { print("All checks passed") } else { print("\(failures) check(s) failed"); exit(1) }
