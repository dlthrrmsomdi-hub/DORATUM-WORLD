import Foundation
import simd

public final class MeshFactory {
    public init() {}

    // MARK: - Primitive Append Helpers (for Mesh Batching)

    public static func appendBox(
        into vertices: inout [Vertex],
        indices: inout [UInt32],
        center: SIMD3<Float>,
        size: SIMD3<Float>,
        color: SIMD4<Float>
    ) {
        let hx = size.x * 0.5
        let hy = size.y * 0.5
        let hz = size.z * 0.5

        let faces: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])] = [
            // +Z Front
            (SIMD3<Float>(0, 0, 1), [
                SIMD3<Float>(-hx, -hy, hz), SIMD3<Float>(hx, -hy, hz),
                SIMD3<Float>(hx, hy, hz), SIMD3<Float>(-hx, hy, hz)
            ]),
            // -Z Back
            (SIMD3<Float>(0, 0, -1), [
                SIMD3<Float>(hx, -hy, -hz), SIMD3<Float>(-hx, -hy, -hz),
                SIMD3<Float>(-hx, hy, -hz), SIMD3<Float>(hx, hy, -hz)
            ]),
            // +X Right
            (SIMD3<Float>(1, 0, 0), [
                SIMD3<Float>(hx, -hy, hz), SIMD3<Float>(hx, -hy, -hz),
                SIMD3<Float>(hx, hy, -hz), SIMD3<Float>(hx, hy, hz)
            ]),
            // -X Left
            (SIMD3<Float>(-1, 0, 0), [
                SIMD3<Float>(-hx, -hy, -hz), SIMD3<Float>(-hx, -hy, hz),
                SIMD3<Float>(-hx, hy, hz), SIMD3<Float>(-hx, hy, -hz)
            ]),
            // +Y Top
            (SIMD3<Float>(0, 1, 0), [
                SIMD3<Float>(-hx, hy, hz), SIMD3<Float>(hx, hy, hz),
                SIMD3<Float>(hx, hy, -hz), SIMD3<Float>(-hx, hy, -hz)
            ]),
            // -Y Bottom
            (SIMD3<Float>(0, -1, 0), [
                SIMD3<Float>(-hx, -hy, -hz), SIMD3<Float>(hx, -hy, -hz),
                SIMD3<Float>(hx, -hy, hz), SIMD3<Float>(-hx, -hy, hz)
            ])
        ]

        let uvs: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)
        ]

        for face in faces {
            let baseIndex = UInt32(vertices.count)
            for i in 0..<4 {
                vertices.append(Vertex(
                    position: center + face.corners[i],
                    normal: face.normal,
                    color: color,
                    uv: uvs[i]
                ))
            }
            indices.append(contentsOf: [
                baseIndex, baseIndex + 1, baseIndex + 2,
                baseIndex, baseIndex + 2, baseIndex + 3
            ])
        }
    }

    public static func appendCylinder(
        into vertices: inout [Vertex],
        indices: inout [UInt32],
        baseCenter: SIMD3<Float>,
        bottomRadius: Float,
        topRadius: Float,
        height: Float,
        segments: Int,
        color: SIMD4<Float>
    ) {
        let segs = max(5, segments)
        let baseStart = UInt32(vertices.count)

        for i in 0...segs {
            let theta = Float(i) / Float(segs) * (.pi * 2.0)
            let ct = cos(theta)
            let st = sin(theta)
            let slope = (bottomRadius - topRadius) / max(height, 0.001)
            let normal = simd_normalize(SIMD3<Float>(ct, slope, st))

            let bottomPos = baseCenter + SIMD3<Float>(ct * bottomRadius, 0, st * bottomRadius)
            let topPos = baseCenter + SIMD3<Float>(ct * topRadius, height, st * topRadius)

            vertices.append(Vertex(position: bottomPos, normal: normal, color: color, uv: SIMD2<Float>(Float(i) / Float(segs), 0)))
            vertices.append(Vertex(position: topPos, normal: normal, color: color, uv: SIMD2<Float>(Float(i) / Float(segs), 1)))
        }

        for i in 0..<segs {
            let i0 = baseStart + UInt32(i * 2)
            let i1 = i0 + 1
            let i2 = i0 + 2
            let i3 = i0 + 3
            indices.append(contentsOf: [i0, i2, i3, i0, i3, i1])
        }

        // Top cap if topRadius > 0
        if topRadius > 0.001 {
            let capCenterIdx = UInt32(vertices.count)
            vertices.append(Vertex(position: baseCenter + SIMD3<Float>(0, height, 0), normal: SIMD3<Float>(0, 1, 0), color: color))
            let ringStart = UInt32(vertices.count)
            for i in 0...segs {
                let theta = Float(i) / Float(segs) * (.pi * 2.0)
                let p = baseCenter + SIMD3<Float>(cos(theta) * topRadius, height, sin(theta) * topRadius)
                vertices.append(Vertex(position: p, normal: SIMD3<Float>(0, 1, 0), color: color))
            }
            for i in 0..<segs {
                indices.append(contentsOf: [capCenterIdx, ringStart + UInt32(i + 1), ringStart + UInt32(i)])
            }
        }
    }

    public static func appendPitchedRoof(
        into vertices: inout [Vertex],
        indices: inout [UInt32],
        baseCenter: SIMD3<Float>,
        width: Float,
        depth: Float,
        height: Float,
        color: SIMD4<Float>
    ) {
        let hx = width * 0.5
        let hz = depth * 0.5
        let y0 = baseCenter.y
        let y1 = baseCenter.y + height
        let cx = baseCenter.x
        let cz = baseCenter.z

        let fl = SIMD3<Float>(cx - hx, y0, cz + hz)
        let fr = SIMD3<Float>(cx + hx, y0, cz + hz)
        let bl = SIMD3<Float>(cx - hx, y0, cz - hz)
        let br = SIMD3<Float>(cx + hx, y0, cz - hz)
        let ridgeF = SIMD3<Float>(cx, y1, cz + hz)
        let ridgeB = SIMD3<Float>(cx, y1, cz - hz)

        func addTri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            let n = simd_normalize(simd_cross(b - a, c - a))
            let base = UInt32(vertices.count)
            vertices.append(Vertex(position: a, normal: n, color: color))
            vertices.append(Vertex(position: b, normal: n, color: color))
            vertices.append(Vertex(position: c, normal: n, color: color))
            indices.append(contentsOf: [base, base + 1, base + 2])
        }

        func addQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
            let n = simd_normalize(simd_cross(b - a, c - a))
            let base = UInt32(vertices.count)
            vertices.append(Vertex(position: a, normal: n, color: color))
            vertices.append(Vertex(position: b, normal: n, color: color))
            vertices.append(Vertex(position: c, normal: n, color: color))
            vertices.append(Vertex(position: d, normal: n, color: color))
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        // Left slope
        addQuad(bl, fl, ridgeF, ridgeB)
        // Right slope
        addQuad(fr, br, ridgeB, ridgeF)
        // Front gable
        addTri(fl, fr, ridgeF)
        // Back gable
        addTri(br, bl, ridgeB)
    }

    // MARK: - Standalone Meshes

    public func makeBoxMesh(size: SIMD3<Float>, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> MeshData {
        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        Self.appendBox(into: &vertices, indices: &indices, center: .zero, size: size, color: color)
        return MeshData(vertices: vertices, indices: indices)
    }

    public func makeSphereMesh(radius: Float, stacks: Int = 10, slices: Int = 14, color: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> MeshData {
        var vertices: [Vertex] = []
        var indices: [UInt32] = []

        for stack in 0...stacks {
            let phi = Float(stack) / Float(stacks) * .pi
            let sinPhi = sin(phi)
            let cosPhi = cos(phi)
            for slice in 0...slices {
                let theta = Float(slice) / Float(slices) * (.pi * 2.0)
                let normal = SIMD3<Float>(sinPhi * cos(theta), cosPhi, sinPhi * sin(theta))
                let pos = normal * radius
                vertices.append(Vertex(
                    position: pos,
                    normal: normal,
                    color: color,
                    uv: SIMD2<Float>(Float(slice) / Float(slices), Float(stack) / Float(stacks))
                ))
            }
        }

        let stride = slices + 1
        for stack in 0..<stacks {
            for slice in 0..<slices {
                let i0 = UInt32(stack * stride + slice)
                let i1 = i0 + 1
                let i2 = i0 + UInt32(stride)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }
        return MeshData(vertices: vertices, indices: indices)
    }

    public func makeTreeMesh(style: Int) -> MeshData {
        var vertices: [Vertex] = []
        var indices: [UInt32] = []

        let trunkColor = SIMD4<Float>(0.42, 0.28, 0.16, 1.0)
        let leafA = style == 0
            ? SIMD4<Float>(0.16, 0.48, 0.22, 1.0)
            : (style == 1 ? SIMD4<Float>(0.22, 0.56, 0.24, 1.0) : SIMD4<Float>(0.18, 0.52, 0.30, 1.0))
        let leafB = SIMD4<Float>(leafA.x * 1.15, min(1.0, leafA.y * 1.14), leafA.z * 1.05, 1.0)

        if style == 2 {
            // Coastal Palm-style tree
            Self.appendCylinder(into: &vertices, indices: &indices, baseCenter: .zero, bottomRadius: 0.26, topRadius: 0.16, height: 4.8, segments: 7, color: trunkColor)
            // Frond clusters
            let frondOffsets: [SIMD3<Float>] = [
                SIMD3<Float>(1.1, 4.7, 0.0),
                SIMD3<Float>(-1.1, 4.7, 0.0),
                SIMD3<Float>(0.0, 4.7, 1.1),
                SIMD3<Float>(0.0, 4.7, -1.1),
                SIMD3<Float>(0.8, 4.9, 0.8),
                SIMD3<Float>(-0.8, 4.9, -0.8)
            ]
            for offset in frondOffsets {
                Self.appendBox(into: &vertices, indices: &indices, center: offset, size: SIMD3<Float>(1.3, 0.28, 1.3), color: leafA)
            }
            Self.appendCylinder(into: &vertices, indices: &indices, baseCenter: SIMD3<Float>(0, 4.8, 0), bottomRadius: 1.0, topRadius: 0.05, height: 0.9, segments: 7, color: leafB)
        } else if style == 1 {
            // Layered Pine/Park tree
            Self.appendCylinder(into: &vertices, indices: &indices, baseCenter: .zero, bottomRadius: 0.28, topRadius: 0.18, height: 2.2, segments: 7, color: trunkColor)
            Self.appendCylinder(into: &vertices, indices: &indices, baseCenter: SIMD3<Float>(0, 1.9, 0), bottomRadius: 1.9, topRadius: 0.3, height: 2.2, segments: 8, color: leafA)
            Self.appendCylinder(into: &vertices, indices: &indices, baseCenter: SIMD3<Float>(0, 3.4, 0), bottomRadius: 1.4, topRadius: 0.15, height: 1.9, segments: 8, color: leafB)
            Self.appendCylinder(into: &vertices, indices: &indices, baseCenter: SIMD3<Float>(0, 4.7, 0), bottomRadius: 0.85, topRadius: 0.02, height: 1.3, segments: 7, color: leafA)
        } else {
            // Broadleaf Urban/Park tree
            Self.appendCylinder(into: &vertices, indices: &indices, baseCenter: .zero, bottomRadius: 0.30, topRadius: 0.20, height: 2.8, segments: 7, color: trunkColor)
            Self.appendBox(into: &vertices, indices: &indices, center: SIMD3<Float>(0, 3.6, 0), size: SIMD3<Float>(2.5, 1.9, 2.5), color: leafA)
            Self.appendBox(into: &vertices, indices: &indices, center: SIMD3<Float>(0.5, 4.4, 0.3), size: SIMD3<Float>(1.7, 1.3, 1.7), color: leafB)
            Self.appendBox(into: &vertices, indices: &indices, center: SIMD3<Float>(-0.5, 4.2, -0.4), size: SIMD3<Float>(1.6, 1.2, 1.6), color: leafA)
        }

        return MeshData(vertices: vertices, indices: indices)
    }

    public func makeRockMesh() -> MeshData {
        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        let rockA = SIMD4<Float>(0.50, 0.52, 0.54, 1.0)
        let rockB = SIMD4<Float>(0.42, 0.44, 0.47, 1.0)
        Self.appendCylinder(into: &vertices, indices: &indices, baseCenter: .zero, bottomRadius: 1.0, topRadius: 0.65, height: 0.75, segments: 6, color: rockA)
        Self.appendBox(into: &vertices, indices: &indices, center: SIMD3<Float>(0.35, 0.35, 0.2), size: SIMD3<Float>(0.9, 0.65, 0.8), color: rockB)
        return MeshData(vertices: vertices, indices: indices)
    }

    public func makeWaterGridMesh(size: Float, subdivisions: Int) -> MeshData {
        let divs = max(8, subdivisions)
        let half = size * 0.5
        let step = size / Float(divs)

        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity((divs + 1) * (divs + 1))

        for z in 0...divs {
            for x in 0...divs {
                let wx = -half + Float(x) * step
                let wz = -half + Float(z) * step
                let u = Float(x) / Float(divs)
                let v = Float(z) / Float(divs)
                // Green channel encodes shore proximity hint for fragment_water
                let shoreHint: Float = Math3D.clamp(1.0 - (wx + half) / size, min: 0.15, max: 0.85)
                vertices.append(Vertex(
                    position: SIMD3<Float>(wx, 0.0, wz),
                    normal: SIMD3<Float>(0, 1, 0),
                    color: SIMD4<Float>(0.12, shoreHint, 0.78, 0.86),
                    uv: SIMD2<Float>(u, v)
                ))
            }
        }

        let row = divs + 1
        for z in 0..<divs {
            for x in 0..<divs {
                let i0 = UInt32(z * row + x)
                let i1 = i0 + 1
                let i2 = i0 + UInt32(row)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }
        return MeshData(vertices: vertices, indices: indices)
    }

    public func makeTerrainChunkMesh(
        originX: Float,
        originZ: Float,
        chunkSize: Float,
        gridResolution: Int,
        heightSampler: (Float, Float) -> Float,
        colorSampler: (Float, Float, Float) -> SIMD4<Float>
    ) -> MeshData {
        let divs = max(4, gridResolution)
        let step = chunkSize / Float(divs)
        var vertices: [Vertex] = []
        var indices: [UInt32] = []
        vertices.reserveCapacity((divs + 1) * (divs + 1))

        for gz in 0...divs {
            for gx in 0...divs {
                let wx = originX + Float(gx) * step
                let wz = originZ + Float(gz) * step
                let h = heightSampler(wx, wz)

                // Central finite-difference normal calculation
                let eps: Float = 0.6
                let hL = heightSampler(wx - eps, wz)
                let hR = heightSampler(wx + eps, wz)
                let hD = heightSampler(wx, wz - eps)
                let hU = heightSampler(wx, wz + eps)
                let normal = simd_normalize(SIMD3<Float>(hL - hR, 2.0 * eps, hD - hU))
                let color = colorSampler(wx, wz, h)

                vertices.append(Vertex(
                    position: SIMD3<Float>(wx, h, wz),
                    normal: normal,
                    color: color,
                    uv: SIMD2<Float>(Float(gx) / Float(divs), Float(gz) / Float(divs))
                ))
            }
        }

        let row = divs + 1
        for gz in 0..<divs {
            for gx in 0..<divs {
                let i0 = UInt32(gz * row + gx)
                let i1 = i0 + 1
                let i2 = i0 + UInt32(row)
                let i3 = i2 + 1
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }

        return MeshData(vertices: vertices, indices: indices)
    }
}
