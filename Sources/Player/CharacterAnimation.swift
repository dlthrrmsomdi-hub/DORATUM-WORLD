import Foundation
import simd

public enum PlayerMovementState: String {
    case idle = "Idle"
    case walking = "Walking"
    case running = "Running"
    case sprinting = "Sprinting"
    case jumping = "Jumping"
    case falling = "Falling"
    case landing = "Landing"
}

public struct CharacterPose {
    public var bodyBobY: Float = 0.0
    public var torsoPitch: Float = 0.0
    public var headPitch: Float = 0.0
    public var leftArmSwingX: Float = 0.0
    public var rightArmSwingX: Float = 0.0
    public var leftArmOutZ: Float = 0.06
    public var rightArmOutZ: Float = -0.06
    public var leftLegSwingX: Float = 0.0
    public var rightLegSwingX: Float = 0.0
}

public final class CharacterAnimation {
    private var walkCyclePhase: Float = 0.0
    private var idleTime: Float = 0.0
    public private(set) var currentPose = CharacterPose()

    public init() {}

    public func update(
        dt: Float,
        horizontalSpeed: Float,
        verticalVelocity: Float,
        state: PlayerMovementState
    ) {
        idleTime += dt
        var target = CharacterPose()

        switch state {
        case .idle:
            // Gentle breathing bob and relaxed arms
            target.bodyBobY = sin(idleTime * 2.2) * 0.02
            target.torsoPitch = 0.0
            target.leftArmSwingX = sin(idleTime * 2.2) * 0.03
            target.rightArmSwingX = -sin(idleTime * 2.2) * 0.03
            target.leftArmOutZ = 0.07
            target.rightArmOutZ = -0.07
            target.leftLegSwingX = 0.0
            target.rightLegSwingX = 0.0

        case .walking, .running, .sprinting:
            let cadence = max(2.8, horizontalSpeed * 1.35)
            walkCyclePhase += dt * cadence
            let speedNorm = Math3D.clamp(horizontalSpeed / 10.5, min: 0.25, max: 1.0)
            let swingAmp: Float = Math3D.lerp(0.42, 0.98, speedNorm)

            let s = sin(walkCyclePhase)
            target.leftLegSwingX = s * swingAmp
            target.rightLegSwingX = -s * swingAmp
            target.leftArmSwingX = -s * swingAmp * 0.88
            target.rightArmSwingX = s * swingAmp * 0.88
            target.leftArmOutZ = 0.09
            target.rightArmOutZ = -0.09
            target.bodyBobY = abs(cos(walkCyclePhase)) * (0.045 + 0.055 * speedNorm)
            target.torsoPitch = (state == .sprinting ? 0.16 : (state == .running ? 0.09 : 0.04))

        case .jumping:
            target.bodyBobY = 0.06
            target.torsoPitch = 0.08
            target.leftArmSwingX = -0.75
            target.rightArmSwingX = -0.65
            target.leftArmOutZ = 0.28
            target.rightArmOutZ = -0.28
            target.leftLegSwingX = 0.42
            target.rightLegSwingX = -0.35

        case .falling:
            let fallFactor = Math3D.clamp(-verticalVelocity / 18.0, min: 0.0, max: 1.0)
            target.bodyBobY = 0.04
            target.torsoPitch = -0.06
            target.leftArmSwingX = -0.45 - fallFactor * 0.35
            target.rightArmSwingX = -0.45 - fallFactor * 0.35
            target.leftArmOutZ = 0.42
            target.rightArmOutZ = -0.42
            target.leftLegSwingX = 0.24
            target.rightLegSwingX = -0.18

        case .landing:
            target.bodyBobY = -0.12
            target.torsoPitch = 0.14
            target.leftArmSwingX = 0.22
            target.rightArmSwingX = 0.22
            target.leftArmOutZ = 0.18
            target.rightArmOutZ = -0.18
            target.leftLegSwingX = 0.15
            target.rightLegSwingX = -0.15
        }

        let blend = Math3D.clamp(dt * 14.0, min: 0.05, max: 1.0)
        currentPose.bodyBobY = Math3D.lerp(currentPose.bodyBobY, target.bodyBobY, blend)
        currentPose.torsoPitch = Math3D.lerp(currentPose.torsoPitch, target.torsoPitch, blend)
        currentPose.headPitch = Math3D.lerp(currentPose.headPitch, target.headPitch, blend)
        currentPose.leftArmSwingX = Math3D.lerp(currentPose.leftArmSwingX, target.leftArmSwingX, blend)
        currentPose.rightArmSwingX = Math3D.lerp(currentPose.rightArmSwingX, target.rightArmSwingX, blend)
        currentPose.leftArmOutZ = Math3D.lerp(currentPose.leftArmOutZ, target.leftArmOutZ, blend)
        currentPose.rightArmOutZ = Math3D.lerp(currentPose.rightArmOutZ, target.rightArmOutZ, blend)
        currentPose.leftLegSwingX = Math3D.lerp(currentPose.leftLegSwingX, target.leftLegSwingX, blend)
        currentPose.rightLegSwingX = Math3D.lerp(currentPose.rightLegSwingX, target.rightLegSwingX, blend)
    }
}
