import CoreGraphics
import Foundation
import ImageIO
import SisyphusCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Command line

/// The `--export-gif <path>` request, parsed out of `CommandLine.arguments` before anything else in
/// the app is created.
///
/// The export is a hidden CLI mode of the app binary rather than a second target, because the scene
/// code lives in the executable target: this keeps the GIF rendered by exactly the drawing code the
/// panel uses, with no duplicated geometry or sprites.
enum GIFExportRequest: Equatable {
    static let flag = "--export-gif"
    static let usage = "usage: Sisyphus \(flag) <output path>"

    /// The flag is not present: start the app normally.
    case none
    /// The flag is present but is not followed by a path.
    case missingPath
    /// Render the scene to `path`, then exit.
    case export(path: String)

    init(arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.flag) else {
            self = .none
            return
        }
        let pathIndex = arguments.index(after: index)
        guard pathIndex < arguments.endIndex else {
            self = .missingPath
            return
        }
        let path = arguments[pathIndex]
        // A following option means the path was forgotten; a path starting with "-" would be
        // indistinguishable from one, and is rejected rather than guessed.
        guard !path.isEmpty, !path.hasPrefix("-") else {
            self = .missingPath
            return
        }
        self = .export(path: path)
    }
}

// MARK: - Exporter

/// Renders the scene animation off-screen into an animated GIF.
///
/// The scenario drives the real `SceneStateMachine` against a real `TaskList` value — four open
/// tasks are completed one at a time, so `progress`, `summitPending` and `hasOpenTasks` are the
/// values the app itself would compute — and every frame goes through `SceneRenderer`, so the GIF
/// shows the shipped animation and not a look-alike.
///
/// The animation is deterministic: the machine is stepped with a fixed `dt` (never more than
/// `SceneStateMachine.maxStep`), the frames are counted rather than timed, and no timestamps or
/// clocks reach the scene, so the same binary produces the same GIF on any machine.
///
/// Exit codes are the caller's (`main.swift`): `true` → 0, `false` → 1.
enum GIFExporter {

    // MARK: Tuning

    /// Frames per second of the exported GIF. `dt` = 1/20 s stays inside `SceneStateMachine.maxStep`
    /// (0.1 s), so one frame is exactly one machine step.
    static let frameRate: Double = 20
    /// Time step of the scenario, in seconds.
    static let dt: Double = 1.0 / frameRate
    /// Pixel scale of the rendered frames. The scene is 160×90 logical px at `SceneGeometry.scale`
    /// (2× → 320×180 pt), so `2` gives crisp 640×360 frames with 4×4 px logical pixels.
    static let exportScale: Double = 2
    /// How many tasks the scenario starts with, and therefore how many completions it plays.
    static let taskCount = 4
    /// How long he pushes at progress 0 before the first task is completed, in seconds.
    static let initialHold: Double = 0.5
    /// Gap between two completions, in seconds. A quarter of the hill takes 1 s at
    /// `SceneStateMachine.manSpeed`, so 1.1 s leaves a visible pause at every stop.
    static let completionInterval: Double = 1.1
    /// How long he must have been sitting when the run ends, in seconds: the "z" only appears
    /// 0.8 s into `sitting`, and `SceneLayout.zVisible` shows it for 1.8 s of a 2.6 s cycle.
    static let minimumSitTime: Double = 2.5
    /// Hard cap on the number of frames, so a scenario that never settles cannot hang the export.
    static let maximumFrames = 600

    /// Frame size in points: the scene's logical size at `SceneGeometry.scale`.
    static var frameWidth: Double { Double(SceneGeometry.width) * SceneGeometry.scale }
    static var frameHeight: Double { Double(SceneGeometry.height) * SceneGeometry.scale }

    /// Phases the scenario must play through, in this order, or the export fails. The run is matched
    /// against this on first occurrences: the phase sequence with later repeats removed must equal
    /// exactly this list, so an extra phase is a failure too.
    static let requiredPhases: [SceneStateMachine.Phase] = [
        .pushing, .atSummit, .rockRolling, .walkingDown, .sitting,
    ]

    // MARK: Failures

    /// Why the scenario did not play out as expected.
    enum ScenarioError: Error, CustomStringConvertible {
        /// Phases that never appeared, or appeared out of order.
        case phaseOrder(expected: [SceneStateMachine.Phase], seen: [SceneStateMachine.Phase])
        /// The machine never reported `summitFinished`, so no summit was consumed.
        case summitNotConsumed
        /// A task was completed before he had walked to the target the previous one set, so the
        /// climb — the point of the animation — would be cut short.
        case stalledClimb(completion: Int, position: Double, reached: Double)
        /// The run hit `maximumFrames` before he had been sitting long enough.
        case unfinished(
            frames: Int,
            phase: SceneStateMachine.Phase,
            phaseTime: Double,
            minimumSitTime: Double
        )

