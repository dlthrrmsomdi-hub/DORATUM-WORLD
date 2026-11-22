import Foundation
import Metal
import simd

public final class LoadedChunk {
    public let coord: ChunkCoord
    public let bounds: AABB
    public let terrainMesh: GPUMesh?
    public let structuresMesh: GPUMesh?
    public let roadMesh: GPUMesh?
    public let treeInstanceBuffers: [(style: Int, buffer: MTLBuffer, count: Int)]
    public let rockInstanceBuffer: (buffer: MTLBuffer, count: Int)?
    public let colliders: [ColliderBox]

    public init(device: MTLDevice, content: GeneratedChunkContent) {
        self.coord = content.coord
        self.bounds = content.worldBounds
        self.terrainMesh = GPUMesh(device: device, meshData: content.terrainMesh, label: "Terrain_\(content.coord.x)_\(content.coord.z)")
        self.structuresMesh = GPUMesh(device: device, meshData: content.structuresMesh, label: "Structs_\(content.coord.x)_\(content.coord.z)")
        self.roadMesh = GPUMesh(device: device, meshData: content.roadMesh, label: "Roads_\(content.coord.x)_\(content.coord.z)")
        self.colliders = content.colliders

        var treeBuffers: [(Int, MTLBuffer, Int)] = []
        for (styleIndex, list) in content.treeInstancesByStyle.enumerated() where !list.isEmpty {
            let bytes = list.count * MemoryLayout<InstanceData>.stride
            if let buf = device.makeBuffer(bytes: list, length: bytes, options: .storageModeShared) {
                buf.label = "Trees_\(styleIndex)_\(content.coord.x)_\(content.coord.z)"
                treeBuffers.append((styleIndex, buf, list.count))
            }
        }
        self.treeInstanceBuffers = treeBuffers

        if !content.rockInstances.isEmpty {
            let bytes = content.rockInstances.count * MemoryLayout<InstanceData>.stride
            if let buf = device.makeBuffer(bytes: content.rockInstances, length: bytes, options: .storageModeShared) {
                buf.label = "Rocks_\(content.coord.x)_\(content.coord.z)"
                self.rockInstanceBuffer = (buf, content.rockInstances.count)
            } else {
                self.rockInstanceBuffer = nil
            }
        } else {
            self.rockInstanceBuffer = nil
        }
    }
}

public final class ChunkManager {
    private let generator: WorldGenerator
    private let collisionWorld: CollisionWorld
    private var device: MTLDevice?

    private var activeChunks: [ChunkCoord: LoadedChunk] = [:]
    private var chunkCache: [ChunkCoord: LoadedChunk] = [:]
    private var cacheOrder: [ChunkCoord] = []
    private let maxCachedChunks = 48

    private var lastCenterChunk: ChunkCoord?
    private var currentTerrainSubdivisions: Int = 18

    public var chunkSize: Float { generator.chunkSize }

    public init(generator: WorldGenerator, collisionWorld: CollisionWorld) {
        self.generator = generator
        self.collisionWorld = collisionWorld
    }

    public func attachDevice(_ device: MTLDevice) {
        self.device = device
    }

    public func loadedChunks() -> [LoadedChunk] {
        Array(activeChunks.values)
    }

    public func chunkCoord(for worldPosition: SIMD3<Float>) -> ChunkCoord {
        ChunkCoord(
            x: Int(floor(worldPosition.x / chunkSize)),
            z: Int(floor(worldPosition.z / chunkSize))
        )
    }

    public func invalidateCache(newSubdivisions: Int) {
        guard newSubdivisions != currentTerrainSubdivisions else { return }
        currentTerrainSubdivisions = newSubdivisions
        activeChunks.removeAll()
        chunkCache.removeAll()
        cacheOrder.removeAll()
        collisionWorld.clearAll()
        lastCenterChunk = nil
    }

    /// Loads immediate spawn area synchronously so the player can play right away, then streams chunks as player moves.
    public func updateChunks(around playerPosition: SIMD3<Float>, quality: GraphicsQuality) {
        guard let device else { return }

        if quality.terrainSubdivisions != currentTerrainSubdivisions {
            invalidateCache(newSubdivisions: quality.terrainSubdivisions)
        }

        let center = chunkCoord(for: playerPosition)
        let radius = quality.chunkRadius

        // Skip work if player stayed in same chunk and all required chunks are already loaded
        if lastCenterChunk == center && activeChunks.count >= (radius * 2 + 1) * (radius * 2 + 1) {
            return
        }
        lastCenterChunk = center

        var desired = Set<ChunkCoord>()
        let maxChunkIndex = Int(ceil(generator.worldHalfExtent / chunkSize))

        for dz in -radius...radius {
            for dx in -radius...radius {
                let coord = ChunkCoord(x: center.x + dx, z: center.z + dz)
                if abs(coord.x) <= maxChunkIndex && abs(coord.z) <= maxChunkIndex {
                    desired.insert(coord)
                }
            }
        }

        // Unload distant chunks from active scene & collision world
        for (coord, _) in activeChunks where !desired.contains(coord) {
            activeChunks.removeValue(forKey: coord)
            collisionWorld.removeColliders(for: coord)
        }

        // Load or restore needed chunks from cache (preventing duplicate generation)
        for coord in desired where activeChunks[coord] == nil {
            if let cached = chunkCache[coord] {
                activeChunks[coord] = cached
                collisionWorld.setColliders(cached.colliders, for: coord)
            } else {
                let content = generator.generateChunk(coord: coord, terrainSubdivisions: currentTerrainSubdivisions)
                let loaded = LoadedChunk(device: device, content: content)
                activeChunks[coord] = loaded
                collisionWorld.setColliders(loaded.colliders, for: coord)
                storeInCache(loaded)
            }
        }
    }

    private func storeInCache(_ chunk: LoadedChunk) {
        chunkCache[chunk.coord] = chunk
        cacheOrder.append(chunk.coord)

        while cacheOrder.count > maxCachedChunks {
            let evicted = cacheOrder.removeFirst()
            if activeChunks[evicted] == nil {
                chunkCache.removeValue(forKey: evicted)
            }
        }
    }

    public func releaseMemory() {
        // Evict inactive cached chunks when app enters background or receives memory warning
        for coord in Array(chunkCache.keys) where activeChunks[coord] == nil {
            chunkCache.removeValue(forKey: coord)
        }
        cacheOrder.removeAll { chunkCache[$0] == nil }
    }
}
