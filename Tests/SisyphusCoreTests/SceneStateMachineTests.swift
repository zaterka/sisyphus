import Foundation
import Testing

import SisyphusCore

private typealias Machine = SceneStateMachine
private typealias Phase = SceneStateMachine.Phase

/// Steps the machine until `condition` holds and returns the number of steps it took, or `nil`
/// when the machine did not reach that state within `limit` steps.
@discardableResult
private func run(
    _ machine: inout Machine,
    limit: Int = 800,
    dt: Double = 0.05,
    target: Double = 1,
    summitPending: Bool,
    hasOpenTasks: Bool,
    onStep: ((Machine, [Machine.Event]) -> Void)? = nil,
    until condition: (Machine) -> Bool
) -> Int? {
    for step in 1...limit {
        let events = machine.step(
            dt: dt,
            target: target,
            summitPending: summitPending,
            hasOpenTasks: hasOpenTasks
        )
        onStep?(machine, events)
        if condition(machine) { return step }
    }
    return nil
}

@Suite("SceneStateMachine initial state")
struct SceneInitTests {
    @Test("An empty store starts sitting at the bottom")
    func emptyStoreSits() {
        let machine = Machine(target: 0.4, summitPending: false, hasOpenTasks: false)
        #expect(machine.phase == .sitting)
        #expect(machine.manPosition == 0)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)
        #expect(machine.moving == 0)
        #expect(!machine.facingLeft)
        #expect(machine.phaseTime == 0)
        #expect(machine.rockBounce == 0)
    }

    @Test("A pending summit starts climbing near the top")
    func pendingSummitStartsHigh() {
        let machine = Machine(target: 0.0, summitPending: true, hasOpenTasks: false)
        #expect(machine.phase == .pushing)
        #expect(abs(machine.manPosition - Machine.initialSummitPosition) < 1e-12)
        #expect(abs(machine.rockPosition - (Machine.initialSummitPosition + Machine.rockOffset)) < 1e-12)
    }

    @Test("Otherwise the machine starts at the target")
    func startsAtTarget() {
        let machine = Machine(target: 0.3, summitPending: false, hasOpenTasks: true)
        #expect(machine.phase == .pushing)
        #expect(abs(machine.manPosition - 0.3) < 1e-12)
        #expect(abs(machine.rockPosition - 0.37) < 1e-12)
    }

    @Test("The initial target is clamped to 0...1")
    func clampsTarget() {
        #expect(Machine(target: 5, summitPending: false, hasOpenTasks: true).manPosition == 1)
        #expect(Machine(target: -5, summitPending: false, hasOpenTasks: true).manPosition == 0)
        #expect(Machine(target: .nan, summitPending: false, hasOpenTasks: true).manPosition == 0)
    }
}

@Suite("SceneStateMachine pushing")
struct PushingTests {
    @Test("Climbs toward the target at the capped speed, never overshooting")
    func cappedClimb() {
        var machine = Machine(target: 0, summitPending: false, hasOpenTasks: true)

        for _ in 0..<5 {
            machine.step(dt: 0.1, target: 1, summitPending: false, hasOpenTasks: true)
        }
        #expect(abs(machine.manPosition - 5 * Machine.manSpeed * 0.1) < 1e-9)
        #expect(machine.moving == 1)
        #expect(!machine.facingLeft)
        #expect(machine.phase == .pushing)

        for _ in 0..<100 {
            machine.step(dt: 0.1, target: 1, summitPending: false, hasOpenTasks: true)
        }
        #expect(machine.manPosition == 1)
        #expect(machine.moving == 0)
        // Without a pending summit he holds at the top instead of triggering the roll.
        #expect(machine.phase == .pushing)
        #expect(machine.rockPosition == 1)
    }

    @Test("Slides back at the capped speed when the target drops")
    func cappedSlide() {
        var machine = Machine(target: 0.5, summitPending: false, hasOpenTasks: true)
        machine.step(dt: 0.1, target: 0, summitPending: false, hasOpenTasks: true)
        #expect(abs(machine.manPosition - (0.5 - Machine.manSpeed * 0.1)) < 1e-9)
        #expect(machine.moving == -1)
        #expect(!machine.facingLeft)
    }

    @Test("Standing still reports moving 0")
    func still() {
        var machine = Machine(target: 0.5, summitPending: false, hasOpenTasks: true)
        machine.step(dt: 0.1, target: 0.5, summitPending: false, hasOpenTasks: true)
        #expect(machine.moving == 0)
        #expect(machine.manPosition == 0.5)
    }

    @Test("A pending summit overrides the target")
    func pendingSummitOverridesTarget() {
        var machine = Machine(target: 0.2, summitPending: true, hasOpenTasks: true)
        machine.step(dt: 0.1, target: 0, summitPending: true, hasOpenTasks: true)
        #expect(machine.moving == 1)
        #expect(machine.manPosition > Machine.initialSummitPosition)
    }

