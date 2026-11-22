import Foundation
import Combine

public enum GraphicsQuality: String, CaseIterable, Codable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    public var id: String { rawValue }

    public var chunkRadius: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    public var terrainSubdivisions: Int {
        switch self {
        case .low: return 12
        case .medium: return 18
        case .high: return 24
        }
    }

    public var maxRenderDistance: Float {
        switch self {
        case .low: return 130.0
        case .medium: return 210.0
        case .high: return 310.0
        }
    }

    public var qualityTierValue: Float {
        switch self {
        case .low: return 0.0
        case .medium: return 1.0
        case .high: return 2.0
        }
    }
}

public enum OutfitColorPreset: String, CaseIterable, Codable, Identifiable {
    case oceanBlue = "Ocean Blue"
    case slateGraphite = "Slate Graphite"
    case crimsonSport = "Crimson Sport"
    case forestGreen = "Forest Green"
    case sunsetGold = "Sunset Gold"

    public var id: String { rawValue }

    public var shirtRGBA: SIMD4<Float> {
        switch self {
        case .oceanBlue: return SIMD4<Float>(0.14, 0.44, 0.84, 1.0)
        case .slateGraphite: return SIMD4<Float>(0.24, 0.27, 0.33, 1.0)
        case .crimsonSport: return SIMD4<Float>(0.76, 0.18, 0.24, 1.0)
        case .forestGreen: return SIMD4<Float>(0.16, 0.52, 0.34, 1.0)
        case .sunsetGold: return SIMD4<Float>(0.86, 0.56, 0.16, 1.0)
        }
    }

    public var pantsRGBA: SIMD4<Float> {
        switch self {
        case .oceanBlue: return SIMD4<Float>(0.15, 0.20, 0.30, 1.0)
        case .slateGraphite: return SIMD4<Float>(0.13, 0.14, 0.17, 1.0)
        case .crimsonSport: return SIMD4<Float>(0.18, 0.19, 0.22, 1.0)
        case .forestGreen: return SIMD4<Float>(0.26, 0.23, 0.19, 1.0)
        case .sunsetGold: return SIMD4<Float>(0.17, 0.22, 0.32, 1.0)
        }
    }
}

public final class GameSettings: ObservableObject {
    private let defaults: UserDefaults

    private enum Keys {
        static let graphicsQuality = "doratum.settings.graphicsQuality"
        static let renderDistance = "doratum.settings.renderDistance"
        static let cameraSensitivity = "doratum.settings.cameraSensitivity"
        static let controlSensitivity = "doratum.settings.controlSensitivity"
        static let musicVolume = "doratum.settings.musicVolume"
        static let soundVolume = "doratum.settings.soundVolume"
        static let fpsLimit = "doratum.settings.fpsLimit"
        static let outfitPreset = "doratum.settings.outfitPreset"
    }

    @Published public var graphicsQuality: GraphicsQuality {
        didSet {
            defaults.set(graphicsQuality.rawValue, forKey: Keys.graphicsQuality)
            if renderDistance > graphicsQuality.maxRenderDistance {
                renderDistance = graphicsQuality.maxRenderDistance
            }
            onSettingsChanged?()
        }
    }

    @Published public var renderDistance: Float {
        didSet {
            let clamped = Math3D.clamp(renderDistance, min: 80.0, max: 320.0)
            if clamped != renderDistance {
                renderDistance = clamped
                return
            }
            defaults.set(renderDistance, forKey: Keys.renderDistance)
            onSettingsChanged?()
        }
    }

    @Published public var cameraSensitivity: Float {
        didSet {
            let clamped = Math3D.clamp(cameraSensitivity, min: 0.2, max: 2.5)
            if clamped != cameraSensitivity {
                cameraSensitivity = clamped
                return
            }
            defaults.set(cameraSensitivity, forKey: Keys.cameraSensitivity)
            onSettingsChanged?()
        }
    }

    @Published public var controlSensitivity: Float {
        didSet {
            let clamped = Math3D.clamp(controlSensitivity, min: 0.4, max: 2.0)
            if clamped != controlSensitivity {
                controlSensitivity = clamped
                return
            }
            defaults.set(controlSensitivity, forKey: Keys.controlSensitivity)
            onSettingsChanged?()
        }
    }

    @Published public var musicVolume: Float {
        didSet {
            defaults.set(Math3D.clamp(musicVolume, min: 0.0, max: 1.0), forKey: Keys.musicVolume)
            onSettingsChanged?()
        }
    }

    @Published public var soundVolume: Float {
        didSet {
            defaults.set(Math3D.clamp(soundVolume, min: 0.0, max: 1.0), forKey: Keys.soundVolume)
            onSettingsChanged?()
        }
    }

    @Published public var fpsLimit: Int {
        didSet {
            let valid = (fpsLimit <= 30) ? 30 : 60
            if valid != fpsLimit {
                fpsLimit = valid
                return
            }
            defaults.set(fpsLimit, forKey: Keys.fpsLimit)
            onSettingsChanged?()
        }
    }

    @Published public var outfitPreset: OutfitColorPreset {
        didSet {
            defaults.set(outfitPreset.rawValue, forKey: Keys.outfitPreset)
            onSettingsChanged?()
        }
    }

    public var onSettingsChanged: (() -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let savedQuality = defaults.string(forKey: Keys.graphicsQuality).flatMap(GraphicsQuality.init(rawValue:)) ?? .medium
        self.graphicsQuality = savedQuality

        let savedDist = defaults.object(forKey: Keys.renderDistance) as? Float
        self.renderDistance = Math3D.clamp(savedDist ?? savedQuality.maxRenderDistance, min: 80.0, max: 320.0)

        let savedCamSens = defaults.object(forKey: Keys.cameraSensitivity) as? Float
        self.cameraSensitivity = Math3D.clamp(savedCamSens ?? 1.0, min: 0.2, max: 2.5)

        let savedCtrlSens = defaults.object(forKey: Keys.controlSensitivity) as? Float
        self.controlSensitivity = Math3D.clamp(savedCtrlSens ?? 1.0, min: 0.4, max: 2.0)

        let savedMusic = defaults.object(forKey: Keys.musicVolume) as? Float
        self.musicVolume = Math3D.clamp(savedMusic ?? 0.6, min: 0.0, max: 1.0)

        let savedSound = defaults.object(forKey: Keys.soundVolume) as? Float
        self.soundVolume = Math3D.clamp(savedSound ?? 0.8, min: 0.0, max: 1.0)

        let savedFPS = defaults.integer(forKey: Keys.fpsLimit)
        self.fpsLimit = (savedFPS == 30 || savedFPS == 60) ? savedFPS : 60

        let savedOutfit = defaults.string(forKey: Keys.outfitPreset).flatMap(OutfitColorPreset.init(rawValue:)) ?? .oceanBlue
        self.outfitPreset = savedOutfit
    }

    public func resetToDefaults() {
        graphicsQuality = .medium
        renderDistance = GraphicsQuality.medium.maxRenderDistance
        cameraSensitivity = 1.0
        controlSensitivity = 1.0
        musicVolume = 0.6
        soundVolume = 0.8
        fpsLimit = 60
        outfitPreset = .oceanBlue
    }
}
