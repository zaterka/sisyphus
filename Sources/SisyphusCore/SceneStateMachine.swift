import Foundation

/// Pure, clock-injected animation state machine for the Sisyphus scene.
///
/// Positions are "progress units": `0` is the bottom of the hill, `1` is the summit. The machine
/// owns no timer and no view state — the caller supplies `dt` (clamped to `0...maxStep`), the
/// current progress `target`, whether a summit run is pending and whether any task is still open.
/// It is a `Sendable` value type, so the `@MainActor` adapter can hold it and step it from a timer.
///
/// Phases and theirs durations (all tunable constants are public):
///
/// | phase | behaviour | duration |
/// |---|---|---|
/// | `pushing` | man eases toward the effective target at ≤ `manSpeed`; rock sits `rockOffset` uphill. With nothing left to push (no open tasks, no pending summit) and the man back at 0 he sits down | open ended |
/// | `atSummit` | holds at the summit, rock at the top | `summitHoldDuration` (0.6 s) |
/// | `rockRolling` | rock accelerates from the summit down to `rockOffset`, then bounces | `rollDuration` + `rockBounceDuration` (1.2 s + 0.3 s) |
/// | `walkingDown` | man walks left to the rock at `walkDownSpeed` | ~2.5 s |
/// | `sitting` | man rests at 0, rock at `rockOffset`; waits for open tasks | until a task exists |
/// | `standingUp` | man rises in place at 0 | `standUpDuration` (0.4 s) |
///
/// A full summit run therefore lasts roughly 4.6 s (0.6 + 1.5 + ~2.5) and cannot be interrupted:
/// in `atSummit`, `rockRolling` and `walkingDown` the `target` argument is ignored.
///
/// `sitting` is reached either at the end of a summit run (with a `.summitFinished` event) or
/// straight from `pushing`, when there is nothing left to push at all: he eases back down to 0 and
/// sits, without any event, because there is no progress to consume.
public struct SceneStateMachine: Equatable, Sendable {

    // MARK: - Nested types

    /// Where the animation currently is.
    public enum Phase: String, Codable, CaseIterable, Sendable {
        case pushing
        case atSummit
        case rockRolling
        case walkingDown
        case sitting
        case standingUp
    }

    /// One-shot notifications handed back from `step(dt:target:summitPending:hasOpenTasks:)`.
    public enum Event: String, Codable, Sendable {
        /// Emitted exactly once per summit run, when the man has walked down and sits.
        /// The adapter answers it with `TaskList.consumeSummit()`.
        case summitFinished
    }

    // MARK: - Tuning constants

    /// Maximum climbing / sliding speed of the man while pushing, in progress units per second.
    public static let manSpeed: Double = 0.25
    /// Speed of the man walking back down to the rock, in progress units per second.
    public static let walkDownSpeed: Double = 0.4
    /// How far uphill the rock sits ahead of the man while pushing, in progress units.
    public static let rockOffset: Double = 0.07
    /// Pause at the summit before the rock starts rolling, in seconds.
    public static let summitHoldDuration: Double = 0.6
    /// Time the rock takes to roll from the summit down to `rockOffset`, in seconds.
    public static let rollDuration: Double = 1.2
    /// Length of the little bounce after the rock hits the bottom, in seconds.
    public static let rockBounceDuration: Double = 0.3
    /// Peak height of the rock's bounce, in logical pixels (the scene is 160×90 logical px).
    public static let rockBounceHeight: Double = 3.0
    /// Time the man takes to get up before pushing again, in seconds.
    public static let standUpDuration: Double = 0.4
    /// `dt` is clamped to `0...maxStep`, so a stalled timer can never teleport a sprite.
    public static let maxStep: Double = 0.1
    /// Position the man starts from when a summit is already pending at launch, so he visibly
    /// climbs the last stretch and replays the summit.
    public static let initialSummitPosition: Double = 0.85

    // MARK: - State

