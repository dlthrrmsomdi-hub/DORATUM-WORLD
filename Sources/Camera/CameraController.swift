import Foundation
import simd

public final class CameraController {
    public var yaw: Float = 0.0
    public var pitch: Float = 0.28
    public var targetDistance: Float = 7.5
    public private(set) var currentDistance: Float = 7.5
    public var cameraHeightOffset: Float = 1.65
    public var smoothingSpeed: Float = 11.0
    public var fieldOfViewDegrees: Float = 62.0
    public var nearPlane: Float = 0.18
    public var farPlane: Float = 450.0

    public private(set) var position: SIMD3<Float> = SIMD3<Float>(0, 4, 26)
    public private(set) var targetPosition: SIMD3<Float> = SIMD3<Float>(0, 2, 18)

    private let minPitch: Float = -0.30
    private let maxPitch: Float = 1.12
    private let minDistance: Float = 3.2
    private let maxDistance: Float = 15.0

    private let collisionWorld: CollisionWorld
    private let chunkSize: Float

    public init(collisionWorld: CollisionWorld, chunkSize: Float) {
        self.collisionWorld = collisionWorld
        self.chunkSize = chunkSize
    }

    public func configure(yaw: Float, pitch: Float, distance: Float, focusPoint: SIMD3<Float>) {
        self.yaw = yaw
        self.pitch = Math3D.clamp(pitch, min: minPitch, max: maxPitch)
        self.targetDistance = Math3D.clamp(distance, min: minDistance, max: maxDistance)
        self.currentDistance = self.targetDistance
        self.targetPosition = focusPoint + SIMD3<Float>(0, cameraHeightOffset, 0)
        self.position = computeIdealCameraPosition(focus: targetPosition, dist: currentDistance)
    }

    public func resetBehind(playerYaw: Float) {
        // Player faces (sin(yaw), cos(yaw)), camera looks from behind player
        self.yaw = playerYaw + .pi
        self.pitch = 0.28
        self.targetDistance = 7.5
    }

    public func update(
        dt: Float,
        playerPosition: SIMD3<Float>,
        playerYaw: Float,
        cameraDelta: SIMD2<Float>,
        zoomDelta: Float,
        resetTriggered: Bool,
        sensitivity: Float,
        renderDistance: Float
    ) {
        if resetTriggered {
            resetBehind(playerYaw: playerYaw)
        }

        let rotScale: Float = 0.0062 * sensitivity
        yaw -= cameraDelta.x * rotScale
        pitch = Math3D.clamp(pitch + cameraDelta.y * rotScale, min: minPitch, max: maxPitch)

        if abs(zoomDelta) > 0.0001 {
            targetDistance = Math3D.clamp(targetDistance - zoomDelta * 4.5, min: minDistance, max: maxDistance)
        }

        farPlane = max(180.0, renderDistance + 120.0)

        let desiredFocus = playerPosition + SIMD3<Float>(0, cameraHeightOffset, 0)
        let focusBlend = Math3D.clamp(1.0 - exp(-smoothingSpeed * dt), min: 0.05, max: 1.0)
        targetPosition = simd_mix(targetPosition, desiredFocus, SIMD3<Float>(repeating: focusBlend))

        // Raycast from focus toward ideal camera offset to prevent clipping into buildings
        let idealPos = computeIdealCameraPosition(focus: targetPosition, dist: targetDistance)
        let rayVec = idealPos - targetPosition
        let rayLen = simd_length(rayVec)

        var safeDistance = targetDistance
        if rayLen > 0.01 {
            let hitDist = collisionWorld.raycastDistance(
                origin: targetPosition,
                direction: rayVec / rayLen,
                maxDistance: targetDistance,
                chunkSize: chunkSize
            )
            if hitDist < targetDistance {
                safeDistance = max(minDistance * 0.65, hitDist - 0.45)
            }
        }

        let distBlend = safeDistance < currentDistance ? 0.55 : Math3D.clamp(dt * 8.0, min: 0.05, max: 1.0)
        currentDistance = Math3D.lerp(currentDistance, safeDistance, distBlend)

        var resolvedPos = computeIdealCameraPosition(focus: targetPosition, dist: currentDistance)

        // Keep camera safely above terrain surface
        let terrainY = collisionWorld.terrainHeight(at: resolvedPos.x, z: resolvedPos.z)
        let minAllowedY = max(terrainY, 0.0) + 0.65
        if resolvedPos.y < minAllowedY {
            resolvedPos.y = minAllowedY
        }

        let posBlend = Math3D.clamp(1.0 - exp(-(smoothingSpeed + 2.0) * dt), min: 0.08, max: 1.0)
        position = simd_mix(position, resolvedPos, SIMD3<Float>(repeating: posBlend))
    }

    private func computeIdealCameraPosition(focus: SIMD3<Float>, dist: Float) -> SIMD3<Float> {
        let cosPitch = cos(pitch)
        let offset = SIMD3<Float>(
            sin(yaw) * cosPitch * dist,
            sin(pitch) * dist,
            cos(yaw) * cosPitch * dist
        )
        return focus + offset
    }

    public func viewMatrix() -> simd_float4x4 {
        Math3D.lookAtRH(eye: position, target: targetPosition, up: SIMD3<Float>(0, 1, 0))
    }

    public func projectionMatrix(aspectRatio: Float) -> simd_float4x4 {
        Math3D.perspectiveRH(
            fovYRadians: fieldOfViewDegrees * (.pi / 180.0),
            aspect: aspectRatio,
            nearZ: nearPlane,
            farZ: farPlane
        )
    }

    public func viewProjectionMatrix(aspectRatio: Float) -> simd_float4x4 {
        projectionMatrix(aspectRatio: aspectRatio) * viewMatrix()
    }
}
