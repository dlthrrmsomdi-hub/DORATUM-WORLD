import Foundation
import simd

public final class PlayerController {
    public let radius: Float = 0.42
    public let height: Float = 1.82

    public let walkSpeed: Float = 4.6
    public let runSpeed: Float = 7.2
    public let sprintSpeed: Float = 10.6

    public var physicsState: CharacterPhysicsState
    public var yaw: Float = 0.0
    public private(set) var movementState: PlayerMovementState = .idle

    public let model: CharacterModel
    public let animation: CharacterAnimation

    private let physicsWorld: PhysicsWorld

    public var position: SIMD3<Float> { physicsState.position }
    public var velocity: SIMD3<Float> { physicsState.velocity }
    public var isGrounded: Bool { physicsState.isGrounded }

    public init(
        initialPosition: SIMD3<Float>,
        initialYaw: Float,
        physicsWorld: PhysicsWorld,
        model: CharacterModel
    ) {
        self.physicsState = CharacterPhysicsState(position: initialPosition)
        self.yaw = initialYaw
        self.physicsWorld = physicsWorld
        self.model = model
        self.animation = CharacterAnimation()
    }

    public func teleport(to position: SIMD3<Float>, yaw: Float) {
        self.physicsState = CharacterPhysicsState(position: position)
        self.yaw = yaw
        self.movementState = .idle
    }

    public func stepPhysics(
        input: InputController.FrameInputSnapshot,
        cameraYaw: Float,
        controlSensitivity: Float,
        fixedDt: Float
    ) {
        let rawMove = input.moveVector
        let rawMag = min(1.0, simd_length(rawMove) * controlSensitivity)

        var desiredHorizontalVelocity = SIMD3<Float>.zero
        if rawMag > 0.06 {
            let normInput = simd_normalize(rawMove)
            // Camera forward/right in XZ plane (Right-handed: forward = -sin(yaw), -cos(yaw))
            let camForward = SIMD3<Float>(-sin(cameraYaw), 0, -cos(cameraYaw))
            let camRight = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
            // Joystick Y > 0 means forward on screen
            let moveDir = simd_normalize(camRight * normInput.x + camForward * normInput.y)

            let targetSpeed: Float
            if input.sprintActive {
                targetSpeed = sprintSpeed
            } else if rawMag > 0.68 {
                targetSpeed = runSpeed
            } else {
                targetSpeed = walkSpeed * Math3D.clamp(rawMag / 0.68, min: 0.45, max: 1.0)
            }

            desiredHorizontalVelocity = moveDir * targetSpeed

            // Smoothly rotate character toward movement direction
            let targetYaw = atan2(moveDir.x, moveDir.z)
            yaw = Math3D.lerpAngle(yaw, targetYaw, Math3D.clamp(fixedDt * 12.0, min: 0.05, max: 1.0))
        }

        physicsWorld.stepCharacter(
            state: &physicsState,
            desiredHorizontalVelocity: desiredHorizontalVelocity,
            jumpRequested: input.jumpTriggered,
            radius: radius,
            height: height,
            dt: fixedDt
        )

        updateMovementState(sprintActive: input.sprintActive)
    }

    public func updateAnimation(dt: Float) {
        let horizSpeed = simd_length(SIMD2<Float>(physicsState.velocity.x, physicsState.velocity.z))
        animation.update(
            dt: dt,
            horizontalSpeed: horizSpeed,
            verticalVelocity: physicsState.velocity.y,
            state: movementState
        )
    }

    private func updateMovementState(sprintActive: Bool) {
        if !physicsState.isGrounded {
            movementState = physicsState.velocity.y > 0.5 ? .jumping : .falling
            return
        }

        if physicsState.landingTimer > 0.01 {
            movementState = .landing
            return
        }

        let horizSpeed = simd_length(SIMD2<Float>(physicsState.velocity.x, physicsState.velocity.z))
        if horizSpeed < 0.25 {
            movementState = .idle
        } else if sprintActive && horizSpeed > 7.6 {
            movementState = .sprinting
        } else if horizSpeed > 5.1 {
            movementState = .running
        } else {
            movementState = .walking
        }
    }
}
