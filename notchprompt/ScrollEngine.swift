//
//  ScrollEngine.swift
//  notchprompt
//
//  The scroll physics, with no UI in it. `position` is how far the script has
//  moved: 0 puts the first line on the reading line, `travel` puts the last one
//  there.
//

import CoreGraphics

struct ScrollEngine {
    enum Mode: Equatable {
        case stopAtEnd
        case loop
    }

    struct StepResult: Equatable {
        var reachedEnd = false
    }

    private static let followRate: CGFloat = 10
    private static let jumpRate: CGFloat = 12
    private static let easeRate: CGFloat = 8
    private static let settleDistance: CGFloat = 0.25

    private(set) var position: CGFloat = 0
    private(set) var travel: CGFloat = 0
    private(set) var cycle: CGFloat = 0
    private(set) var isAtEnd = false

    var mode: Mode = .stopAtEnd
    var isRunning = false
    /// Points per second at full pace.
    var speed: CGFloat = 0
    /// 0...1 multiplier used by voice-activated scrolling.
    var speedScale: CGFloat = 1
    /// When set, the script chases this position instead of moving at `speed`.
    var followTarget: CGFloat?

    private var pace: CGFloat = 0
    private var pendingJump: CGFloat = 0

    /// Pace that reads `wordCount` words at `wordsPerMinute` over the full travel.
    static func speed(wordsPerMinute: Double, wordCount: Int, travel: CGFloat) -> CGFloat {
        guard wordCount > 0, travel > 0, wordsPerMinute > 0 else { return 0 }
        return travel * CGFloat(wordsPerMinute) / (60 * CGFloat(wordCount))
    }

    var progress: Double {
        guard travel > 0 else { return 0 }
        return Double(min(max(position / travel, 0), 1))
    }

    /// True while another frame would still change something.
    var needsFrames: Bool {
        if isRunning, !isAtEnd || followTarget != nil { return true }
        if pace > 0 || pendingJump != 0 { return true }
        return false
    }

    mutating func setLength(travel: CGFloat, cycle: CGFloat) {
        self.travel = max(travel, 0)
        self.cycle = max(cycle, 0)
        applyPositionLimits()
    }

    mutating func reset() {
        position = 0
        pace = 0
        pendingJump = 0
        followTarget = nil
        isAtEnd = false
    }

    mutating func setPosition(_ newPosition: CGFloat) {
        position = newPosition
        applyPositionLimits()
    }

    /// Immediate movement, for the trackpad.
    mutating func nudge(by delta: CGFloat) {
        position += delta
        applyPositionLimits()
    }

    /// Eased movement, for "jump back".
    mutating func jump(by delta: CGFloat) {
        pendingJump += delta
        isAtEnd = false
    }

    @discardableResult
    mutating func advance(by rawDelta: CGFloat) -> StepResult {
        // A long gap means the Mac slept or the window was hidden. Don't leap.
        let dt = min(max(rawDelta, 0), 0.1)
        var movement: CGFloat = 0

        let following = isRunning && followTarget != nil
        let desiredPace = (isRunning && !following && !isAtEnd) ? min(max(speedScale, 0), 1) : 0
        pace += (desiredPace - pace) * (1 - exp(-Self.easeRate * dt))
        if desiredPace == 0, pace < 0.002 { pace = 0 }
        movement += speed * pace * dt

        if pendingJump != 0 {
            var step = pendingJump * (1 - exp(-Self.jumpRate * dt))
            if abs(pendingJump - step) < Self.settleDistance { step = pendingJump }
            movement += step
            pendingJump -= step
        }

        if following, let followTarget {
            let difference = followTarget - position
            if abs(difference) > Self.settleDistance {
                movement += difference * (1 - exp(-Self.followRate * dt))
            }
        }

        return apply(movement: movement)
    }

    private mutating func apply(movement: CGFloat) -> StepResult {
        var result = StepResult()
        let isPaced = isRunning && followTarget == nil
        position += movement

        switch mode {
        case .loop where cycle > 0:
            wrapIntoCycle()
        default:
            if position <= 0 { position = 0 }
            if position >= travel {
                position = travel
                if !isAtEnd, isPaced, movement >= 0 {
                    isAtEnd = true
                    pace = 0
                    pendingJump = 0
                    result.reachedEnd = true
                }
            } else {
                isAtEnd = false
            }
        }
        return result
    }

    private mutating func applyPositionLimits() {
        switch mode {
        case .loop where cycle > 0:
            wrapIntoCycle()
        default:
            position = min(max(position, 0), travel)
            if position < travel { isAtEnd = false }
        }
    }

    private mutating func wrapIntoCycle() {
        position = position.truncatingRemainder(dividingBy: cycle)
        if position < 0 { position += cycle }
        isAtEnd = false
    }
}
