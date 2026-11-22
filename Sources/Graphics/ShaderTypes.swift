import Foundation
import Metal
import simd

// MARK: - Vertex & Uniform Layouts (16-byte aligned, matching WorldShaders.metal)

public struct Vertex {
    public var position: SIMD3<Float>
    public var normal: SIMD3<Float>
    public var color: SIMD4<Float>
    public var uv: SIMD2<Float>
    public var padding: SIMD2<Float>

    public init(
        position: SIMD3<Float>,
        normal: SIMD3<Float>,
        color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        uv: SIMD2<Float> = SIMD2<Float>(0, 0)
    ) {
        self.position = position
        self.normal = normal
        self.color = color
        self.uv = uv
        self.padding = SIMD2<Float>(0, 0)
    }

    public static func makeVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        // Attribute 0: position
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = MemoryLayout<Vertex>.offset(of: \.position) ?? 0
        descriptor.attributes[0].bufferIndex = 0
        // Attribute 1: normal
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = MemoryLayout<Vertex>.offset(of: \.normal) ?? 16
        descriptor.attributes[1].bufferIndex = 0
        // Attribute 2: color
        descriptor.attributes[2].format = .float4
        descriptor.attributes[2].offset = MemoryLayout<Vertex>.offset(of: \.color) ?? 32
        descriptor.attributes[2].bufferIndex = 0
        // Attribute 3: uv
        descriptor.attributes[3].format = .float2
        descriptor.attributes[3].offset = MemoryLayout<Vertex>.offset(of: \.uv) ?? 48
        descriptor.attributes[3].bufferIndex = 0

        descriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }
}

public struct FrameUniforms {
    public var viewProjectionMatrix: simd_float4x4
    public var cameraPosition: SIMD4<Float>   // xyz = pos, w = elapsedTime
    public var sunDirection: SIMD4<Float>     // xyz = normalized dir toward sun, w = sunIntensity
    public var sunColor: SIMD4<Float>         // rgb = sunColor, w = ambientIntensity
    public var ambientColor: SIMD4<Float>     // rgb = ambientColor, w = fogDensity
    public var fogColor: SIMD4<Float>         // rgb = fogColor, w = fogStart
    public var fogParams: SIMD4<Float>        // x = fogEnd, y = waterLevel, z = qualityTier, w = 0

    public init(
        viewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4,
        cameraPosition: SIMD4<Float> = SIMD4<Float>(0, 10, 0, 0),
        sunDirection: SIMD4<Float> = SIMD4<Float>(0.4, 0.8, 0.3, 1.0),
        sunColor: SIMD4<Float> = SIMD4<Float>(1.0, 0.96, 0.88, 0.35),
        ambientColor: SIMD4<Float> = SIMD4<Float>(0.55, 0.68, 0.85, 0.004),
        fogColor: SIMD4<Float> = SIMD4<Float>(0.68, 0.82, 0.96, 60.0),
        fogParams: SIMD4<Float> = SIMD4<Float>(240.0, 0.0, 1.0, 0.0)
    ) {
        self.viewProjectionMatrix = viewProjectionMatrix
        self.cameraPosition = cameraPosition
        self.sunDirection = sunDirection
        self.sunColor = sunColor
        self.ambientColor = ambientColor
        self.fogColor = fogColor
        self.fogParams = fogParams
    }
}

public struct ModelUniforms {
    public var modelMatrix: simd_float4x4
    public var normalMatrix: simd_float4x4
    public var tintColor: SIMD4<Float>        // rgb = tint, a = opacity
    public var materialParams: SIMD4<Float>   // x = specular, y = shininess, z = roughness, w = emissive

