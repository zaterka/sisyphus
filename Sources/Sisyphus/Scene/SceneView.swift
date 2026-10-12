import CoreGraphics
import SisyphusCore
import SwiftUI

/// The animated hill scene: 160×90 logical pixels drawn at 2× (320×180 pt).
///
/// The view polls `model.machine` on every `TimelineView` frame — that snapshot is deliberately not
/// observable, so stepping the machine does not re-render this view — and redraws at
/// `model.framePeriod`: ≈ 15 fps while he is pushing, ≈ 6 fps while he sits with nothing to do.
struct SceneView: View {
    let model: SceneModel

    init(model: SceneModel) {
        self.model = model
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: model.framePeriod)) { _ in
            let snapshot = model.machine
            Canvas(opaque: true) { context, _ in
                SceneRenderer.draw(SceneLayout(machine: snapshot), in: &context)
            }
        }
        // `PeriodicTimelineSchedule` is not comparable, so a new rate needs a new identity before
        // SwiftUI is guaranteed to schedule with it. The lifecycle hooks below stay outside, so
        // `start()`/`stop()` are not re-run for a rate change.
        .id(model.framePeriod)
        .frame(
            width: Double(SceneGeometry.width) * SceneGeometry.scale,
            height: Double(SceneGeometry.height) * SceneGeometry.scale
        )
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .accessibilityElement()
        .accessibilityLabel("Sisyphus pushing his boulder up the hill")
    }
}

// MARK: - Layout (pure)

/// Everything needed to draw one frame, derived purely from a machine snapshot: which sprite
/// frames to show and where (integer logical pixels, top-left of each sprite).
struct SceneLayout: Equatable {
    enum ManPose: Equatable {
        case push(Int)
        case walk(Int)
        case stand
        case sit(Int)
    }

    var pose: ManPose
    var manX: Int
    var manY: Int
    var mirrored: Bool
    var rockFrame: Int
    var rockX: Int
    var rockY: Int
    /// Top-left of the sleep "z", when visible.
    var z: (x: Int, y: Int)?

    static func == (lhs: SceneLayout, rhs: SceneLayout) -> Bool {
        lhs.pose == rhs.pose && lhs.manX == rhs.manX && lhs.manY == rhs.manY
            && lhs.mirrored == rhs.mirrored && lhs.rockFrame == rhs.rockFrame
            && lhs.rockX == rhs.rockX && lhs.rockY == rhs.rockY
            && lhs.z?.x == rhs.z?.x && lhs.z?.y == rhs.z?.y
    }

    // MARK: Tuning

    /// The man's feet are drawn this many logical px behind his slope point, so that with the
    /// machine's `rockOffset` (≈ 8 px uphill) his hands meet the side of the boulder.
    static let footBehind: Double = 5
    /// Logical px between the man's slope point and the rock centre while pushing.
    static let rockLead: Double = SceneStateMachine.rockOffset
        * (SceneGeometry.slopeEnd.x - SceneGeometry.slopeStart.x)
    /// Logical px the boulder travels for each quarter-turn roll frame (circumference / 4).
    static let pxPerRollFrame: Double = 2 * Double.pi * Double(SpriteFrames.rockSize) / 2 / 4

    static let pushFPS: Double = 8
    static let strainFPS: Double = 2
    static let walkFPS: Double = 10
    static let breatheFPS: Double = 1.2
    static let zCycle: Double = 2.6
    static let zVisible: Double = 1.8

    /// Column inside each 16-px man sprite that stands on the slope point.
    private static func anchorColumn(for pose: ManPose) -> Int {
        switch pose {
        case .push: return 5
        case .walk, .stand: return 8
        case .sit: return 7
        }
    }

