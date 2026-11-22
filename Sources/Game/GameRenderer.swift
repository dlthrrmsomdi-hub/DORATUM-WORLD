import Foundation
import Metal
import MetalKit
import simd

public enum GraphicsInitError: LocalizedError {
    case metalDeviceUnavailable
    case commandQueueCreationFailed
    case shaderLibraryUnavailable
    case shaderFunctionMissing(String)
    case pipelineCreationFailed(String)
    case depthStencilCreationFailed

    public var errorDescription: String? {
        switch self {
        case .metalDeviceUnavailable:
            return "Apple Metal GPU device is not available on this device."
        case .commandQueueCreationFailed:
            return "Failed to create Metal command queue."
        case .shaderLibraryUnavailable:
            return "Failed to load compiled Metal shader library (WorldShaders.metal)."
        case .shaderFunctionMissing(let name):
            return "Missing required Metal shader function: \(name)."
        case .pipelineCreationFailed(let reason):
            return "Failed to build Metal render pipeline: \(reason)"
        case .depthStencilCreationFailed:
            return "Failed to create depth-stencil state."
        }
    }
}

public final class GameRenderer: NSObject, MTKViewDelegate {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let opaquePipeline: MTLRenderPipelineState
    private let instancedPipeline: MTLRenderPipelineState
    private let waterPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let waterDepthState: MTLDepthStencilState

    private let frameUniformBuffer: MTLBuffer?
    private weak var engine: GameEngine?

    public private(set) var viewportSize = CGSize(width: 1280, height: 720)
    public private(set) var lastDrawCallCount: Int = 0
    public private(set) var lastVisibleChunkCount: Int = 0