    public init(
        modelMatrix: simd_float4x4 = matrix_identity_float4x4,
        tintColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        materialParams: SIMD4<Float> = SIMD4<Float>(0.25, 24.0, 0.65, 0.0)
    ) {
        self.modelMatrix = modelMatrix
        let upper = simd_float3x3(
            SIMD3<Float>(modelMatrix.columns.0.x, modelMatrix.columns.0.y, modelMatrix.columns.0.z),
            SIMD3<Float>(modelMatrix.columns.1.x, modelMatrix.columns.1.y, modelMatrix.columns.1.z),
            SIMD3<Float>(modelMatrix.columns.2.x, modelMatrix.columns.2.y, modelMatrix.columns.2.z)
        )
        let det = simd_determinant(upper)
        let invT: simd_float3x3 = abs(det) > 1e-6 ? upper.inverse.transpose : matrix_identity_float3x3
        self.normalMatrix = simd_float4x4(
            SIMD4<Float>(invT.columns.0, 0),
            SIMD4<Float>(invT.columns.1, 0),
            SIMD4<Float>(invT.columns.2, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
        self.tintColor = tintColor
        self.materialParams = materialParams
    }
}

public struct InstanceData {
    public var modelMatrix: simd_float4x4
    public var tintColor: SIMD4<Float>
    public var materialParams: SIMD4<Float>

    public init(
        modelMatrix: simd_float4x4,
        tintColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        materialParams: SIMD4<Float> = SIMD4<Float>(0.2, 16.0, 0.7, 0.0)
    ) {
        self.modelMatrix = modelMatrix
        self.tintColor = tintColor
        self.materialParams = materialParams
    }
}

// MARK: - Geometry & Bounding Volumes

public struct MeshData {
    public var vertices: [Vertex]
    public var indices: [UInt32]
    public var bounds: AABB

    public init(vertices: [Vertex], indices: [UInt32]) {
        self.vertices = vertices
        self.indices = indices
        if let first = vertices.first {
            var minP = first.position
            var maxP = first.position
            for v in vertices {
                minP = simd_min(minP, v.position)
                maxP = simd_max(maxP, v.position)
            }
            self.bounds = AABB(min: minP, max: maxP)
        } else {
            self.bounds = AABB(min: .zero, max: .zero)
        }
    }
}

public final class GPUMesh {
    public let vertexBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexCount: Int
    public let bounds: AABB

    public init?(device: MTLDevice, meshData: MeshData, label: String) {
        guard !meshData.vertices.isEmpty, !meshData.indices.isEmpty else {
            return nil
        }
        let vLength = meshData.vertices.count * MemoryLayout<Vertex>.stride
        let iLength = meshData.indices.count * MemoryLayout<UInt32>.stride
        guard
            let vBuf = device.makeBuffer(bytes: meshData.vertices, length: vLength, options: .storageModeShared),
            let iBuf = device.makeBuffer(bytes: meshData.indices, length: iLength, options: .storageModeShared)
        else {
            return nil
        }
        vBuf.label = "\(label)_VB"
        iBuf.label = "\(label)_IB"
        self.vertexBuffer = vBuf
        self.indexBuffer = iBuf
        self.indexCount = meshData.indices.count
        self.bounds = meshData.bounds
    }
}

public struct AABB: Equatable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public var center: SIMD3<Float> {
        (min + max) * 0.5
    }

    public var extents: SIMD3<Float> {
        (max - min) * 0.5
    }

    public func transformed(by matrix: simd_float4x4) -> AABB {
        let corners: [SIMD3<Float>] = [
            SIMD3<Float>(min.x, min.y, min.z),
            SIMD3<Float>(max.x, min.y, min.z),
            SIMD3<Float>(min.x, max.y, min.z),
            SIMD3<Float>(max.x, max.y, min.z),
            SIMD3<Float>(min.x, min.y, max.z),
            SIMD3<Float>(max.x, min.y, max.z),
            SIMD3<Float>(min.x, max.y, max.z),
            SIMD3<Float>(max.x, max.y, max.z)
        ]
        var newMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var newMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for c in corners {
            let p4 = matrix * SIMD4<Float>(c.x, c.y, c.z, 1.0)
            let p = SIMD3<Float>(p4.x, p4.y, p4.z)
            newMin = simd_min(newMin, p)
            newMax = simd_max(newMax, p)
        }
        return AABB(min: newMin, max: newMax)
    }
}

public struct Frustum {
    public var planes: [SIMD4<Float>]