    @Test("The rock trails the man by rockOffset and never passes the summit")
    func rockOffset() {
        var machine = Machine(target: 0, summitPending: false, hasOpenTasks: true)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)

        machine.step(dt: 0.1, target: 0.6, summitPending: false, hasOpenTasks: true)
        #expect(abs(machine.rockPosition - (machine.manPosition + Machine.rockOffset)) < 1e-12)

        var high = Machine(target: 0.99, summitPending: false, hasOpenTasks: true)
        high.step(dt: 0.1, target: 1, summitPending: false, hasOpenTasks: true)
        #expect(high.rockPosition == 1)
    }

    @Test("dt is clamped to maxStep")
    func clampsLargeDt() {
        var machine = Machine(target: 0, summitPending: false, hasOpenTasks: true)
        machine.step(dt: 10, target: 1, summitPending: false, hasOpenTasks: true)
        #expect(abs(machine.manPosition - Machine.manSpeed * Machine.maxStep) < 1e-12)
        #expect(Machine.maxStep == 0.1)
    }

    @Test("A negative or non-finite dt does not move anything")
    func clampsInvalidDt() {
        var machine = Machine(target: 0.5, summitPending: false, hasOpenTasks: true)
        machine.step(dt: -5, target: 1, summitPending: false, hasOpenTasks: true)
        #expect(machine.manPosition == 0.5)
        machine.step(dt: .nan, target: 1, summitPending: false, hasOpenTasks: true)
        #expect(machine.manPosition == 0.5)
        machine.step(dt: .infinity, target: 1, summitPending: false, hasOpenTasks: true)
        #expect(machine.manPosition == 0.5)
        #expect(machine.moving == 0)
    }

    @Test("phaseTime accumulates and is exposed")
    func phaseTimeAccumulates() {
        var machine = Machine(target: 0.5, summitPending: false, hasOpenTasks: true)
        machine.step(dt: 0.05, target: 0.5, summitPending: false, hasOpenTasks: true)
        machine.step(dt: 0.05, target: 0.5, summitPending: false, hasOpenTasks: true)
        #expect(abs(machine.phaseTime - 0.1) < 1e-12)
    }
}

@Suite("SceneStateMachine sitting down when there is nothing to push")
struct PushingToSittingTests {
    @Test("Pushing with nothing left slides back to the bottom and sits")
    func pushesThenSits() {
        var machine = Machine(target: 0.3, summitPending: false, hasOpenTasks: true)
        #expect(machine.phase == .pushing)
        #expect(abs(machine.manPosition - 0.3) < 1e-12)

        // The last open task goes away without a completion, so there is no summit to play: he has
        // to ease down first and only sits once he is back at the bottom.
        var steps = 0
        var events: [Machine.Event] = []
        while machine.phase == .pushing && steps < 800 {
            events += machine.step(dt: 0.05, target: 0, summitPending: false, hasOpenTasks: false)
            steps += 1
            if steps == 1 {
                #expect(machine.phase == .pushing)
                #expect(machine.manPosition > 0)
            }
        }

        #expect(steps < 800)
        #expect(machine.phase == .sitting)
        #expect(machine.manPosition == 0)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)
        #expect(machine.moving == 0)
        #expect(!machine.facingLeft)
        #expect(machine.phaseTime == 0)
        #expect(machine.rockBounce == 0)
        // Sitting down from pushing is not a summit: nothing is emitted and nothing is consumed.
        #expect(events.isEmpty)
    }

    @Test("Adding a task then stands him up and he pushes again from 0")
    func addingATaskStandsUpAndPushes() {
        var machine = Machine(target: 0.3, summitPending: false, hasOpenTasks: true)
        #expect(run(
            &machine,
            target: 0,
            summitPending: false,
            hasOpenTasks: false,
            until: { $0.phase == .sitting }
        ) != nil)
        #expect(machine.manPosition == 0)

        // A task appears: sitting → standingUp → pushing, without the rock moving.
        #expect(run(&machine, target: 0.3, summitPending: false, hasOpenTasks: true, until: { $0.phase == .standingUp }) != nil)
        #expect(run(&machine, target: 0.3, summitPending: false, hasOpenTasks: true, until: { $0.phase == .pushing }) != nil)
        #expect(machine.manPosition == 0)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)
        #expect(machine.moving == 0)

        machine.step(dt: 0.1, target: 0.3, summitPending: false, hasOpenTasks: true)
        #expect(machine.moving == 1)
        #expect(machine.manPosition > 0)
    }

    @Test("Pushing at the bottom with open tasks never sits")
    func pushingAtZeroWithOpenTasksStaysPushing() {
        var machine = Machine(target: 0, summitPending: false, hasOpenTasks: true)
        for _ in 0..<200 {
            machine.step(dt: 0.05, target: 0, summitPending: false, hasOpenTasks: true)
            #expect(machine.phase == .pushing)
        }
        #expect(machine.manPosition == 0)
        #expect(machine.moving == 0)
    }

    @Test("A pending summit wins over sitting down at the bottom")
    func pendingSummitBeatsSitting() {
        // Reachable in the app: with the counter above 0 and no open tasks (he is standing up
        // after a summit, or the last task was just completed) he must climb, not sit.
        var machine = Machine(target: 0, summitPending: false, hasOpenTasks: false)
        #expect(machine.phase == .sitting)
        #expect(run(&machine, target: 0, summitPending: false, hasOpenTasks: true, until: { $0.phase == .pushing }) != nil)
        #expect(machine.manPosition == 0)

        machine.step(dt: 0.1, target: 1, summitPending: true, hasOpenTasks: false)
        #expect(machine.phase == .pushing)
        #expect(machine.moving == 1)
        #expect(machine.manPosition > 0)
    }
}

