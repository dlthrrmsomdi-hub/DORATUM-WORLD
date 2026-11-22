import Foundation
import Metal
import simd

public final class LightingSystem {
    // Time of day in hours [0, 24), starting at pleasant late morning (10.5)
    public private(set) var timeOfDay: Float = 10.5
    public var cycleSpeed: Float = 0.045 // gentle dynamic sun drift

    public private(set) var sunDirection: SIMD3<Float> = simd_normalize(SIMD3<Float>(0.45, 0.82, 0.35))
    public private(set) var sunColor: SIMD3<Float> = SIMD3<Float>(1.0, 0.96, 0.88)
    public private(set) var sunIntensity: Float = 1.05
    public private(set) var ambientColor: SIMD3<Float> = SIMD3<Float>(0.56, 0.70, 0.88)
    public private(set) var ambientIntensity: Float = 0.42
    public private(set) var skyColor: SIMD4<Float> = SIMD4<Float>(0.53, 0.75, 0.95, 1.0)
    public private(set) var fogColor: SIMD3<Float> = SIMD3<Float>(0.68, 0.82, 0.94)
    public private(set) var fogDensity: Float = 0.0032

    public init() {
        updateLightingParameters()
    }

    public func update(deltaTime: Float) {
        timeOfDay += deltaTime * cycleSpeed
        if timeOfDay >= 17.5 {
            // Keep Doratum Bay in vibrant daylight to golden-hour cycle so world stays clearly visible
            timeOfDay = 7.2
        }
        updateLightingParameters()
    }

    private func updateLightingParameters() {
        // Map [7.2, 17.5] to sun elevation angle
        let normalizedDay = Math3D.clamp((timeOfDay - 6.0) / 12.0, min: 0.08, max: 0.92)
        let angle = normalizedDay * .pi
        let elevation = sin(angle)
        let azimuth = cos(angle)

        sunDirection = simd_normalize(SIMD3<Float>(azimuth * 0.85, max(0.28, elevation), 0.38))

        // Blend warm morning/golden-hour tones with crisp midday tones
        let warmth = Math3D.clamp(1.0 - elevation * 1.15, min: 0.0, max: 1.0)
        sunColor = simd_mix(
            SIMD3<Float>(1.0, 0.97, 0.92),
            SIMD3<Float>(1.0, 0.78, 0.56),
            SIMD3<Float>(repeating: warmth)
        )
        sunIntensity = Math3D.lerp(1.08, 0.86, warmth)

        ambientColor = simd_mix(
            SIMD3<Float>(0.56, 0.72, 0.92),
            SIMD3<Float>(0.62, 0.54, 0.64),
            SIMD3<Float>(repeating: warmth)
        )
        ambientIntensity = Math3D.lerp(0.42, 0.36, warmth)

        let skyRGB = simd_mix(
            SIMD3<Float>(0.48, 0.73, 0.95),
            SIMD3<Float>(0.82, 0.63, 0.54),
            SIMD3<Float>(repeating: warmth)
        )
        skyColor = SIMD4<Float>(skyRGB.x, skyRGB.y, skyRGB.z, 1.0)

        fogColor = simd_mix(
            SIMD3<Float>(0.66, 0.81, 0.94),
            SIMD3<Float>(0.85, 0.70, 0.60),
            SIMD3<Float>(repeating: warmth)
        )
    }

    public var clearColor: MTLClearColor {
        MTLClearColor(
            red: Double(skyColor.x),
            green: Double(skyColor.y),
            blue: Double(skyColor.z),
            alpha: 1.0
        )
    }

    public func makeFrameUniforms(
        viewProjection: simd_float4x4,
        cameraPosition: SIMD3<Float>,
        elapsedTime: Float,
        renderDistance: Float,
        qualityTier: Float
    ) -> FrameUniforms {
        let fogStart = max(35.0, renderDistance * 0.42)
        let fogEnd = max(fogStart + 40.0, renderDistance * 0.98)
        return FrameUniforms(
            viewProjectionMatrix: viewProjection,
            cameraPosition: SIMD4<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z, elapsedTime),
            sunDirection: SIMD4<Float>(sunDirection.x, sunDirection.y, sunDirection.z, sunIntensity),
            sunColor: SIMD4<Float>(sunColor.x, sunColor.y, sunColor.z, ambientIntensity),
            ambientColor: SIMD4<Float>(ambientColor.x, ambientColor.y, ambientColor.z, fogDensity),
            fogColor: SIMD4<Float>(fogColor.x, fogColor.y, fogColor.z, fogStart),
            fogParams: SIMD4<Float>(fogEnd, 0.0, qualityTier, 0.0)
        )
    }
}
