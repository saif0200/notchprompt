//
//  ScriptTrackerSelfTests.swift
//  notchprompt
//

import Foundation

enum ScriptTrackerSelfTests {
    static func run() {
        let script = "Welcome to the show. Today we are going to talk about gardening, and the best tools for it. Don't forget the spade."

        var t = ScriptTracker(script: script)
        assert(t.update(recognized: "welcome") == 0, "a long word alone is enough to start")
        assert(t.update(recognized: "welcome to") == 1)
        assert(t.update(recognized: "welcome to the") == 2)
        assert(t.update(recognized: "welcome to the show") == 3)
        assert(t.update(recognized: "welcome to the show") == nil, "repeated partial is not a move")

        // Ad-lib that isn't in the script leaves the position alone.
        assert(t.update(recognized: "welcome to the show and um you know") == nil)
        assert(t.currentWordIndex == 3)

        // Skipping "we are going to" jumps straight to "talk about".
        assert(t.update(recognized: "welcome to the show today talk about") == 10, "skip ahead")

        // Case and punctuation differences are ignored, apostrophes survive.
        var p = ScriptTracker(script: script)
        assert(p.update(recognized: "WELCOME, to THE show!") == 3)
        var q = ScriptTracker(script: script)
        assert(q.update(recognized: "Don\u{2019}t forget") == 19)

        // A phrase repeated beyond the forward window must not capture the position.
        let far = "start here " + (1...30).map { "filler\($0)" }.joined(separator: " ") + " alpha beta"
        var f = ScriptTracker(script: far)
        assert(f.update(recognized: "start here") == 1)
        assert(f.update(recognized: "alpha beta") == nil, "far repeat ignored")

        // A repeated common word neither moves backwards nor forwards.
        var c = ScriptTracker(script: "I think the cat saw the dog and the bird")
        assert(c.update(recognized: "I think the cat saw") == 4)
        assert(c.update(recognized: "I think the cat saw the") == 5)
        assert(c.update(recognized: "the") == nil, "lone short word does not move")
        assert(c.currentWordIndex == 5)

        // A real read-through never lowers progress and ends at the end.
        var r = ScriptTracker(script: script)
        let spoken = ScriptTracker.tokenize(script).map(\.text)
        var last = r.progress
        for i in spoken.indices {
            _ = r.update(recognized: spoken[...i].joined(separator: " "))
            assert(r.progress >= last, "progress must be monotonic")
            last = r.progress
        }
        assert(r.currentWordIndex == spoken.count - 1)
        r.reset()
        assert(r.progress == 0 && r.currentWordIndex == -1)

        var lost = ScriptTracker(script: (1...60).map { "w\($0)" }.joined(separator: " ") + " the quick brown fox jumps")
        assert(lost.update(recognized: "w1 w2") == 1)
        assert(lost.update(recognized: "the quick brown fox") == 63, "recovers when far ahead via a unique 4-word run")
        var dup = ScriptTracker(script: "a b c d x a b c d y")
        assert(dup.update(recognized: "zz a b c d") == 3, "first in window")

        var sl = ScriptTracker(script: "a bit short line another short line last paragraph")
        assert(sl.update(recognized: "a bit short") == 2)
        assert(sl.update(recognized: "a bit short lines") == 3, "near-miss plural matches")
        assert(sl.update(recognized: "a bit short lines another") == 4, "single next word steps on")
        assert(sl.update(recognized: "another short lime") == 6, "one-letter misrecognition matches")
        assert(ScriptTracker.sameWord("line", "lines") && !ScriptTracker.sameWord("the", "she") && !ScriptTracker.sameWord("line", "lane s"))
    }
}
