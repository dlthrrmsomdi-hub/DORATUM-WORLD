import Foundation
import Metal
import simd

public struct InteractablePoint {
    public let title: String
    public let message: String
    public let position: SIMD3<Float>
    public let radius: Float
}

public final class WorldScene {
    public let materialSystem: MaterialSystem
    public let meshFactory: MeshFactory
    public let lightingSystem: LightingSystem
    public let worldGenerator: WorldGenerator
    public let collisionWorld: CollisionWorld
    public let physicsWorld: PhysicsWorld
    public let chunkManager: ChunkManager
    public let playerController: PlayerController
    public let cameraController: CameraController

    public private(set) var treeMeshes: [GPUMesh] = []
    public private(set) var rockMesh: GPUMesh?
    public private(set) var waterMesh: GPUMesh?
    public private(set) var elapsedTime: Float = 0.0

    public let landmarks: [InteractablePoint] = [
        InteractablePoint(
            title: "Doratum Spire",
            message: "Welcome to Doratum Bay! Downtown Plaza stands at the heart of the city.",
            position: SIMD3<Float>(0, 2.2, 0),
            radius: 10.0
        ),
        InteractablePoint(
            title: "Seaside Boardwalk",
            message: "Doratum Bay Coastline — Enjoy the ocean breeze and animated waves.",
            position: SIMD3<Float>(98, 2.0, 12),
            radius: 14.0
        ),
        InteractablePoint(
            title: "Westside Park",
            message: "Doratum Central Park — Rolling green hills and shaded walking trails.",
            position: SIMD3<Float>(-115, 3.0, -10),
            radius: 16.0
        ),
        InteractablePoint(
            title: "Bayview Residences",
            message: "Residential District — Quiet neighborhood avenues and coastal homes.",
            position: SIMD3<Float>(16, 2.2, 118),
            radius: 16.0
        )
    ]

    public init(saveData: PlayerSaveData, settings: GameSettings) {
        self.materialSystem = MaterialSystem()
        self.meshFactory = MeshFactory()
        self.lightingSystem = LightingSystem()
        self.worldGenerator = WorldGenerator(seed: 20260719, meshFactory: meshFactory, materialSystem: materialSystem)
        self.collisionWorld = CollisionWorld()
        self.collisionWorld.worldHalfExtent = worldGenerator.worldHalfExtent
        self.collisionWorld.terrainHeightProvider = { [worldGenerator] x, z in
            worldGenerator.terrainHeight(at: x, z: z)
        }
        self.physicsWorld = PhysicsWorld(collisionWorld: collisionWorld, chunkSize: worldGenerator.chunkSize)
        self.chunkManager = ChunkManager(generator: worldGenerator, collisionWorld: collisionWorld)

        let charModel = CharacterModel(meshFactory: meshFactory, materialSystem: materialSystem)
        charModel.applyOutfit(settings.outfitPreset)

        let safeY = max(saveData.posY, worldGenerator.terrainHeight(at: saveData.posX, z: saveData.posZ) + 0.1)
        let startPos = SIMD3<Float>(saveData.posX, safeY, saveData.posZ)

        self.playerController = PlayerController(
            initialPosition: startPos,
            initialYaw: saveData.yaw,
            physicsWorld: physicsWorld,
            model: charModel
        )
        self.cameraController = CameraController(collisionWorld: collisionWorld, chunkSize: worldGenerator.chunkSize)
        self.cameraController.configure(
            yaw: saveData.cameraYaw,
            pitch: saveData.cameraPitch,
            distance: saveData.cameraDistance,
            focusPoint: startPos
        )
    }

    public func buildSharedGPUResources(device: MTLDevice, quality: GraphicsQuality) {
        chunkManager.attachDevice(device)
        playerController.model.buildGPUResources(device: device)

        if treeMeshes.isEmpty {
            for style in 0..<3 {
                if let mesh = GPUMesh(device: device, meshData: meshFactory.makeTreeMesh(style: style), label: "TreeStyle_\(style)") {
                    treeMeshes.append(mesh)
                }
            }
        }
        if rockMesh == nil {
            rockMesh = GPUMesh(device: device, meshData: meshFactory.makeRockMesh(), label: "RockMesh")
        }
        if waterMesh == nil {
            waterMesh = GPUMesh(device: device, meshData: meshFactory.makeWaterGridMesh(size: 760.0, subdivisions: 48), label: "OceanWaterMesh")
        }

        // Immediately load spawn chunks so world is playable without waiting
        chunkManager.updateChunks(around: playerController.position, quality: quality)
    }

    public func stepFixedPhysics(
        input: InputController.FrameInputSnapshot,
        controlSensitivity: Float,
        fixedDt: Float
    ) {
        playerController.stepPhysics(
            input: input,
            cameraYaw: cameraController.yaw,
            controlSensitivity: controlSensitivity,
            fixedDt: fixedDt
        )
    }

    public func updateVariableSystems(
        dt: Float,
        input: InputController.FrameInputSnapshot,
        settings: GameSettings
    ) {
        elapsedTime += dt
        lightingSystem.update(deltaTime: dt)
        playerController.updateAnimation(dt: dt)
        cameraController.update(
            dt: dt,
            playerPosition: playerController.position,
            playerYaw: playerController.yaw,
            cameraDelta: input.cameraDelta,
            zoomDelta: input.zoomDelta,
            resetTriggered: input.cameraResetTriggered,
            sensitivity: settings.cameraSensitivity,
            renderDistance: settings.renderDistance
        )
        chunkManager.updateChunks(around: playerController.position, quality: settings.graphicsQuality)
    }

    public func currentLocationLabel() -> String {
        let pos = playerController.position
        let dist = worldGenerator.district(at: pos.x, z: pos.z)
        return "\(dist.rawValue) — Doratum Bay"
    }

    public func nearbyInteractable() -> InteractablePoint? {
        let pos = playerController.position
        for point in landmarks {
            if simd_distance(SIMD2<Float>(pos.x, pos.z), SIMD2<Float>(point.position.x, point.position.z)) <= point.radius {
                return point
            }
        }
        return nil
    }

    public func makeSaveData() -> PlayerSaveData {
        PlayerSaveData(
            posX: playerController.position.x,
            posY: playerController.position.y,
            posZ: playerController.position.z,
            yaw: playerController.yaw,
            cameraYaw: cameraController.yaw,
            cameraPitch: cameraController.pitch,
            cameraDistance: cameraController.targetDistance,
            lastKnownLocation: currentLocationLabel(),
            savedTimestamp: Date().timeIntervalSince1970
        )
    }
}