    /// Current phase. Read-only from outside.
    public private(set) var phase: Phase
    /// Man position along the slope, `0...1` (0 = bottom, 1 = summit).
    public private(set) var manPosition: Double
    /// Rock position along the slope, `0...1`.
    public private(set) var rockPosition: Double
    /// `true` while the man faces left (only while walking down).
    public private(set) var facingLeft: Bool
    /// Direction of the man's movement on the last step: `1` up, `-1` down, `0` still.
    public private(set) var moving: Int
    /// Seconds spent in the current phase. A phase change resets it to 0; the leftover slice of
    /// the step that caused the change is discarded.
    public private(set) var phaseTime: Double
    /// Vertical bounce offset of the rock in logical pixels; `0` except during the little bounce
    /// at the bottom of a summit run.
    public private(set) var rockBounce: Double

    private var summitEventEmitted: Bool

    // MARK: - Init

    /// Builds the machine in the state that matches the store at launch.
    ///
    /// - `summitPending` → `pushing` at `initialSummitPosition` (he climbs and replays the summit;
    ///   this also covers quitting in the middle of a summit sequence).
    /// - otherwise, no open tasks → `sitting` at 0 (empty store).
    /// - otherwise → `pushing` with `manPosition = target`.
    public init(target: Double, summitPending: Bool, hasOpenTasks: Bool) {
        if summitPending {
            self.phase = .pushing
            self.manPosition = SceneStateMachine.initialSummitPosition
        } else if !hasOpenTasks {
            self.phase = .sitting
            self.manPosition = 0
        } else {
            self.phase = .pushing
            self.manPosition = SceneStateMachine.clamp01(target)
        }
        self.rockPosition = SceneStateMachine.rockPosition(forMan: self.manPosition)
        self.facingLeft = false
        self.moving = 0
        self.phaseTime = 0
        self.rockBounce = 0
        self.summitEventEmitted = false
    }

    // MARK: - Step

    /// Advances the machine by `dt` seconds (clamped to `0...maxStep`) and returns any events.
    @discardableResult
    public mutating func step(
        dt: Double,
        target: Double,
        summitPending: Bool,
        hasOpenTasks: Bool
    ) -> [Event] {
        let d = SceneStateMachine.clampStep(dt)
        switch phase {
        case .pushing:
            return stepPushing(d: d, target: target, summitPending: summitPending, hasOpenTasks: hasOpenTasks)
        case .atSummit:
            return stepAtSummit(d: d)
        case .rockRolling:
            return stepRockRolling(d: d)
        case .walkingDown:
            return stepWalkingDown(d: d)
        case .sitting:
            return stepSitting(d: d, hasOpenTasks: hasOpenTasks)
        case .standingUp:
            return stepStandingUp(d: d)
        }
    }

    // MARK: - Phase implementations

    private mutating func stepPushing(
        d: Double,
        target: Double,
        summitPending: Bool,
        hasOpenTasks: Bool
    ) -> [Event] {
        // A pending summit overrides the progress target: he always finishes the climb.
        let effectiveTarget = summitPending ? 1.0 : SceneStateMachine.clamp01(target)
        let maxDelta = SceneStateMachine.manSpeed * d
        let delta = min(max(effectiveTarget - manPosition, -maxDelta), maxDelta)
        manPosition = SceneStateMachine.clamp01(manPosition + delta)
        moving = SceneStateMachine.direction(of: delta)
        facingLeft = false
        rockBounce = 0
        rockPosition = SceneStateMachine.rockPosition(forMan: manPosition)

        if summitPending && manPosition >= 1.0 - SceneStateMachine.epsilon {
            manPosition = 1
            rockPosition = 1
            phase = .atSummit
            phaseTime = 0
        } else if !summitPending && !hasOpenTasks && manPosition <= SceneStateMachine.epsilon {
            // Nothing left to push and no summit to play (progress 0): he has slid all the way back
            // down, so he sits next to the rock instead of straining at the bottom. No event: there
            // is no earned progress to consume, and the rock is already at its rest position.
            manPosition = 0
            moving = 0
            facingLeft = false
            rockPosition = SceneStateMachine.rockOffset
            phase = .sitting
            phaseTime = 0
        } else {
            phaseTime += d
        }
        return []
    }

