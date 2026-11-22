import Foundation
import simd

public enum DistrictType: String {
    case downtown = "Downtown"
    case residential = "Residential District"
    case coastal = "Coastal Area"
    case park = "Park Area"
    case ocean = "Doratum Bay Ocean"
}

public struct SeededRandom {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func nextFloat() -> Float {
        let v = nextUInt64() >> 40
        return Float(v) / Float(1 << 24)
    }

    public mutating func range(_ minVal: Float, _ maxVal: Float) -> Float {
        minVal + (maxVal - minVal) * nextFloat()
    }

    public mutating func intRange(_ minVal: Int, _ maxVal: Int) -> Int {
        guard maxVal > minVal else { return minVal }
        let span = UInt64(maxVal - minVal + 1)
        return minVal + Int(nextUInt64() % span)
    }
}

public struct GeneratedChunkContent {
    public let coord: ChunkCoord
    public let terrainMesh: MeshData
    public let structuresMesh: MeshData
    public let roadMesh: MeshData
    public let treeInstancesByStyle: [[InstanceData]] // 0: broadleaf, 1: pine, 2: palm
    public let rockInstances: [InstanceData]
    public let colliders: [ColliderBox]
    public let worldBounds: AABB
}

public final class WorldGenerator {
    public let worldSeed: UInt64
    public let chunkSize: Float = 64.0
    public let worldHalfExtent: Float = 360.0
    public let roadSpacing: Float = 64.0
    public let roadHalfWidth: Float = 5.4
    public let sidewalkWidth: Float = 2.6

    private let meshFactory: MeshFactory
    private let materialSystem: MaterialSystem

    public init(seed: UInt64 = 20260719, meshFactory: MeshFactory, materialSystem: MaterialSystem) {
        self.worldSeed = seed
        self.meshFactory = meshFactory
        self.materialSystem = materialSystem
    }

    // MARK: - Deterministic Noise & Terrain Height

    private func hash2D(_ ix: Int, _ iz: Int) -> Float {
        var h = UInt64(bitPattern: Int64(ix)) &* 374761393
        h ^= UInt64(bitPattern: Int64(iz)) &* 668265263
        h ^= worldSeed
        h = (h ^ (h >> 13)) &* 1274126177
        return Float((h ^ (h >> 16)) & 0xFFFF) / 65535.0
    }

    private func valueNoise(_ x: Float, _ z: Float) -> Float {
        let fx = floor(x)
        let fz = floor(z)
        let ix = Int(fx)
        let iz = Int(fz)
        let tx = x - fx
        let tz = z - fz
        let ux = tx * tx * (3.0 - 2.0 * tx)
        let uz = tz * tz * (3.0 - 2.0 * tz)

        let a = hash2D(ix, iz)
        let b = hash2D(ix + 1, iz)
        let c = hash2D(ix, iz + 1)
        let d = hash2D(ix + 1, iz + 1)
        return Math3D.lerp(Math3D.lerp(a, b, ux), Math3D.lerp(c, d, ux), uz)
    }

    private func fbm(_ x: Float, _ z: Float) -> Float {
        var sum: Float = 0
        var amp: Float = 0.5
        var freq: Float = 1.0
        for _ in 0..<3 {
            sum += valueNoise(x * freq, z * freq) * amp
            freq *= 2.05
            amp *= 0.5
        }
        return sum
    }

    public func district(at x: Float, z: Float) -> DistrictType {
        if x > 142.0 {
            return .ocean
        }
        if x > 92.0 {
            return .coastal
        }
        if x < -84.0 && z < 68.0 {
            return .park
        }
        if z > 84.0 || (x < -84.0 && z >= 68.0) {
            return .residential
        }
        return .downtown
    }

    public func isOnRoadOrSidewalk(x: Float, z: Float) -> Bool {
        if x > 102.0 || (x < -86.0 && z < 66.0) {
            return false
        }
        let distX = abs((x + roadSpacing * 0.5).truncatingRemainder(dividingBy: roadSpacing))
        let modX = min(distX, roadSpacing - distX)
        let distZ = abs((z + roadSpacing * 0.5).truncatingRemainder(dividingBy: roadSpacing))
        let modZ = min(distZ, roadSpacing - distZ)
        let threshold = roadHalfWidth + sidewalkWidth
        return modX < threshold || modZ < threshold
    }