@Suite("SceneStateMachine summit sequence")
struct SummitSequenceTests {
    @Test("The full sequence visits every phase and emits summitFinished exactly once")
    func fullSequence() {
        var machine = Machine(target: 1, summitPending: true, hasOpenTasks: false)
        var phases: [Phase] = [machine.phase]
        var finishedEvents = 0

        let steps = run(
            &machine,
            summitPending: true,
            hasOpenTasks: false,
            onStep: { current, events in
                phases.append(current.phase)
                finishedEvents += events.filter { $0 == .summitFinished }.count
            },
            until: { $0.phase == .sitting }
        )

        #expect(steps != nil)
        #expect(phases.contains(.pushing))
        #expect(phases.contains(.atSummit))
        #expect(phases.contains(.rockRolling))
        #expect(phases.contains(.walkingDown))
        #expect(phases.contains(.sitting))
        #expect(finishedEvents == 1)
        #expect(machine.manPosition == 0)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)
        // The run is short: well under 10 seconds at 20 steps per second.
        #expect((steps ?? 800) < 200)
    }

    @Test("The sequence holds at the summit, rolls, bounces, then walks down and sits")
    func sequenceTiming() {
        var machine = Machine(target: 1, summitPending: true, hasOpenTasks: false)
        let dt = 0.02

        // Reach the summit.
        #expect(run(&machine, dt: dt, summitPending: true, hasOpenTasks: false, until: { $0.phase == .atSummit }) != nil)

        // The hold lasts summitHoldDuration.
        var holdSteps = 0
        while machine.phase == .atSummit && holdSteps < 200 {
            machine.step(dt: dt, target: 1, summitPending: true, hasOpenTasks: false)
            holdSteps += 1
        }
        #expect(machine.phase == .rockRolling)
        #expect(abs(Double(holdSteps) * dt - Machine.summitHoldDuration) < dt + 1e-9)

        // The rock starts from the summit and the man stays put.
        machine.step(dt: dt, target: 1, summitPending: true, hasOpenTasks: false)
        #expect(machine.phase == .rockRolling)
        #expect(machine.rockPosition <= 1)
        #expect(machine.rockPosition > 0.99)

        // It accelerates down, then bounces briefly at the bottom.
        var rollingSteps = 0
        var maxBounce = 0.0
        var sawBounce = false
        while machine.phase == .rockRolling && rollingSteps < 400 {
            machine.step(dt: dt, target: 1, summitPending: true, hasOpenTasks: false)
            rollingSteps += 1
            maxBounce = max(maxBounce, machine.rockBounce)
            if machine.rockBounce > 0 { sawBounce = true }
            #expect(machine.manPosition == 1)
        }
        #expect(sawBounce)
        #expect(maxBounce > 0)
        #expect(maxBounce <= Machine.rockBounceHeight + 1e-9)
        #expect(abs(Double(rollingSteps + 1) * dt - (Machine.rollDuration + Machine.rockBounceDuration)) < 2 * dt + 1e-9)

        // Walking down lands exactly on the rock's left edge, facing left.
        #expect(machine.phase == .walkingDown)
        #expect(machine.rockBounce == 0)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)
        machine.step(dt: dt, target: 1, summitPending: true, hasOpenTasks: false)
        #expect(machine.facingLeft)
        #expect(machine.moving == -1)

        var walkSteps = 0
        var finished = 0
        while machine.phase == .walkingDown && walkSteps < 400 {
            finished += machine.step(dt: dt, target: 1, summitPending: true, hasOpenTasks: false)
                .filter { $0 == .summitFinished }.count
            walkSteps += 1
        }
        #expect(machine.phase == .sitting)
        #expect(finished == 1)
        #expect(machine.manPosition == 0)
        #expect(!machine.facingLeft)
        #expect(machine.moving == 0)
        #expect(abs(Double(walkSteps) * dt - 1.0 / Machine.walkDownSpeed) < 2 * dt + 1e-9)
    }