    init(machine m: SceneStateMachine) {
        let t = m.phaseTime

        // Pose / frame selection.
        let pose: ManPose
        switch m.phase {
        case .pushing:
            switch m.moving {
            case 1:
                pose = .push(Self.cycle(t, fps: Self.pushFPS, count: 4))
            case -1:
                pose = .push(3 - Self.cycle(t, fps: Self.pushFPS, count: 4))
            default:
                pose = .push(Self.cycle(t, fps: Self.strainFPS, count: 2))
            }
        case .atSummit, .rockRolling, .standingUp:
            pose = .stand
        case .walkingDown:
            pose = .walk(Self.cycle(t, fps: Self.walkFPS, count: 4))
        case .sitting:
            pose = .sit(Self.cycle(t, fps: Self.breatheFPS, count: 2))
        }
        self.pose = pose
        self.mirrored = m.facingLeft

        // Rock: centre x along the slope (extended onto the plateau so it never overlaps the man
        // at the summit), bottom row resting on the ground line, lifted by the bounce.
        let rockCenterX = Self.rockCenterX(m)
        let half = Double(SpriteFrames.rockSize) / 2
        self.rockX = Int((rockCenterX - half).rounded())
        let rockGround = SceneGeometry.groundY(atX: rockCenterX)
        self.rockY = Int((rockGround - Double(SpriteFrames.rockSize - 1) - m.rockBounce).rounded())
        let turns = Int((rockCenterX / Self.pxPerRollFrame).rounded(.down))
        self.rockFrame = ((turns % 4) + 4) % 4

        // Man.
        let size = SpriteFrames.manSize
        if case .sit = pose {
            // Sitting with his back against the boulder, on the ground next to it.
            let left = self.rockX - (size - 2)
            self.manX = left
            let ground = SceneGeometry.groundY(atX: Double(left + Self.anchorColumn(for: pose)))
            self.manY = Int(ground.rounded()) - (size - 1)
        } else {
            let footX = SceneGeometry.slopeX(progress: m.manPosition) - Self.footBehind
            var anchor = Self.anchorColumn(for: pose)
            if m.facingLeft { anchor = size - 1 - anchor }
            self.manX = Int(footX.rounded()) - anchor
            let ground = SceneGeometry.groundY(atX: footX)
            self.manY = Int(ground.rounded()) - (size - 1)
        }

        // Sleep "z" rising above his head after he has settled.
        if case .sit = pose, t > 0.8 {
            let local = (t - 0.8).truncatingRemainder(dividingBy: Self.zCycle)
            if local < Self.zVisible {
                let rise = Int(local * 4)
                let sway = (Int(local * 2) % 2)
                self.z = (manX + 11 + sway, manY + 1 - rise)
            } else {
                self.z = nil
            }
        } else {
            self.z = nil
        }
    }

    /// Rock centre in logical px.
    ///
    /// - While pushing (and at the summit) it leads the man by `rockLead`, ignoring the machine's
    ///   clamp at 1, so near the top the boulder is shoved onto the plateau instead of into him.
    /// - Otherwise `rockPosition` (which runs 1 → `rockOffset`) is mapped onto the same span:
    ///   1 ↦ summit point + lead, `rockOffset` ↦ foot of the hill + lead. Both mappings agree at
    ///   every phase boundary, so the rock never jumps.
    static func rockCenterX(_ m: SceneStateMachine) -> Double {
        let span = SceneGeometry.slopeEnd.x - SceneGeometry.slopeStart.x
        switch m.phase {
        case .pushing, .atSummit:
            return SceneGeometry.slopeX(progress: m.manPosition) + rockLead
        case .rockRolling, .walkingDown, .sitting, .standingUp:
            let offset = SceneStateMachine.rockOffset
            let u = (m.rockPosition - offset) / (1 - offset) // 1 at the summit, 0 at rest
            return SceneGeometry.slopeStart.x + rockLead + u * span
        }
    }

    private static func cycle(_ t: Double, fps: Double, count: Int) -> Int {
        guard t.isFinite, t >= 0 else { return 0 }
        return Int(t * fps) % count
    }
}

// MARK: - Renderer

enum SceneRenderer {
    /// Draws one frame. `context` is in points; everything is drawn in logical px scaled 2×.
    static func draw(_ layout: SceneLayout, in context: inout GraphicsContext) {
        context.scaleBy(x: SceneGeometry.scale, y: SceneGeometry.scale)
        let sprites = SpriteImages.shared

        blit(Background.image, x: 0, y: 0, mirrored: false, in: &context)
        blit(sprites.rock[layout.rockFrame], x: layout.rockX, y: layout.rockY, mirrored: false, in: &context)

        let man: CGImage
        switch layout.pose {
        case .push(let i): man = sprites.push[i]
        case .walk(let i): man = sprites.walk[i]
        case .stand: man = sprites.stand
        case .sit(let i): man = sprites.sit[i]
        }
        blit(man, x: layout.manX, y: layout.manY, mirrored: layout.mirrored, in: &context)

        if let z = layout.z {
            blit(sprites.z, x: z.x, y: z.y, mirrored: false, in: &context)
        }
    }

    /// Draws a `CGImage` at integer logical coordinates, crisp (no interpolation), optionally
    /// mirrored horizontally around its own centre.
    private static func blit(_ image: CGImage, x: Int, y: Int, mirrored: Bool, in context: inout GraphicsContext) {
        let w = Double(image.width)
        let h = Double(image.height)
        let picture = Image(decorative: image, scale: 1).interpolation(.none)
        if mirrored {
            var flipped = context
            flipped.translateBy(x: Double(x) + w, y: Double(y))
            flipped.scaleBy(x: -1, y: 1)
            flipped.draw(picture, in: CGRect(x: 0, y: 0, width: w, height: h))
        } else {
            context.draw(picture, in: CGRect(x: Double(x), y: Double(y), width: w, height: h))
        }
    }
}