    public func terrainHeight(at x: Float, z: Float) -> Float {
        // Coastal slope toward Doratum Bay on the +X side
        if x > 86.0 {
            let t = Math3D.clamp((x - 86.0) / 62.0, min: 0.0, max: 1.0)
            let beachCurve = Math3D.lerp(2.2, -3.4, t * t * (3.0 - 2.0 * t))
            let ripple = (fbm(x * 0.025, z * 0.025) - 0.5) * 0.65
            return beachCurve + ripple
        }

        // Park rolling hills on the -X / north side
        if x < -84.0 && z < 68.0 {
            let edgeBlend = Math3D.clamp((-84.0 - x) / 36.0, min: 0.0, max: 1.0)
            let hill = (fbm(x * 0.018, z * 0.018) - 0.35) * 6.8 * edgeBlend
            return 2.2 + max(-0.4, hill)
        }

        // Residential gentle terrace
        if z > 84.0 {
            let edgeBlend = Math3D.clamp((z - 84.0) / 40.0, min: 0.0, max: 1.0)
            let gentle = (fbm(x * 0.014, z * 0.014) - 0.45) * 2.2 * edgeBlend
            return 2.2 + gentle
        }

        // Flat urban Downtown plateau for crisp roads & plazas
        return 2.2
    }

    public func terrainColor(at x: Float, z: Float, height: Float) -> SIMD4<Float> {
        let d = district(at: x, z: z)
        if height < 0.85 || d == .ocean {
            return SIMD4<Float>(0.76, 0.69, 0.52, 1.0) // wet/submerged sand
        }
        if d == .coastal {
            if x < 104.0 {
                return SIMD4<Float>(0.72, 0.71, 0.68, 1.0) // seaside boardwalk stone
            }
            return materialSystem.material(for: .sand).baseColor
        }
        if d == .park {
            let tint = (fbm(x * 0.06, z * 0.06) - 0.5) * 0.12
            return SIMD4<Float>(0.22 + tint * 0.4, 0.56 + tint, 0.24 + tint * 0.3, 1.0)
        }
        if d == .residential {
            let tint = (fbm(x * 0.05, z * 0.05) - 0.5) * 0.08
            return SIMD4<Float>(0.29 + tint, 0.54 + tint, 0.29 + tint, 1.0)
        }
        // Downtown concrete/plaza ground
        if abs(x) < 26.0 && abs(z) < 26.0 {
            return SIMD4<Float>(0.68, 0.70, 0.73, 1.0) // Downtown central plaza stone
        }
        return SIMD4<Float>(0.58, 0.60, 0.63, 1.0)
    }

    // MARK: - Chunk Generation