    @Test("The summit sequence ignores the target while it runs")
    func ignoresTarget() {
        var machine = Machine(target: 1, summitPending: true, hasOpenTasks: false)
        #expect(run(&machine, summitPending: true, hasOpenTasks: false, until: { $0.phase == .walkingDown }) != nil)
        let manAtWalkStart = machine.manPosition
        #expect(manAtWalkStart == 1)

        // A wild target must not pull the man back up while walking down.
        machine.step(dt: 0.05, target: 1, summitPending: false, hasOpenTasks: false)
        machine.step(dt: 0.05, target: 1, summitPending: false, hasOpenTasks: false)
        #expect(machine.manPosition < manAtWalkStart)
        #expect(machine.moving == -1)
        #expect(machine.phase == .walkingDown)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)
    }

    @Test("Sitting then standing up resumes pushing at 0 without a rock jump")
    func sittingThenStandingUp() {
        var machine = Machine(target: 0, summitPending: false, hasOpenTasks: false)
        #expect(machine.phase == .sitting)

        let steps = run(
            &machine,
            target: 0.3,
            summitPending: false,
            hasOpenTasks: true,
            until: { $0.phase == .pushing }
        )
        #expect(steps != nil)
        #expect(machine.manPosition == 0)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)
        #expect(machine.moving == 0)
        #expect(!machine.facingLeft)

        // From there he eases toward the real target.
        machine.step(dt: 0.1, target: 0.3, summitPending: false, hasOpenTasks: true)
        #expect(machine.moving == 1)
        #expect(machine.manPosition > 0)
    }

    @Test("standingUp lasts standUpDuration")
    func standingUpDuration() {
        var machine = Machine(target: 0, summitPending: false, hasOpenTasks: false)
        machine.step(dt: 0.05, target: 0, summitPending: false, hasOpenTasks: true)
        #expect(machine.phase == .standingUp)

        let dt = 0.01
        var steps = 0
        while machine.phase == .standingUp && steps < 200 {
            machine.step(dt: dt, target: 0, summitPending: false, hasOpenTasks: true)
            steps += 1
        }
        #expect(machine.phase == .pushing)
        #expect(abs(Double(steps) * dt - Machine.standUpDuration) < dt + 1e-9)
        #expect(machine.phaseTime == 0)
    }

    @Test("Sitting waits while there is nothing to push")
    func sittingWaits() {
        var machine = Machine(target: 0, summitPending: false, hasOpenTasks: false)
        for _ in 0..<200 {
            machine.step(dt: 0.05, target: 0, summitPending: false, hasOpenTasks: false)
            #expect(machine.phase == .sitting)
        }
        #expect(machine.manPosition == 0)
    }

    @Test("A task added mid-sequence does not cancel the summit, then he stands up")
    func interruptedSequenceStillFinishes() {
        var machine = Machine(target: 1, summitPending: true, hasOpenTasks: false)
        var finished = 0
        var sawWalkingDown = false
        var sawSitting = false

        for _ in 0..<800 {
            // A task appears while the sequence runs, so consumeSummit() would be a no-op:
            // the machine still has to finish the run it started.
            let inSequence = machine.phase == .atSummit
                || machine.phase == .rockRolling
                || machine.phase == .walkingDown
            let events = machine.step(
                dt: 0.05,
                target: 0.9,
                summitPending: !inSequence,
                hasOpenTasks: true
            )
            finished += events.filter { $0 == .summitFinished }.count
            if machine.phase == .walkingDown { sawWalkingDown = true }
            if machine.phase == .sitting { sawSitting = true }
            if sawWalkingDown && machine.phase == .pushing { break }
        }

        #expect(sawWalkingDown)
        #expect(sawSitting)
        #expect(finished == 1)
        #expect(machine.phase == .pushing)
        #expect(machine.manPosition == 0)
        #expect(abs(machine.rockPosition - Machine.rockOffset) < 1e-12)
    }

    @Test("A second summit run emits the event again")
    func secondRunEmitsAgain() {
        var machine = Machine(target: 1, summitPending: true, hasOpenTasks: false)
        var finished = 0
        var runs = 0

        for _ in 0..<2000 {
            let inSequence = machine.phase == .rockRolling || machine.phase == .walkingDown
            let events = machine.step(
                dt: 0.05,
                target: 1,
                summitPending: !inSequence,
                hasOpenTasks: true
            )
            finished += events.filter { $0 == .summitFinished }.count
            if machine.phase == .sitting {
                runs += 1
                if runs == 2 { break }
            }
        }

        #expect(runs == 2)
        #expect(finished == 2)
    }
}
