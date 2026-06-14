import Foundation
import CoreGraphics
import QuartzCore

/// Shared clock + drift formula for the Metal "Pro" renderer.
///
/// Both the GPU shader and the SwiftUI overlays (labels, selection
/// halo, hover ring) need to compute the SAME per-node wobble offset
/// for a given (seed, time) pair, otherwise labels appear to lag the
/// disc they're labeling. Centralising the formula + the time origin
/// here guarantees they stay in lockstep.
///
/// Time origin is a process-wide `CACurrentMediaTime()` snapshot so
/// `time` stays small (Float precision degrades past a few hours of
/// uptime when feeding values like raw mach absolute time).
enum GraphDrift {
    /// Process-shared start moment. First reference initialises it.
    static let startTime: CFTimeInterval = CACurrentMediaTime()

    /// Seconds since `startTime`. Use as the `t` argument to
    /// `offset(seed:time:)`.
    static func now() -> Double { CACurrentMediaTime() - startTime }

    /// Same as `now()` but in `Float` for the shader uniform.
    static func nowFloat() -> Float { Float(now()) }

    /// Drift offset in screen-space points, matching the shader's
    /// `nodeDrift()` exactly. Two harmonic sums per axis, each with
    /// its own phase + frequency derived from the same 0..1 seed.
    /// Amplitudes tuned to 1.5× the Canvas path's 8 + 4 (the canvas
    /// drift was a touch too subtle; 4× was too enthusiastic).
    static func offset(seed: Float, time: Double) -> CGPoint {
        let s = Double(seed)
        let pa = s * 6.28318
        let pb = fract(s * 7.91)  * 6.28318
        let pc = fract(s * 13.37) * 6.28318
        let pd = fract(s * 23.71) * 6.28318
        let fa = 1.0 + fract(s * 3.14)  * 1.5
        let fb = 1.4 + fract(s * 5.93)  * 1.5
        let fc = 1.0 + fract(s * 11.29) * 1.5
        let fd = 1.4 + fract(s * 19.47) * 1.5
        let tt = time * 0.5
        let wx = sin(tt * fa + pa) * 5.0 + sin(tt * fb + pb) * 3.0
        let wy = cos(tt * fc + pc) * 5.0 + cos(tt * fd + pd) * 3.0
        return CGPoint(x: wx, y: wy)
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
}