    public func generateChunk(coord: ChunkCoord, terrainSubdivisions: Int) -> GeneratedChunkContent {
        let originX = Float(coord.x) * chunkSize
        let originZ = Float(coord.z) * chunkSize

        let chunkSeed = worldSeed
            ^ (UInt64(bitPattern: Int64(coord.x)) &* 0x517CC1B727220A95)
            ^ (UInt64(bitPattern: Int64(coord.z)) &* 0x94D049BB133111EB)
        var rng = SeededRandom(seed: chunkSeed)

        let terrainMesh = meshFactory.makeTerrainChunkMesh(
            originX: originX,
            originZ: originZ,
            chunkSize: chunkSize,
            gridResolution: terrainSubdivisions,
            heightSampler: { [weak self] wx, wz in
                self?.terrainHeight(at: wx, z: wz) ?? 0.0
            },
            colorSampler: { [weak self] wx, wz, h in
                self?.terrainColor(at: wx, z: wz, height: h) ?? SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
            }
        )

        var structVerts: [Vertex] = []
        var structIndices: [UInt32] = []
        var roadVerts: [Vertex] = []
        var roadIndices: [UInt32] = []
        var colliders: [ColliderBox] = []
        var treesByStyle: [[InstanceData]] = [[], [], []]
        var rocks: [InstanceData] = []

        let centerX = originX + chunkSize * 0.5
        let centerZ = originZ + chunkSize * 0.5
        let primaryDistrict = district(at: centerX, z: centerZ)

        // 1. Roads, Sidewalks, Lane Markings, Intersections
        if primaryDistrict == .downtown || primaryDistrict == .residential {
            buildChunkRoads(
                originX: originX,
                originZ: originZ,
                into: &roadVerts,
                indices: &roadIndices
            )
        } else if primaryDistrict == .coastal && originX < 120.0 {
            // Coastal promenade boardwalk along X ~ 98
            let boardX: Float = 98.0
            if boardX >= originX && boardX <= originX + chunkSize {
                let y = terrainHeight(at: boardX, z: centerZ) + 0.14
                MeshFactory.appendBox(
                    into: &roadVerts,
                    indices: &roadIndices,
                    center: SIMD3<Float>(boardX, y, centerZ),
                    size: SIMD3<Float>(6.5, 0.28, chunkSize),
                    color: SIMD4<Float>(0.58, 0.45, 0.32, 1.0)
                )
            }
        }

        // 2. Central Plaza Monument in Spawn Chunk (0, 0)
        if coord.x == 0 && coord.z == 0 {
            buildDowntownPlazaLandmark(into: &structVerts, indices: &structIndices, colliders: &colliders)
        }

        // 3. District-Specific Procedural Buildings, Trees, and Rocks
        switch primaryDistrict {
        case .downtown:
            populateDowntownChunk(
                coord: coord,
                originX: originX,
                originZ: originZ,
                rng: &rng,
                vertices: &structVerts,
                indices: &structIndices,
                colliders: &colliders,
                treesByStyle: &treesByStyle
            )

        case .residential:
            populateResidentialChunk(
                originX: originX,
                originZ: originZ,
                rng: &rng,
                vertices: &structVerts,
                indices: &structIndices,
                colliders: &colliders,
                treesByStyle: &treesByStyle
            )

        case .park:
            populateParkChunk(
                originX: originX,
                originZ: originZ,
                rng: &rng,
                vertices: &structVerts,
                indices: &structIndices,
                colliders: &colliders,
                treesByStyle: &treesByStyle,
                rocks: &rocks
            )

        case .coastal:
            populateCoastalChunk(
                originX: originX,
                originZ: originZ,
                rng: &rng,
                colliders: &colliders,
                treesByStyle: &treesByStyle,
                rocks: &rocks
            )

        case .ocean:
            break
        }

        let structuresMesh = MeshData(vertices: structVerts, indices: structIndices)
        let roadMesh = MeshData(vertices: roadVerts, indices: roadIndices)
        let bounds = AABB(
            min: SIMD3<Float>(originX, -6.0, originZ),
            max: SIMD3<Float>(originX + chunkSize, 65.0, originZ + chunkSize)
        )

        return GeneratedChunkContent(
            coord: coord,
            terrainMesh: terrainMesh,
            structuresMesh: structuresMesh,
            roadMesh: roadMesh,
            treeInstancesByStyle: treesByStyle,
            rockInstances: rocks,
            colliders: colliders,
            worldBounds: bounds
        )
    }

    // MARK: - Road Network Builder