    public init(viewProjection m: simd_float4x4) {
        let row0 = SIMD4<Float>(m.columns.0.x, m.columns.1.x, m.columns.2.x, m.columns.3.x)
        let row1 = SIMD4<Float>(m.columns.0.y, m.columns.1.y, m.columns.2.y, m.columns.3.y)
        let row2 = SIMD4<Float>(m.columns.0.z, m.columns.1.z, m.columns.2.z, m.columns.3.z)
        let row3 = SIMD4<Float>(m.columns.0.w, m.columns.1.w, m.columns.2.w, m.columns.3.w)

        let rawPlanes: [SIMD4<Float>] = [
            row3 + row0, // Left
            row3 - row0, // Right
            row3 + row1, // Bottom
            row3 - row1, // Top
            row2,        // Near (Metal Z in [0, 1])
            row3 - row2  // Far
        ]
        self.planes = rawPlanes.map { p in
            let len = simd_length(SIMD3<Float>(p.x, p.y, p.z))
            return len > 1e-6 ? p / len : p
        }
    }

    public func intersects(_ box: AABB) -> Bool {
        for plane in planes {
            let px = plane.x >= 0 ? box.max.x : box.min.x
            let py = plane.y >= 0 ? box.max.y : box.min.y
            let pz = plane.z >= 0 ? box.max.z : box.min.z
            if plane.x * px + plane.y * py + plane.z * pz + plane.w < 0 {
                return false
            }
        }
        return true
    }
}

// MARK: - Matrix Helpers

public enum Math3D {
    public static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }

    public static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4<Float>(s.x, 0, 0, 0),
            SIMD4<Float>(0, s.y, 0, 0),
            SIMD4<Float>(0, 0, s.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    public static func rotationX(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    public static func rotationY(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    public static func rotationZ(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(
            SIMD4<Float>(c, s, 0, 0),
            SIMD4<Float>(-s, c, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }

    public static func perspectiveRH(fovYRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let safeAspect = max(aspect, 0.1)
        let yScale = 1.0 / tan(fovYRadians * 0.5)
        let xScale = yScale / safeAspect
        let zRange = farZ - nearZ
        let zScale = -(farZ) / zRange
        let wzScale = -(farZ * nearZ) / zRange
        return simd_float4x4(
            SIMD4<Float>(xScale, 0, 0, 0),
            SIMD4<Float>(0, yScale, 0, 0),
            SIMD4<Float>(0, 0, zScale, -1),
            SIMD4<Float>(0, 0, wzScale, 0)
        )
    }

    public static func lookAtRH(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let zAxis = simd_normalize(eye - target)
        let xAxis = simd_normalize(simd_cross(up, zAxis))
        let yAxis = simd_cross(zAxis, xAxis)
        return simd_float4x4(
            SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0),
            SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0),
            SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0),
            SIMD4<Float>(-simd_dot(xAxis, eye), -simd_dot(yAxis, eye), -simd_dot(zAxis, eye), 1)
        )
    }

    public static func clamp<T: Comparable>(_ value: T, min minVal: T, max maxVal: T) -> T {
        Swift.max(minVal, Swift.min(maxVal, value))
    }

    public static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * clamp(t, min: 0, max: 1)
    }

    public static func lerpAngle(_ a: Float, _ b: Float, _ t: Float) -> Float {
        var diff = (b - a).truncatingRemainder(dividingBy: .pi * 2)
        if diff > .pi { diff -= .pi * 2 }
        if diff < -.pi { diff += .pi * 2 }
        return a + diff * clamp(t, min: 0, max: 1)
    }
}
