import Foundation
import simd

public struct CharacterPhysicsState {
    public var position: SIMD3<Float>
    public var velocity: SIMD3<Float>
    public var isGrounded: Bool
    public var wasGrounded: Bool
    public var groundHeight: Float
    public var landingTimer: Float

    public init(position: SIMD3<Float>) {
        self.position = position
        self.velocity = .zero
        self.isGrounded = true
        self.wasGrounded = true
        self.groundHeight = position.y
        self.landingTimer = 0.0
    }
}

public final class PhysicsWorld {
    public let gravity: Float = -24.0
    public let groundAcceleration: Float = 36.0
    public let airAcceleration: Float = 12.0
    public let groundFriction: Float = 11.5
    public let airDrag: Float = 1.4
    public let jumpVelocity: Float = 9.2
    public let waterFloorY: Float = -0.35

    private let collisionWorld: CollisionWorld
    private let chunkSize: Float

    public init(collisionWorld: CollisionWorld, chunkSize: Float) {
        self.collisionWorld = collisionWorld
        self.chunkSize = chunkSize
    }

    public func stepCharacter(
        state: inout CharacterPhysicsState,
        desiredHorizontalVelocity: SIMD3<Float>,
        jumpRequested: Bool,
        radius: Float,
        height: Float,
        dt: Float
    ) {
        state.wasGrounded = state.isGrounded
        if state.landingTimer > 0 {
            state.landingTimer = max(0, state.landingTimer - dt)
        }

        // Horizontal acceleration and friction
        let horizVel = SIMD3<Float>(state.velocity.x, 0, state.velocity.z)
        let accel = state.isGrounded ? groundAcceleration : airAcceleration
        let friction = state.isGrounded ? groundFriction : airDrag

        if simd_length_squared(desiredHorizontalVelocity) > 0.001 {
            let delta = desiredHorizontalVelocity - horizVel
            let maxChange = accel * dt
            let deltaLen = simd_length(delta)
            if deltaLen <= maxChange {
                state.velocity.x = desiredHorizontalVelocity.x
                state.velocity.z = desiredHorizontalVelocity.z
            } else {
                let step = (delta / deltaLen) * maxChange
                state.velocity.x += step.x
                state.velocity.z += step.z
            }
        } else {
            let damping = exp(-friction * dt)
            state.velocity.x *= damping
            state.velocity.z *= damping
            if abs(state.velocity.x) < 0.02 { state.velocity.x = 0 }
            if abs(state.velocity.z) < 0.02 { state.velocity.z = 0 }
        }

        // Jump impulse
        if jumpRequested && state.isGrounded {
            state.velocity.y = jumpVelocity
            state.isGrounded = false
        }

        // Gravity
        state.velocity.y += gravity * dt
        state.velocity.y = max(state.velocity.y, -42.0)

        // Sub-stepped integration to prevent tunneling on thin walls or high vertical speed
        let subSteps = 2
        let subDt = dt / Float(subSteps)
        var stoodOnCollider = false

        for _ in 0..<subSteps {
            state.position += state.velocity * subDt
            let onBox = collisionWorld.resolveCharacterCollisions(
                position: &state.position,
                velocity: &state.velocity,
                radius: radius,
                height: height,
                chunkSize: chunkSize
            )
            if onBox {
                stoodOnCollider = true
            }
        }

        // Ground detection against Terrain Mesh and shallow water floor
        let rawTerrainY = collisionWorld.terrainHeight(at: state.position.x, z: state.position.z)
        let effectiveFloorY = max(rawTerrainY, waterFloorY)
        state.groundHeight = effectiveFloorY

        if stoodOnCollider {
            state.isGrounded = true
        } else if state.position.y <= effectiveFloorY + 0.03 && state.velocity.y <= 0.1 {
            state.position.y = effectiveFloorY
            state.velocity.y = 0.0
            state.isGrounded = true
        } else {
            state.isGrounded = false
        }

        // Landing feedback window
        if !state.wasGrounded && state.isGrounded {
            state.landingTimer = 0.18
        }
    }
}
