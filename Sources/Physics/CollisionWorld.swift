import Foundation
import simd

public struct ChunkCoord: Hashable, Codable {
    public let x: Int
    public let z: Int

    public init(x: Int, z: Int) {
        self.x = x
        self.z = z
    }
}

public enum ColliderCategory: String {
    case building
    case tree
    case rock
    case wall
    case prop
}

public struct ColliderBox {
    public let bounds: AABB
    public let category: ColliderCategory

    public init(bounds: AABB, category: ColliderCategory) {
        self.bounds = bounds
        self.category = category
    }
}

public final class CollisionWorld {
    private var chunkColliders: [ChunkCoord: [ColliderBox]] = [:]
    private let lock = NSLock()
    public var terrainHeightProvider: ((Float, Float) -> Float)?
    public var worldHalfExtent: Float = 360.0

    public init() {}

    public func setColliders(_ colliders: [ColliderBox], for chunk: ChunkCoord) {
        lock.lock()
        chunkColliders[chunk] = colliders
        lock.unlock()
    }

    public func removeColliders(for chunk: ChunkCoord) {
        lock.lock()
        chunkColliders.removeValue(forKey: chunk)
        lock.unlock()
    }

    public func clearAll() {
        lock.lock()
        chunkColliders.removeAll()
        lock.unlock()
    }

    public func terrainHeight(at x: Float, z: Float) -> Float {
        terrainHeightProvider?(x, z) ?? 0.0
    }

    /// Resolves a vertical capsule (approximated by cylinder radius + height) against nearby AABBs.
    public func resolveCharacterCollisions(
        position: inout SIMD3<Float>,
        velocity: inout SIMD3<Float>,
        radius: Float,
        height: Float,
        chunkSize: Float
    ) -> Bool {
        // Clamp to map boundaries
        let maxCoord = worldHalfExtent - radius - 1.0
        if position.x < -maxCoord {
            position.x = -maxCoord
            velocity.x = max(0, velocity.x)
        } else if position.x > maxCoord {
            position.x = maxCoord
            velocity.x = min(0, velocity.x)
        }
        if position.z < -maxCoord {
            position.z = -maxCoord
            velocity.z = max(0, velocity.z)
        } else if position.z > maxCoord {
            position.z = maxCoord
            velocity.z = min(0, velocity.z)
        }

        let centerChunkX = Int(floor(position.x / chunkSize))
        let centerChunkZ = Int(floor(position.z / chunkSize))

        var nearby: [ColliderBox] = []
        lock.lock()
        for dz in -1...1 {
            for dx in -1...1 {
                if let list = chunkColliders[ChunkCoord(x: centerChunkX + dx, z: centerChunkZ + dz)] {
                    nearby.append(contentsOf: list)
                }
            }
        }
        lock.unlock()

        var stoodOnCollider = false

        // Two solver iterations prevent corner tunneling
        for _ in 0..<2 {
            let charMinY = position.y
            let charMaxY = position.y + height

            for box in nearby {
                let bMin = box.bounds.min
                let bMax = box.bounds.max

                // Vertical overlap check
                if charMaxY <= bMin.y + 0.02 || charMinY >= bMax.y {
                    continue
                }

                // Closest point on AABB XZ to character center
                let closestX = Math3D.clamp(position.x, min: bMin.x, max: bMax.x)
                let closestZ = Math3D.clamp(position.z, min: bMin.z, max: bMax.z)
                let dx = position.x - closestX
                let dz = position.z - closestZ
                let distSq = dx * dx + dz * dz

                if distSq < radius * radius {
                    // Check if player can step onto top of low object (e.g. curb/platform)
                    let stepUpHeight = bMax.y - charMinY
                    if stepUpHeight > 0 && stepUpHeight <= 0.45 && velocity.y <= 0.1 {
                        position.y = bMax.y
                        velocity.y = 0
                        stoodOnCollider = true
                        continue
                    }

                    let dist = sqrt(distSq)
                    if dist > 0.0001 {
                        let push = radius - dist
                        let nx = dx / dist
                        let nz = dz / dist
                        position.x += nx * push
                        position.z += nz * push

                        let vn = velocity.x * nx + velocity.z * nz
                        if vn < 0 {
                            velocity.x -= vn * nx
                            velocity.z -= vn * nz
                        }
                    } else {
                        // Center is inside box; push out along shallowest axis
                        let penLeft = abs(position.x - bMin.x)
                        let penRight = abs(bMax.x - position.x)
                        let penBack = abs(position.z - bMin.z)
                        let penFront = abs(bMax.z - position.z)
                        let minPen = min(min(penLeft, penRight), min(penBack, penFront))

                        if minPen == penLeft {
                            position.x = bMin.x - radius
                            velocity.x = min(0, velocity.x)
                        } else if minPen == penRight {
                            position.x = bMax.x + radius
                            velocity.x = max(0, velocity.x)
                        } else if minPen == penBack {
                            position.z = bMin.z - radius
                            velocity.z = min(0, velocity.z)
                        } else {
                            position.z = bMax.z + radius
                            velocity.z = max(0, velocity.z)
                        }
                    }
                }
            }
        }

        return stoodOnCollider
    }

    /// Ray-AABB intersection used by CameraController to keep the camera outside buildings.
    public func raycastDistance(
        origin: SIMD3<Float>,
        direction: SIMD3<Float>,
        maxDistance: Float,
        chunkSize: Float
    ) -> Float {
        let dir = simd_normalize(direction)
        let invDir = SIMD3<Float>(
            abs(dir.x) > 1e-6 ? 1.0 / dir.x : 1e6,
            abs(dir.y) > 1e-6 ? 1.0 / dir.y : 1e6,
            abs(dir.z) > 1e-6 ? 1.0 / dir.z : 1e6
        )

        let midPoint = origin + dir * (maxDistance * 0.5)
        let cx = Int(floor(midPoint.x / chunkSize))
        let cz = Int(floor(midPoint.z / chunkSize))

        var candidates: [ColliderBox] = []
        lock.lock()
        for dz in -1...1 {
            for dx in -1...1 {
                if let list = chunkColliders[ChunkCoord(x: cx + dx, z: cz + dz)] {
                    candidates.append(contentsOf: list)
                }
            }
        }
        lock.unlock()

        var closestHit = maxDistance

        for box in candidates {
            let t1 = (box.bounds.min - origin) * invDir
            let t2 = (box.bounds.max - origin) * invDir
            let tMinVec = simd_min(t1, t2)
            let tMaxVec = simd_max(t1, t2)
            let tNear = max(max(tMinVec.x, tMinVec.y), tMinVec.z)
            let tFar = min(min(tMaxVec.x, tMaxVec.y), tMaxVec.z)

            if tFar >= max(tNear, 0.0) && tNear >= 0.0 && tNear < closestHit {
                closestHit = tNear
            }
        }

        return closestHit
    }
}