        var description: String {
            switch self {
            case let .phaseOrder(expected, seen):
                let want = expected.map(\.rawValue).joined(separator: " → ")
                let got = seen.map(\.rawValue).joined(separator: " → ")
                return "unexpected phase sequence (want \(want), got \(got))"
            case .summitNotConsumed:
                return "the scene never finished a summit run"
            case let .stalledClimb(completion, position, reached):
                return """
                    completion \(completion + 1) arrived before the climb finished \
                    (man at \(position), target was \(reached))
                    """
            case let .unfinished(frames, phase, phaseTime, minimumSitTime):
                return """
                    the animation did not settle: stopped after \(frames) frames in \
                    \(phase.rawValue) (phaseTime \(phaseTime)s, need \(minimumSitTime)s of sitting)
                    """
            }
        }
    }

    // MARK: Entry point

    /// Renders the scenario to an animated GIF at `path`.
    ///
    /// The GIF is rendered into a temporary file next to `path` and only moved onto `path` once it
    /// is complete, so a failure part-way through — a full disk, an unrenderable frame, a viewer
    /// holding the old file open — leaves any existing GIF exactly as it was instead of truncating
    /// or half-overwriting it.
    ///
    /// - Returns: `true` on success; `false` after printing the reason to standard error.
    @MainActor
    static func export(to path: String) -> Bool {
        let snapshots: [SceneStateMachine]
        do {
            snapshots = try scenario()
        } catch {
            fail("\(error)")
            return false
        }

        let url = URL(fileURLWithPath: path)
        guard let staged = stage(snapshots, nextTo: url) else {
            return false
        }

        do {
            try commit(staged, to: url)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            fail("could not replace \(url.path): \(error.localizedDescription)")
            return false
        }

        let duration = Double(snapshots.count) * dt
        print("Exported \(snapshots.count) frames (\(String(format: "%.2f", duration))s) to \(url.path)")
        return true
    }

    // MARK: Writing

    /// Renders `snapshots` into a temporary GIF in the destination's own directory.
    ///
    /// The staging file sits next to the destination on purpose: that keeps the final move a rename
    /// on one volume rather than a copy onto another, and it means the destination path itself is
    /// not touched until the write has succeeded.
    ///
    /// - Returns: the staged file's URL, or `nil` after reporting why the render failed.
    @MainActor
    private static func stage(_ snapshots: [SceneStateMachine], nextTo url: URL) -> URL? {
        let staged = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )

        guard let destination = CGImageDestinationCreateWithURL(
            staged as CFURL,
            UTType.gif.identifier as CFString,
            snapshots.count,
            nil
        ) else {
            fail("could not create a GIF file for \(url.path)")
            return nil
        }