    private func buildChunkRoads(
        originX: Float,
        originZ: Float,
        into vertices: inout [Vertex],
        indices: inout [UInt32]
    ) {
        let asphalt = materialSystem.material(for: .asphalt).baseColor
        let sidewalk = SIMD4<Float>(0.73, 0.74, 0.76, 1.0)
        let curb = SIMD4<Float>(0.62, 0.63, 0.66, 1.0)
        let yellowLine = SIMD4<Float>(0.94, 0.78, 0.22, 1.0)
        let whiteLine = SIMD4<Float>(0.92, 0.93, 0.95, 1.0)

        let roadCenterX = originX + chunkSize * 0.5
        let roadCenterZ = originZ + chunkSize * 0.5
        let roadY = terrainHeight(at: roadCenterX, z: roadCenterZ) + 0.06

        // North-South Avenue along chunk center X
        MeshFactory.appendBox(
            into: &vertices, indices: &indices,
            center: SIMD3<Float>(roadCenterX, roadY, roadCenterZ),
            size: SIMD3<Float>(roadHalfWidth * 2.0, 0.12, chunkSize),
            color: asphalt
        )
        // East-West Avenue along chunk center Z
        MeshFactory.appendBox(
            into: &vertices, indices: &indices,
            center: SIMD3<Float>(roadCenterX, roadY + 0.005, roadCenterZ),
            size: SIMD3<Float>(chunkSize, 0.12, roadHalfWidth * 2.0),
            color: asphalt
        )

        // Sidewalks & Curbs flanking both avenues
        let swOffset = roadHalfWidth + sidewalkWidth * 0.5
        let segLen = (chunkSize * 0.5) - roadHalfWidth
        let segCenterOffset = roadHalfWidth + segLen * 0.5

        for side in [-1.0 as Float, 1.0 as Float] {
            for half in [-1.0 as Float, 1.0 as Float] {
                // Along Z
                MeshFactory.appendBox(
                    into: &vertices, indices: &indices,
                    center: SIMD3<Float>(roadCenterX + side * swOffset, roadY + 0.10, roadCenterZ + half * segCenterOffset),
                    size: SIMD3<Float>(sidewalkWidth, 0.22, segLen),
                    color: sidewalk
                )
                MeshFactory.appendBox(
                    into: &vertices, indices: &indices,
                    center: SIMD3<Float>(roadCenterX + side * (roadHalfWidth + 0.16), roadY + 0.12, roadCenterZ + half * segCenterOffset),
                    size: SIMD3<Float>(0.32, 0.24, segLen),
                    color: curb
                )
                // Along X
                MeshFactory.appendBox(
                    into: &vertices, indices: &indices,
                    center: SIMD3<Float>(roadCenterX + half * segCenterOffset, roadY + 0.10, roadCenterZ + side * swOffset),
                    size: SIMD3<Float>(segLen, 0.22, sidewalkWidth),
                    color: sidewalk
                )
                MeshFactory.appendBox(
                    into: &vertices, indices: &indices,
                    center: SIMD3<Float>(roadCenterX + half * segCenterOffset, roadY + 0.12, roadCenterZ + side * (roadHalfWidth + 0.16)),
                    size: SIMD3<Float>(segLen, 0.24, 0.32),
                    color: curb
                )
            }
        }

        // Dashed center lane markings
        for i in 0..<4 {
            let offset = roadHalfWidth + 3.2 + Float(i) * 6.0
            if offset + 2.0 < chunkSize * 0.5 {
                for dir in [-1.0 as Float, 1.0 as Float] {
                    MeshFactory.appendBox(
                        into: &vertices, indices: &indices,
                        center: SIMD3<Float>(roadCenterX, roadY + 0.08, roadCenterZ + dir * offset),
                        size: SIMD3<Float>(0.24, 0.03, 3.0),
                        color: yellowLine
                    )
                    MeshFactory.appendBox(
                        into: &vertices, indices: &indices,
                        center: SIMD3<Float>(roadCenterX + dir * offset, roadY + 0.08, roadCenterZ),
                        size: SIMD3<Float>(3.0, 0.03, 0.24),
                        color: yellowLine
                    )
                }
            }
        }

        // Intersection crosswalk stripes
        for stripe in -2...2 {
            let sOff = Float(stripe) * 1.65
            for dir in [-1.0 as Float, 1.0 as Float] {
                MeshFactory.appendBox(
                    into: &vertices, indices: &indices,
                    center: SIMD3<Float>(roadCenterX + sOff, roadY + 0.08, roadCenterZ + dir * (roadHalfWidth + 1.1)),
                    size: SIMD3<Float>(0.75, 0.03, 1.6),
                    color: whiteLine
                )
                MeshFactory.appendBox(
                    into: &vertices, indices: &indices,
                    center: SIMD3<Float>(roadCenterX + dir * (roadHalfWidth + 1.1), roadY + 0.08, roadCenterZ + sOff),
                    size: SIMD3<Float>(1.6, 0.03, 0.75),
                    color: whiteLine
                )
            }
        }
    }

