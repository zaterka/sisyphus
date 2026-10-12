import Foundation
import Observation
import QuartzCore
import SisyphusCore

/// `@MainActor` adapter that owns the pure `SceneStateMachine` and steps it from a timer.
///
/// Each tick passes the store's current `progress`, `summitPending` and whether any task is
/// open, using the real elapsed time (split into `SceneStateMachine.maxStep` slices). When the
/// machine reports `.summitFinished`, the adapter answers with `store.consumeSummit()`, which is a
/// safe no-op if tasks were added during the summit run.
///
/// While there is nothing to push — `sitting` with an empty open list — the scene has almost
/// nothing to animate, so the timer drops to `idleTickRate` and `SceneView` redraws at
/// `idleFramePeriod`. A task added while idle is picked up at once: the store's task list is
/// observed, so the scene does not wait for the next slow tick, and never for longer than one.
@MainActor
@Observable
final class SceneModel {
    /// Snapshot of the animation state, read by `SceneView` on each drawn frame.
    ///
    /// Deliberately *not* observable: the machine changes on every tick (at the very least
    /// `phaseTime` advances), so publishing it would invalidate `SceneView` 30 times a second for a
    /// view that already redraws on its own `TimelineView` schedule.
    var machine: SceneStateMachine { storage }

    /// Timer frequency while he has something to push, in Hz.
    static let tickRate: Double = 30
    /// Timer frequency while he is sitting with nothing to push, in Hz.
    static let idleTickRate: Double = 5
    /// `SceneView` redraw period while pushing, in seconds (≈ 15 fps).
    static let activeFramePeriod: Double = 1.0 / 15
    /// `SceneView` redraw period while idle, in seconds (≈ 6 fps).
    static let idleFramePeriod: Double = 1.0 / 6
    /// How many clamped slices a single tick may advance the machine by. The machine clamps one
    /// step to `SceneStateMachine.maxStep`, so a stalled tick advances at most 3 × 0.1 s instead of
    /// teleporting a sprite.
    static let maxSubSteps = 3

    /// `true` while the scene runs at the reduced idle rate. It only flips when the phase or the
    /// open list changes, so observing it is cheap; `SceneView` reads `framePeriod`.
    private(set) var isIdle: Bool

    /// Redraw period for `SceneView`, in seconds: slower while there is nothing to animate.
    var framePeriod: Double {
        isIdle ? SceneModel.idleFramePeriod : SceneModel.activeFramePeriod
    }

    @ObservationIgnored private var storage: SceneStateMachine
    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick: CFTimeInterval?
    /// Interval the current `timer` was built with, in Hz.
    @ObservationIgnored private var activeTickRate: Double
    /// Bumped by `start()`/`stop()`; queued store-observation callbacks from an older generation
    /// are ignored.
    @ObservationIgnored private var observationGeneration = 0

    init(store: TaskStore) {
        self.store = store
        let list = store.list
        let machine = SceneStateMachine(
            target: list.progress,
            summitPending: list.summitPending,
            hasOpenTasks: !list.open.isEmpty
        )
        let idle = SceneModel.shouldRunIdle(machine: machine, list: list)
        self.storage = machine
        self.isIdle = idle
        self.activeTickRate = idle ? SceneModel.idleTickRate : SceneModel.tickRate
    }

    // MARK: - Lifecycle

    /// Starts the timer on the main run loop (`.common` mode, so it keeps ticking while menus are
    /// tracking or a list is being dragged). Calling it twice is harmless.
    func start() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        timer = makeTimer()
        observationGeneration &+= 1
        observeStore(generation: observationGeneration)
    }

    /// Stops the timer. The machine keeps its state and resumes from it on the next `start()`.
    func stop() {
        timer?.invalidate()
        timer = nil
        lastTick = nil
        // Invalidates an observation callback that is still queued for the main actor.
        observationGeneration &+= 1
    }

    // MARK: - Stepping

    /// One step: real `dt`, store inputs, rate adjustment, event handling.
    private func tick() {
        let now = CACurrentMediaTime()
        let dt = max(0, lastTick.map { now - $0 } ?? (1.0 / activeTickRate))
        lastTick = now

        let list = store.list
        var next = storage
        let events = SceneModel.advance(
            &next,
            dt: dt,
            target: list.progress,
            summitPending: list.summitPending,
            hasOpenTasks: !list.open.isEmpty
        )
        storage = next

        for event in events {
            switch event {
            case .summitFinished:
                store.consumeSummit()
            }
        }

        // The store is re-read after the events, so a task that arrived during this tick (or that
        // `consumeSummit` just answered) is taken into account right away.
        let idle = SceneModel.shouldRunIdle(machine: next, list: store.list)
        if idle != isIdle {
            isIdle = idle
            activeTickRate = idle ? SceneModel.idleTickRate : SceneModel.tickRate
            rescheduleTimer()
        }
    }

    /// Steps the machine by `dt` seconds and returns the events it emitted.
    ///
    /// The machine clamps a single step to `SceneStateMachine.maxStep` (0.1 s) so a stalled timer
    /// cannot teleport a sprite. The idle timer runs slower than that, so the elapsed time is split
    /// into slices: otherwise `phaseTime` would advance at half speed and the sitting breathing and
    /// the "z" animation would run slow. At 30 Hz one slice is enough, so this is a single step.
    private static func advance(
        _ machine: inout SceneStateMachine,
        dt: Double,
        target: Double,
        summitPending: Bool,
        hasOpenTasks: Bool
    ) -> [SceneStateMachine.Event] {
        var events: [SceneStateMachine.Event] = []
        var remaining = max(0, dt)
        var slices = 0
        repeat {
            let slice = min(remaining, SceneStateMachine.maxStep)
            events += machine.step(
                dt: slice,
                target: target,
                summitPending: summitPending,
                hasOpenTasks: hasOpenTasks
            )
            remaining -= slice
            slices += 1
        } while remaining > 0 && slices < SceneModel.maxSubSteps
        return events
    }

    /// The scene can idle when there is nothing to animate: he sits and the store has no open task.
    private static func shouldRunIdle(machine: SceneStateMachine, list: TaskList) -> Bool {
        machine.phase == .sitting && list.open.isEmpty
    }

    // MARK: - Timer

    private func makeTimer() -> Timer {
        let interval = 1.0 / activeTickRate
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // A proportional tolerance lets the system coalesce the timer (which matters at the idle
        // rate) without the animation stuttering.
        timer.tolerance = interval / 10
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// Swaps in a timer for the new rate. The old timer is held until it has been invalidated, so
    /// this is safe to call from inside that timer's own callback.
    private func rescheduleTimer() {
        let old = timer
        timer = makeTimer()
        old?.invalidate()
    }

    /// Wakes the scene as soon as the store's tasks change, so a task added while the timer is
    /// idling at 5 Hz is picked up at once instead of up to one idle tick later.
    ///
    /// `withObservationTracking` fires once, so the observation is re-armed after each change. The
    /// generation guard drops callbacks left over from an earlier `start()`/`stop()` pair, so the
    /// scene never ends up with two observers doing the same work.
    private func observeStore(generation: Int) {
        withObservationTracking {
            _ = store.list
        } onChange: { [weak self] in
            // onChange fires before the new value is stored; act on the next main-actor turn.
            Task { @MainActor [weak self] in
                guard let self, generation == self.observationGeneration, self.timer != nil else { return }
                self.tick()
                self.observeStore(generation: generation)
            }
        }
    }
}