    public init(engine: GameEngine, colorPixelFormat: MTLPixelFormat = .bgra8Unorm, depthPixelFormat: MTLPixelFormat = .depth32Float) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw GraphicsInitError.metalDeviceUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw GraphicsInitError.commandQueueCreationFailed
        }
        guard let library = device.makeDefaultLibrary() else {
            throw GraphicsInitError.shaderLibraryUnavailable
        }

        guard let vertMain = library.makeFunction(name: "vertex_main") else {
            throw GraphicsInitError.shaderFunctionMissing("vertex_main")
        }
        guard let fragMain = library.makeFunction(name: "fragment_main") else {
            throw GraphicsInitError.shaderFunctionMissing("fragment_main")
        }
        guard let vertInstanced = library.makeFunction(name: "vertex_instanced") else {
            throw GraphicsInitError.shaderFunctionMissing("vertex_instanced")
        }
        guard let vertWater = library.makeFunction(name: "vertex_water") else {
            throw GraphicsInitError.shaderFunctionMissing("vertex_water")
        }
        guard let fragWater = library.makeFunction(name: "fragment_water") else {
            throw GraphicsInitError.shaderFunctionMissing("fragment_water")
        }

        let vertexDescriptor = Vertex.makeVertexDescriptor()

        // 1. Opaque World & Character Pipeline
        let opaqueDesc = MTLRenderPipelineDescriptor()
        opaqueDesc.label = "DoratumOpaquePipeline"
        opaqueDesc.vertexFunction = vertMain
        opaqueDesc.fragmentFunction = fragMain
        opaqueDesc.vertexDescriptor = vertexDescriptor
        opaqueDesc.colorAttachments[0].pixelFormat = colorPixelFormat
        opaqueDesc.depthAttachmentPixelFormat = depthPixelFormat

        // 2. Instanced Vegetation & Props Pipeline
        let instancedDesc = MTLRenderPipelineDescriptor()
        instancedDesc.label = "DoratumInstancedPipeline"
        instancedDesc.vertexFunction = vertInstanced
        instancedDesc.fragmentFunction = fragMain
        instancedDesc.vertexDescriptor = vertexDescriptor
        instancedDesc.colorAttachments[0].pixelFormat = colorPixelFormat
        instancedDesc.depthAttachmentPixelFormat = depthPixelFormat

        // 3. Translucent Animated Water Pipeline
        let waterDesc = MTLRenderPipelineDescriptor()
        waterDesc.label = "DoratumWaterPipeline"
        waterDesc.vertexFunction = vertWater
        waterDesc.fragmentFunction = fragWater
        waterDesc.vertexDescriptor = vertexDescriptor
        waterDesc.colorAttachments[0].pixelFormat = colorPixelFormat
        waterDesc.colorAttachments[0].isBlendingEnabled = true
        waterDesc.colorAttachments[0].rgbBlendOperation = .add
        waterDesc.colorAttachments[0].alphaBlendOperation = .add
        waterDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        waterDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        waterDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        waterDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        waterDesc.depthAttachmentPixelFormat = depthPixelFormat

        do {
            self.opaquePipeline = try device.makeRenderPipelineState(descriptor: opaqueDesc)
            self.instancedPipeline = try device.makeRenderPipelineState(descriptor: instancedDesc)
            self.waterPipeline = try device.makeRenderPipelineState(descriptor: waterDesc)
        } catch {
            throw GraphicsInitError.pipelineCreationFailed(error.localizedDescription)
        }

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .less
        depthDesc.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depthDesc) else {
            throw GraphicsInitError.depthStencilCreationFailed
        }

        let waterDepthDesc = MTLDepthStencilDescriptor()
        waterDepthDesc.depthCompareFunction = .less
        waterDepthDesc.isDepthWriteEnabled = false
        guard let waterDepthState = device.makeDepthStencilState(descriptor: waterDepthDesc) else {
            throw GraphicsInitError.depthStencilCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.depthState = depthState
        self.waterDepthState = waterDepthState
        self.frameUniformBuffer = device.makeBuffer(length: MemoryLayout<FrameUniforms>.stride, options: .storageModeShared)
        self.engine = engine

        super.init()
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        if size.width > 0 && size.height > 0 {
            viewportSize = size
        }
    }

    public func draw(in view: MTKView) {
        guard
            let engine,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        // Advance simulation step (skips movement when paused or on main menu)
        engine.tickFrame()

        let scene = engine.scene
        let settings = engine.settings

        renderPassDescriptor.colorAttachments[0].clearColor = scene.lightingSystem.clearColor
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.storeAction = .dontCare

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        encoder.label = "DoratumWorldMainPass"

        let aspect = Float(max(viewportSize.width, 1.0) / max(viewportSize.height, 1.0))
        let viewProj = scene.cameraController.viewProjectionMatrix(aspectRatio: aspect)
        let frustum = Frustum(viewProjection: viewProj)
        let camPos = scene.cameraController.position
        let maxRenderDist = settings.renderDistance + scene.chunkManager.chunkSize

        var frameUniforms = scene.lightingSystem.makeFrameUniforms(
            viewProjection: viewProj,
            cameraPosition: camPos,
            elapsedTime: scene.elapsedTime,
            renderDistance: settings.renderDistance,
            qualityTier: settings.graphicsQuality.qualityTierValue
        )

        if let frameUniformBuffer {
            memcpy(frameUniformBuffer.contents(), &frameUniforms, MemoryLayout<FrameUniforms>.stride)
            encoder.setVertexBuffer(frameUniformBuffer, offset: 0, index: 1)
            encoder.setFragmentBuffer(frameUniformBuffer, offset: 0, index: 1)
        } else {
            encoder.setVertexBytes(&frameUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&frameUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        }

        var drawCalls = 0
        var visibleChunks: [LoadedChunk] = []
        let loaded = scene.chunkManager.loadedChunks()
        visibleChunks.reserveCapacity(loaded.count)

        for chunk in loaded {
            let dist = simd_distance(SIMD2<Float>(camPos.x, camPos.z), SIMD2<Float>(chunk.bounds.center.x, chunk.bounds.center.z))
            if dist > maxRenderDist { continue }
            if !frustum.intersects(chunk.bounds) { continue }
            visibleChunks.append(chunk)
        }
        lastVisibleChunkCount = visibleChunks.count

        // PASS 1: Opaque Terrain, Roads, Buildings, and Player Character
        encoder.setRenderPipelineState(opaquePipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.back)
        encoder.setFrontFacing(.counterClockwise)

        var terrainUniforms = ModelUniforms(
            modelMatrix: matrix_identity_float4x4,
            tintColor: SIMD4<Float>(1, 1, 1, 1),
            materialParams: scene.materialSystem.material(for: .grass).materialParams
        )
        var roadUniforms = ModelUniforms(
            modelMatrix: matrix_identity_float4x4,
            tintColor: SIMD4<Float>(1, 1, 1, 1),
            materialParams: scene.materialSystem.material(for: .asphalt).materialParams
        )
        var buildingUniforms = ModelUniforms(
            modelMatrix: matrix_identity_float4x4,
            tintColor: SIMD4<Float>(1, 1, 1, 1),
            materialParams: scene.materialSystem.material(for: .concrete).materialParams
        )

        for chunk in visibleChunks {
            if let terrain = chunk.terrainMesh {
                encoder.setVertexBytes(&terrainUniforms, length: MemoryLayout<ModelUniforms>.stride, index: 2)
                encoder.setVertexBuffer(terrain.vertexBuffer, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: terrain.indexCount, indexType: .uint32, indexBuffer: terrain.indexBuffer, indexBufferOffset: 0)
                drawCalls += 1
            }

            if let roads = chunk.roadMesh {
                encoder.setVertexBytes(&roadUniforms, length: MemoryLayout<ModelUniforms>.stride, index: 2)
                encoder.setVertexBuffer(roads.vertexBuffer, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: roads.indexCount, indexType: .uint32, indexBuffer: roads.indexBuffer, indexBufferOffset: 0)
                drawCalls += 1
            }

            if let structures = chunk.structuresMesh {
                encoder.setVertexBytes(&buildingUniforms, length: MemoryLayout<ModelUniforms>.stride, index: 2)
                encoder.setVertexBuffer(structures.vertexBuffer, offset: 0, index: 0)
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: structures.indexCount, indexType: .uint32, indexBuffer: structures.indexBuffer, indexBufferOffset: 0)
                drawCalls += 1
            }
        }

        // Draw Player Character Parts
        let playerParts = scene.playerController.model.buildRenderItems(
            worldPosition: scene.playerController.position,
            yaw: scene.playerController.yaw,
            pose: scene.playerController.animation.currentPose
        )
        for item in playerParts {
            var u = item.modelUniforms
            encoder.setVertexBytes(&u, length: MemoryLayout<ModelUniforms>.stride, index: 2)
            encoder.setVertexBuffer(item.mesh.vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: item.mesh.indexCount, indexType: .uint32, indexBuffer: item.mesh.indexBuffer, indexBufferOffset: 0)
            drawCalls += 1
        }

        // PASS 2: Instanced Vegetation (Trees) & Rocks
        encoder.setRenderPipelineState(instancedPipeline)
        encoder.setCullMode(.none)

        for chunk in visibleChunks {
            for entry in chunk.treeInstanceBuffers {
                guard entry.style >= 0, entry.style < scene.treeMeshes.count, entry.count > 0 else { continue }
                let treeMesh = scene.treeMeshes[entry.style]
                encoder.setVertexBuffer(treeMesh.vertexBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(entry.buffer, offset: 0, index: 3)
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: treeMesh.indexCount,
                    indexType: .uint32,
                    indexBuffer: treeMesh.indexBuffer,
                    indexBufferOffset: 0,
                    instanceCount: entry.count
                )
                drawCalls += 1
            }

            if let rockMesh = scene.rockMesh, let rockBuf = chunk.rockInstanceBuffer, rockBuf.count > 0 {
                encoder.setVertexBuffer(rockMesh.vertexBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(rockBuf.buffer, offset: 0, index: 3)
                encoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: rockMesh.indexCount,
                    indexType: .uint32,
                    indexBuffer: rockMesh.indexBuffer,
                    indexBufferOffset: 0,
                    instanceCount: rockBuf.count
                )
                drawCalls += 1
            }
        }

        // PASS 3: Animated 3D Water Surface
        if let waterMesh = scene.waterMesh {
            encoder.setRenderPipelineState(waterPipeline)
            encoder.setDepthStencilState(waterDepthState)
            encoder.setCullMode(.none)

            var waterUniforms = ModelUniforms(
                modelMatrix: Math3D.translation(SIMD3<Float>(210.0, 0.0, 0.0)),
                tintColor: SIMD4<Float>(1, 1, 1, 0.86),
                materialParams: scene.materialSystem.material(for: .water).materialParams
            )
            encoder.setVertexBytes(&waterUniforms, length: MemoryLayout<ModelUniforms>.stride, index: 2)
            encoder.setVertexBuffer(waterMesh.vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: waterMesh.indexCount,
                indexType: .uint32,
                indexBuffer: waterMesh.indexBuffer,
                indexBufferOffset: 0
            )
            drawCalls += 1
        }

        lastDrawCallCount = drawCalls
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