    // MARK: - Downtown Plaza Landmark

    private func buildDowntownPlazaLandmark(
        into vertices: inout [Vertex],
        indices: inout [UInt32],
        colliders: inout [ColliderBox]
    ) {
        let baseX: Float = 0.0
        let baseZ: Float = 0.0
        let y = terrainHeight(at: baseX, z: baseZ)

        // Stepped stone pedestal
        MeshFactory.appendBox(
            into: &vertices, indices: &indices,
            center: SIMD3<Float>(baseX, y + 0.3, baseZ),
            size: SIMD3<Float>(8.0, 0.6, 8.0),
            color: SIMD4<Float>(0.76, 0.78, 0.82, 1.0)
        )
        // Blue glass fountain basin
        MeshFactory.appendBox(
            into: &vertices, indices: &indices,
            center: SIMD3<Float>(baseX, y + 0.75, baseZ),
            size: SIMD3<Float>(5.6, 0.4, 5.6),
            color: SIMD4<Float>(0.18, 0.56, 0.84, 1.0)
        )
        // Central metallic spire
        MeshFactory.appendCylinder(
            into: &vertices, indices: &indices,
            baseCenter: SIMD3<Float>(baseX, y + 0.9, baseZ),
            bottomRadius: 0.9,
            topRadius: 0.18,
            height: 7.5,
            segments: 8,
            color: SIMD4<Float>(0.24, 0.52, 0.88, 1.0)
        )

        colliders.append(ColliderBox(
            bounds: AABB(
                min: SIMD3<Float>(baseX - 2.8, y, baseZ - 2.8),
                max: SIMD3<Float>(baseX + 2.8, y + 8.5, baseZ + 2.8)
            ),
            category: .prop
        ))
    }

    // MARK: - Building Generator (Varied Shapes, Windows, Doors, Roofs)