        // Loop count 0 = loop forever. It is a file-level property, so it goes on the destination.
        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        // Both delay keys are set: viewers disagree about which one they honour, and a frame
        // without a delay can be dropped or played at the viewer's default speed.
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: dt,
                kCGImagePropertyGIFUnclampedDelayTime: dt,
            ]
        ]

        for (index, snapshot) in snapshots.enumerated() {
            guard let image = render(snapshot) else {
                try? FileManager.default.removeItem(at: staged)
                fail("frame \(index) of \(snapshots.count) could not be rendered")
                return nil
            }
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: staged)
            fail("writing \(staged.path) failed")
            return nil
        }

        return staged
    }

    /// Moves the finished GIF onto `url`, replacing whatever is already there in one step.
    ///
    /// - Throws: whatever `FileManager` throws, after which the destination is unchanged.
    private static func commit(_ staged: URL, to url: URL) throws {
        let manager = FileManager.default
        // `replaceItemAt` is the atomic swap, but it insists on an existing original; the first
        // export to a fresh path is a plain move instead.
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: staged)
        } else {
            try manager.moveItem(at: staged, to: url)
        }
    }

    // MARK: Scenario

    /// Plays the scenario on a fresh machine and returns one snapshot per frame.
    ///
    /// - Throws: `ScenarioError` when the run is not the animation it must be — a phase out of order,
    ///   a climb cut short by the next completion, no summit consumed, or no long enough sit at the
    ///   end — so a broken scene fails the build instead of quietly shipping a wrong GIF.
    static func scenario() throws -> [SceneStateMachine] {
        var list = startList()
        var machine = SceneStateMachine(
            target: list.progress,
            summitPending: list.summitPending,
            hasOpenTasks: !list.open.isEmpty
        )

        // Completions are scheduled by frame index rather than by accumulated seconds, so floating
        // point drift can never move (or skip) one.
        let completionFrames = (0..<taskCount).map { index in
            Int(((initialHold + Double(index) * completionInterval) / dt).rounded())
        }

        var frames: [SceneStateMachine] = []
        var phaseOrder: [SceneStateMachine.Phase] = [machine.phase]
        // Man position at each completion, so the run can prove he had reached the target the
        // previous completion set before the next one arrived.
        var positionsAtCompletion: [Double] = []
        var summitConsumed = false
        var nextCompletion = 0

        while frames.count < maximumFrames {
            // A completion is applied before the frame is stepped and recorded, so the first frame
            // of each climb already shows the new target.
            while nextCompletion < completionFrames.count,
                  frames.count >= completionFrames[nextCompletion],
                  let id = list.open.first?.id {
                positionsAtCompletion.append(machine.manPosition)
                list.complete(id: id, now: Date(timeIntervalSinceReferenceDate: 0))
                nextCompletion += 1
            }

            let events = machine.step(
                dt: dt,
                target: list.progress,
                summitPending: list.summitPending,
                hasOpenTasks: !list.open.isEmpty
            )
            for event in events {
                switch event {
                case .summitFinished:
                    // Mirrors SceneModel.tick(): the running animation answers the event by
                    // resetting the earned progress.
                    summitConsumed = list.consumeSummit() || summitConsumed
                }
            }

            frames.append(machine)
            if machine.phase != phaseOrder.last {
                phaseOrder.append(machine.phase)
            }

            if machine.phase == .sitting, machine.phaseTime >= minimumSitTime {
                break
            }
        }

        try validate(
            frames: frames,
            phaseOrder: phaseOrder,
            positionsAtCompletion: positionsAtCompletion,
            summitConsumed: summitConsumed
        )
        return frames
    }

    /// The four open tasks the scenario completes. Titles and priorities only affect the task list
    /// UI, never the scene, but they keep the scenario readable.
    static func startList() -> TaskList {
        var list = TaskList()
        for title in ["Draft the release notes", "Wire up the CI build", "Render the GIF", "Ship it"] {
            list.add(title: title, now: Date(timeIntervalSinceReferenceDate: 0))
        }
        return list
    }

    /// Checks that the recorded run really is the animation the GIF is supposed to show.
    private static func validate(
        frames: [SceneStateMachine],
        phaseOrder: [SceneStateMachine.Phase],
        positionsAtCompletion: [Double],
        summitConsumed: Bool
    ) throws {
        // `phaseOrder` records every phase change, so the first entry for each phase is the frame
        // that phase was entered in. Keeping only the first occurrence of each phase must therefore
        // reproduce `requiredPhases` exactly: every required phase is reached, in that order, and no
        // other phase — a skipped summit, a stray `standingUp` — appears in between. Later repeats
        // collapse away, because only a phase's first occurrence decides the order.
        var seen: [SceneStateMachine.Phase] = []
        for phase in phaseOrder where !seen.contains(phase) {
            seen.append(phase)
        }
        guard seen == requiredPhases else {
            throw ScenarioError.phaseOrder(expected: requiredPhases, seen: phaseOrder)
        }

        // Every completion but the first has a target to beat: a quarter of the hill takes 1 s at
        // `SceneStateMachine.manSpeed` and `completionInterval` leaves only 0.1 s of slack, so a
        // slower climb (or a shorter interval) would cut the animation short — this is what makes
        // that a loud failure instead of a GIF where he never reaches any stop.
        for (index, position) in positionsAtCompletion.enumerated().dropFirst() {
            let reached = Double(index) / Double(taskCount)
            guard position >= reached - 1e-9 else {
                throw ScenarioError.stalledClimb(
                    completion: index,
                    position: position,
                    reached: reached
                )
            }
        }

        guard summitConsumed else {
            throw ScenarioError.summitNotConsumed
        }

        guard let last = frames.last,
              last.phase == .sitting,
              last.phaseTime >= minimumSitTime
        else {
            throw ScenarioError.unfinished(
                frames: frames.count,
                phase: frames.last?.phase ?? .pushing,
                phaseTime: frames.last?.phaseTime ?? 0,
                minimumSitTime: minimumSitTime
            )
        }
    }

    // MARK: Rendering

    /// Renders one machine snapshot the same way `SceneView` draws it, into a bitmap.
    ///
    /// One `ImageRenderer` per frame: its content is fixed at init, so a fresh one is the cheapest
    /// way to render a sequence. No `NSApplication` is touched, so the export works in a plain CLI
    /// process with no window server session of its own.
    @MainActor
    private static func render(_ machine: SceneStateMachine) -> CGImage? {
        let renderer = ImageRenderer(
            content: Canvas(opaque: true) { context, _ in
                SceneRenderer.draw(SceneLayout(machine: machine), in: &context)
            }
            .frame(width: frameWidth, height: frameHeight)
        )
        renderer.scale = exportScale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    // MARK: Output

    private static func fail(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }
}