    private mutating func stepAtSummit(d: Double) -> [Event] {
        manPosition = 1
        rockPosition = 1
        rockBounce = 0
        facingLeft = false
        moving = 0
        phaseTime += d
        if phaseTime >= SceneStateMachine.summitHoldDuration {
            // A new summit run starts here, so the one-shot event is armed again.
            summitEventEmitted = false
            phase = .rockRolling
            phaseTime = 0
        }
        return []
    }

    private mutating func stepRockRolling(d: Double) -> [Event] {
        manPosition = 1
        facingLeft = false
        moving = 0
        phaseTime += d

        // Ease-in (accelerating) from the summit down to rockOffset, then a decaying bounce.
        let rollTime = min(phaseTime, SceneStateMachine.rollDuration)
        let rollProgress = rollTime / SceneStateMachine.rollDuration
        rockPosition = SceneStateMachine.rockOffset
            + (1 - SceneStateMachine.rockOffset) * (1 - rollProgress * rollProgress)

        if phaseTime > SceneStateMachine.rollDuration {
            let bounceTime = min(phaseTime - SceneStateMachine.rollDuration, SceneStateMachine.rockBounceDuration)
            let bounceProgress = bounceTime / SceneStateMachine.rockBounceDuration
            rockBounce = SceneStateMachine.rockBounceHeight
                * abs(sin(.pi * 2 * bounceProgress))
                * (1 - bounceProgress)
        } else {
            rockBounce = 0
        }

        if phaseTime >= SceneStateMachine.rollDuration + SceneStateMachine.rockBounceDuration {
            phase = .walkingDown
            phaseTime = 0
            rockPosition = SceneStateMachine.rockOffset
            rockBounce = 0
        }
        return []
    }

    private mutating func stepWalkingDown(d: Double) -> [Event] {
        // The rock rests at the bottom, slightly to the right; the man stops at its left side.
        rockPosition = SceneStateMachine.rockOffset
        rockBounce = 0
        facingLeft = true

        let stop = max(0, rockPosition - SceneStateMachine.rockOffset)
        let maxDelta = SceneStateMachine.walkDownSpeed * d
        let delta = min(max(stop - manPosition, -maxDelta), maxDelta)
        manPosition = SceneStateMachine.clamp01(manPosition + delta)
        moving = SceneStateMachine.direction(of: delta)

        var events: [Event] = []
        if manPosition <= stop + SceneStateMachine.epsilon {
            manPosition = stop
            moving = 0
            facingLeft = false
            phase = .sitting
            phaseTime = 0
            if !summitEventEmitted {
                summitEventEmitted = true
                events.append(.summitFinished)
            }
        } else {
            phaseTime += d
        }
        return events
    }

    private mutating func stepSitting(d: Double, hasOpenTasks: Bool) -> [Event] {
        manPosition = 0
        rockPosition = SceneStateMachine.rockOffset
        rockBounce = 0
        facingLeft = false
        moving = 0
        phaseTime += d
        if hasOpenTasks {
            phase = .standingUp
            phaseTime = 0
        }
        return []
    }

    private mutating func stepStandingUp(d: Double) -> [Event] {
        manPosition = 0
        rockPosition = SceneStateMachine.rockOffset
        rockBounce = 0
        facingLeft = false
        moving = 0
        phaseTime += d
        if phaseTime >= SceneStateMachine.standUpDuration {
            // He is already at the bottom next to the rock, so nothing jumps when pushing resumes.
            phase = .pushing
            phaseTime = 0
        }
        return []
    }

    // MARK: - Helpers

    private static let epsilon = 1e-9

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func clampStep(_ dt: Double) -> Double {
        guard dt.isFinite else { return 0 }
        return min(max(dt, 0), maxStep)
    }

    private static func rockPosition(forMan manPosition: Double) -> Double {
        min(1, manPosition + rockOffset)
    }

    private static func direction(of delta: Double) -> Int {
        if delta > epsilon { return 1 }
        if delta < -epsilon { return -1 }
        return 0
    }
}