    private func appendProceduralBuilding(
        center: SIMD3<Float>,
        width: Float,
        depth: Float,
        height: Float,
        isTower: Bool,
        rng: inout SeededRandom,
        into vertices: inout [Vertex],
        indices: inout [UInt32],
        colliders: inout [ColliderBox]
    ) {
        let wallPalettes: [SIMD4<Float>] = isTower ? [
            SIMD4<Float>(0.68, 0.72, 0.78, 1.0),
            SIMD4<Float>(0.54, 0.60, 0.68, 1.0),
            SIMD4<Float>(0.76, 0.75, 0.72, 1.0),
            SIMD4<Float>(0.44, 0.52, 0.64, 1.0),
            SIMD4<Float>(0.78, 0.72, 0.64, 1.0)
        ] : [
            SIMD4<Float>(0.86, 0.82, 0.74, 1.0),
            SIMD4<Float>(0.80, 0.74, 0.66, 1.0),
            SIMD4<Float>(0.74, 0.80, 0.82, 1.0),
            SIMD4<Float>(0.84, 0.76, 0.72, 1.0),
            SIMD4<Float>(0.88, 0.86, 0.82, 1.0)
        ]
        let wallColor = wallPalettes[rng.intRange(0, wallPalettes.count - 1)]
        let windowColor = isTower
            ? SIMD4<Float>(0.26, 0.48, 0.70, 1.0)
            : SIMD4<Float>(0.34, 0.56, 0.74, 1.0)
        let doorColor = SIMD4<Float>(0.32, 0.20, 0.13, 1.0)
        let roofColor = isTower
            ? SIMD4<Float>(0.34, 0.37, 0.42, 1.0)
            : SIMD4<Float>(0.58, 0.28, 0.22, 1.0)

        // Main building mass
        MeshFactory.appendBox(
            into: &vertices, indices: &indices,
            center: SIMD3<Float>(center.x, center.y + height * 0.5, center.z),
            size: SIMD3<Float>(width, height, depth),
            color: wallColor
        )

        // Door on front (+Z) face
        MeshFactory.appendBox(
            into: &vertices, indices: &indices,
            center: SIMD3<Float>(center.x, center.y + 1.25, center.z + depth * 0.5 + 0.06),
            size: SIMD3<Float>(min(2.2, width * 0.25), 2.5, 0.14),
            color: doorColor
        )

        // Window bands across floors
        let floorHeight: Float = isTower ? 3.8 : 3.2
        let floorCount = max(1, Int((height - 2.6) / floorHeight))
        for f in 0..<floorCount {
            let wy = center.y + 3.2 + Float(f) * floorHeight
            if wy + 0.9 > center.y + height { break }
            // Front & Back glass ribbon
            MeshFactory.appendBox(
                into: &vertices, indices: &indices,
                center: SIMD3<Float>(center.x, wy, center.z),
                size: SIMD3<Float>(width * 0.82, 1.35, depth + 0.12),
                color: windowColor
            )
            // Left & Right glass ribbon
            MeshFactory.appendBox(
                into: &vertices, indices: &indices,
                center: SIMD3<Float>(center.x, wy, center.z),
                size: SIMD3<Float>(width + 0.12, 1.35, depth * 0.82),
                color: windowColor
            )
        }

        // Roof architectural variation
        if isTower {
            // Parapet cornice
            MeshFactory.appendBox(
                into: &vertices, indices: &indices,
                center: SIMD3<Float>(center.x, center.y + height + 0.35, center.z),
                size: SIMD3<Float>(width + 0.45, 0.7, depth + 0.45),
                color: roofColor
            )
            // Optional stepped upper penthouse tier
            if height > 18.0 && rng.nextFloat() > 0.35 {
                let topW = width * 0.62
                let topD = depth * 0.62
                let topH = rng.range(4.0, 9.0)
                MeshFactory.appendBox(
                    into: &vertices, indices: &indices,
                    center: SIMD3<Float>(center.x, center.y + height + topH * 0.5, center.z),
                    size: SIMD3<Float>(topW, topH, topD),
                    color: SIMD4<Float>(wallColor.x * 0.92, wallColor.y * 0.94, wallColor.z * 0.98, 1.0)
                )
                // Rooftop antenna
                MeshFactory.appendCylinder(
                    into: &vertices, indices: &indices,
                    baseCenter: SIMD3<Float>(center.x, center.y + height + topH, center.z),
                    bottomRadius: 0.14,
                    topRadius: 0.04,
                    height: 4.5,
                    segments: 5,
                    color: SIMD4<Float>(0.78, 0.80, 0.84, 1.0)
                )
            }
        } else {
            // Pitched residential roof
            MeshFactory.appendPitchedRoof(
                into: &vertices, indices: &indices,
                baseCenter: SIMD3<Float>(center.x, center.y + height, center.z),
                width: width + 0.8,
                depth: depth + 0.8,
                height: rng.range(2.2, 3.8),
                color: roofColor
            )
        }

        colliders.append(ColliderBox(
            bounds: AABB(
                min: SIMD3<Float>(center.x - width * 0.5, center.y, center.z - depth * 0.5),
                max: SIMD3<Float>(center.x + width * 0.5, center.y + height, center.z + depth * 0.5)
            ),
            category: .building
        ))
    }

    // MARK: - District Populators

    private func populateDowntownChunk(
        coord: ChunkCoord,
        originX: Float,
        originZ: Float,
        rng: inout SeededRandom,
        vertices: inout [Vertex],
        indices: inout [UInt32],
        colliders: inout [ColliderBox],
        treesByStyle: inout [[InstanceData]]
    ) {
        let quadrants: [(Float, Float)] = [
            (originX + 15.0, originZ + 15.0),
            (originX + 49.0, originZ + 15.0),
            (originX + 15.0, originZ + 49.0),
            (originX + 49.0, originZ + 49.0)
        ]

        for (qx, qz) in quadrants {
            // Keep immediate central plaza open around spawn
            if coord.x == 0 && coord.z == 0 && hypot(qx, qz) < 28.0 {
                continue
            }

            let y = terrainHeight(at: qx, z: qz)
            let w = rng.range(10.5, 16.0)
            let d = rng.range(10.5, 16.0)
            let distFromCore = hypot(qx, qz)
            let h = distFromCore < 70.0 ? rng.range(18.0, 42.0) : rng.range(11.0, 24.0)

            appendProceduralBuilding(
                center: SIMD3<Float>(qx, y, qz),
                width: w,
                depth: d,
                height: h,
                isTower: true,
                rng: &rng,
                into: &vertices,
                indices: &indices,
                colliders: &colliders
            )

            // Street-side decorative tree
            let tx = qx + (qx < originX + 32 ? 9.5 : -9.5)
            let tz = qz + (qz < originZ + 32 ? 9.5 : -9.5)
            if !isOnRoadOrSidewalk(x: tx, z: tz) {
                addTreeInstance(at: SIMD3<Float>(tx, terrainHeight(at: tx, z: tz), tz), style: 0, scale: rng.range(0.85, 1.15), rng: &rng, treesByStyle: &treesByStyle, colliders: &colliders)
            }
        }
    }

