import Foundation
import simd

public enum SurfaceMaterialType: String, CaseIterable, Codable {
    case concrete
    case asphalt
    case grass
    case sand
    case water
    case glass
    case metal
    case wood
    case foliage
    case skin
    case fabric
}

public struct GameMaterial {
    public let type: SurfaceMaterialType
    public var baseColor: SIMD4<Float>
    public var specular: Float
    public var shininess: Float
    public var roughness: Float
    public var emissive: Float

    public var materialParams: SIMD4<Float> {
        SIMD4<Float>(specular, shininess, roughness, emissive)
    }

    public init(
        type: SurfaceMaterialType,
        baseColor: SIMD4<Float>,
        specular: Float,
        shininess: Float,
        roughness: Float,
        emissive: Float = 0.0
    ) {
        self.type = type
        self.baseColor = baseColor
        self.specular = specular
        self.shininess = shininess
        self.roughness = roughness
        self.emissive = emissive
    }
}

public final class MaterialSystem {
    private var materials: [SurfaceMaterialType: GameMaterial] = [:]

    public init() {
        registerDefaults()
    }

    private func registerDefaults() {
        materials[.concrete] = GameMaterial(
            type: .concrete,
            baseColor: SIMD4<Float>(0.74, 0.75, 0.77, 1.0),
            specular: 0.14,
            shininess: 14.0,
            roughness: 0.82
        )
        materials[.asphalt] = GameMaterial(
            type: .asphalt,
            baseColor: SIMD4<Float>(0.21, 0.22, 0.24, 1.0),
            specular: 0.16,
            shininess: 18.0,
            roughness: 0.88
        )
        materials[.grass] = GameMaterial(
            type: .grass,
            baseColor: SIMD4<Float>(0.24, 0.56, 0.26, 1.0),
            specular: 0.08,
            shininess: 8.0,
            roughness: 0.92
        )
        materials[.sand] = GameMaterial(
            type: .sand,
            baseColor: SIMD4<Float>(0.86, 0.79, 0.60, 1.0),
            specular: 0.12,
            shininess: 10.0,
            roughness: 0.86
        )
        materials[.water] = GameMaterial(
            type: .water,
            baseColor: SIMD4<Float>(0.12, 0.52, 0.74, 0.86),
            specular: 0.95,
            shininess: 96.0,
            roughness: 0.12
        )
        materials[.glass] = GameMaterial(
            type: .glass,
            baseColor: SIMD4<Float>(0.42, 0.66, 0.84, 1.0),
            specular: 0.85,
            shininess: 64.0,
            roughness: 0.15,
            emissive: 0.06
        )
        materials[.metal] = GameMaterial(
            type: .metal,
            baseColor: SIMD4<Float>(0.54, 0.59, 0.65, 1.0),
            specular: 0.75,
            shininess: 48.0,
            roughness: 0.28
        )
        materials[.wood] = GameMaterial(
            type: .wood,
            baseColor: SIMD4<Float>(0.44, 0.29, 0.18, 1.0),
            specular: 0.16,
            shininess: 16.0,
            roughness: 0.78
        )
        materials[.foliage] = GameMaterial(
            type: .foliage,
            baseColor: SIMD4<Float>(0.18, 0.48, 0.22, 1.0),
            specular: 0.10,
            shininess: 10.0,
            roughness: 0.90
        )
        materials[.skin] = GameMaterial(
            type: .skin,
            baseColor: SIMD4<Float>(0.90, 0.74, 0.61, 1.0),
            specular: 0.18,
            shininess: 20.0,
            roughness: 0.55
        )
        materials[.fabric] = GameMaterial(
            type: .fabric,
            baseColor: SIMD4<Float>(0.18, 0.44, 0.78, 1.0),
            specular: 0.12,
            shininess: 12.0,
            roughness: 0.84
        )
    }

    public func material(for type: SurfaceMaterialType) -> GameMaterial {
        materials[type] ?? GameMaterial(
            type: type,
            baseColor: SIMD4<Float>(0.7, 0.7, 0.7, 1.0),
            specular: 0.2,
            shininess: 16.0,
            roughness: 0.7
        )
    }

    public func tinted(_ type: SurfaceMaterialType, color: SIMD4<Float>) -> GameMaterial {
        var mat = material(for: type)
        mat.baseColor = color
        return mat
    }
}