    private func populateResidentialChunk(
        originX: Float,
        originZ: Float,
        rng: inout SeededRandom,
        vertices: inout [Vertex],
        indices: inout [UInt32],
        colliders: inout [ColliderBox],
        treesByStyle: inout [[InstanceData]]
    ) {
        let lots: [(Float, Float)] = [
            (originX + 14.5, originZ + 14.5),
            (originX + 49.5, originZ + 14.5),
            (originX + 14.5, originZ + 49.5),
            (originX + 49.5, originZ + 49.5)
        ]

        for (lx, lz) in lots {
            let y = terrainHeight(at: lx, z: lz)
            if y < 0.8 { continue }
            let w = rng.range(8.0, 12.5)
            let d = rng.range(7.5, 11.5)
            let h = rng.range(4.5, 8.2)

            appendProceduralBuilding(
                center: SIMD3<Float>(lx, y, lz),
                width: w,
                depth: d,
                height: h,
                isTower: false,
                rng: &rng,
                into: &vertices,
                indices: &indices,
                colliders: &colliders
            )

            // Garden trees
            for _ in 0..<2 {
                let tx = lx + rng.range(-9.0, 9.0)
                let tz = lz + rng.range(-9.0, 9.0)
                if abs(tx - lx) < w * 0.65 && abs(tz - lz) < d * 0.65 { continue }
                if isOnRoadOrSidewalk(x: tx, z: tz) { continue }
                let ty = terrainHeight(at: tx, z: tz)
                addTreeInstance(at: SIMD3<Float>(tx, ty, tz), style: rng.intRange(0, 1), scale: rng.range(0.8, 1.25), rng: &rng, treesByStyle: &treesByStyle, colliders: &colliders)
            }
        }
    }

    private func populateParkChunk(
        originX: Float,
        originZ: Float,
        rng: inout SeededRandom,
        vertices: inout [Vertex],
        indices: inout [UInt32],
        colliders: inout [ColliderBox],
        treesByStyle: inout [[InstanceData]],
        rocks: inout [InstanceData]
    ) {
        // Walking path cross through park
        let cx = originX + chunkSize * 0.5
        let cz = originZ + chunkSize * 0.5
        let cy = terrainHeight(at: cx, z: cz)
        MeshFactory.appendBox(
            into: &vertices, indices: &indices,
            center: SIMD3<Float>(cx, cy + 0.08, cz),
            size: SIMD3<Float>(3.2, 0.14, chunkSize * 0.82),
            color: SIMD4<Float>(0.76, 0.72, 0.62, 1.0)
        )

        // Park trees
        let treeCount = rng.intRange(10, 16)
        for _ in 0..<treeCount {
            let tx = originX + rng.range(4.0, chunkSize - 4.0)
            let tz = originZ + rng.range(4.0, chunkSize - 4.0)
            if abs(tx - cx) < 3.0 { continue }
            let ty = terrainHeight(at: tx, z: tz)
            if ty < 0.8 { continue }
            addTreeInstance(at: SIMD3<Float>(tx, ty, tz), style: rng.intRange(0, 1), scale: rng.range(0.85, 1.45), rng: &rng, treesByStyle: &treesByStyle, colliders: &colliders)
        }

        // Decorative boulders
        let rockCount = rng.intRange(3, 6)
        for _ in 0..<rockCount {
            let rx = originX + rng.range(5.0, chunkSize - 5.0)
            let rz = originZ + rng.range(5.0, chunkSize - 5.0)
            let ry = terrainHeight(at: rx, z: rz)
            let s = rng.range(0.7, 1.6)
            let mat = Math3D.translation(SIMD3<Float>(rx, ry, rz))
                * Math3D.rotationY(rng.range(0, .pi * 2))
                * Math3D.scale(SIMD3<Float>(s, s * 0.8, s))
            rocks.append(InstanceData(modelMatrix: mat, tintColor: SIMD4<Float>(1, 1, 1, 1), materialParams: materialSystem.material(for: .concrete).materialParams))
            colliders.append(ColliderBox(
                bounds: AABB(min: SIMD3<Float>(rx - s, ry, rz - s), max: SIMD3<Float>(rx + s, ry + s * 1.1, rz + s)),
                category: .rock
            ))
        }
    }

    private func populateCoastalChunk(
        originX: Float,
        originZ: Float,
        rng: inout SeededRandom,
        colliders: inout [ColliderBox],
        treesByStyle: inout [[InstanceData]],
        rocks: inout [InstanceData]
    ) {
        // Palm trees along the upper beach
        let palmCount = rng.intRange(5, 9)
        for _ in 0..<palmCount {
            let tx = originX + rng.range(3.0, chunkSize - 3.0)
            let tz = originZ + rng.range(3.0, chunkSize - 3.0)
            let ty = terrainHeight(at: tx, z: tz)
            if ty < 0.65 || abs(tx - 98.0) < 4.5 { continue }
            addTreeInstance(at: SIMD3<Float>(tx, ty, tz), style: 2, scale: rng.range(0.9, 1.35), rng: &rng, treesByStyle: &treesByStyle, colliders: &colliders)
        }

        // Coastal rocks near shoreline
        let rockCount = rng.intRange(4, 8)
        for _ in 0..<rockCount {
            let rx = originX + rng.range(4.0, chunkSize - 4.0)
            let rz = originZ + rng.range(4.0, chunkSize - 4.0)
            let ry = terrainHeight(at: rx, z: rz)
            if ry < -0.5 || ry > 1.8 { continue }
            let s = rng.range(0.8, 1.8)
            let mat = Math3D.translation(SIMD3<Float>(rx, ry, rz))
                * Math3D.rotationY(rng.range(0, .pi * 2))
                * Math3D.scale(SIMD3<Float>(s, s * 0.75, s))
            rocks.append(InstanceData(modelMatrix: mat, tintColor: SIMD4<Float>(0.92, 0.90, 0.86, 1.0), materialParams: materialSystem.material(for: .concrete).materialParams))
            colliders.append(ColliderBox(
                bounds: AABB(min: SIMD3<Float>(rx - s, ry, rz - s), max: SIMD3<Float>(rx + s, ry + s, rz + s)),
                category: .rock
            ))
        }
    }

    private func addTreeInstance(
        at position: SIMD3<Float>,
        style: Int,
        scale: Float,
        rng: inout SeededRandom,
        treesByStyle: inout [[InstanceData]],
        colliders: inout [ColliderBox]
    ) {
        let clampedStyle = Math3D.clamp(style, min: 0, max: 2)
        let rot = rng.range(0, .pi * 2)
        let tintVar = rng.range(0.88, 1.12)
        let model = Math3D.translation(position)
            * Math3D.rotationY(rot)
            * Math3D.scale(SIMD3<Float>(repeating: scale))
        let inst = InstanceData(
            modelMatrix: model,
            tintColor: SIMD4<Float>(tintVar, min(1.15, tintVar * 1.02), tintVar * 0.96, 1.0),
            materialParams: materialSystem.material(for: .foliage).materialParams
        )
        treesByStyle[clampedStyle].append(inst)
        colliders.append(ColliderBox(
            bounds: AABB(
                min: SIMD3<Float>(position.x - 0.45 * scale, position.y, position.z - 0.45 * scale),
                max: SIMD3<Float>(position.x + 0.45 * scale, position.y + 4.2 * scale, position.z + 0.45 * scale)
            ),
            category: .tree
        ))
    }
}
