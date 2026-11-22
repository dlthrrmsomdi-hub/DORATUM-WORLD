import Foundation
import QuartzCore
import simd

public struct HUDTelemetry {
    public let fps: Int
    public let locationName: String
    public let movementState: String
    public let nearbyPrompt: String?
    public let coordinatesText: String
    public let drawCalls: Int
}

public final class GameEngine {
    public let settings: GameSettings
    public let saveManager: SaveManager
    public let inputController: InputController
    public let fpsMonitor: FPSMonitor
    public let scene: WorldScene

    public private(set) var renderer: GameRenderer?
    public private(set) var initializationError: String?

    public var isPaused: Bool = true
    public var isInMainMenu: Bool = true

    private var lastFrameTimestamp: CFTimeInterval = 0
    private var physicsAccumulator: Float = 0
    private let fixedTimeStep: Float = 1.0 / 60.0
    private let maxDeltaTime: Float = 0.05
    private var hudNotifyAccumulator: Float = 0
    private var autoSaveAccumulator: Float = 0

    public var onTelemetryUpdate: ((HUDTelemetry) -> Void)?
    public var onInteractFeedback: ((String) -> Void)?

    public init() {
        self.settings = GameSettings()
        self.saveManager = SaveManager()
        self.inputController = InputController()
        self.fpsMonitor = FPSMonitor()

        let loadedSave = saveManager.load()
        self.scene = WorldScene(saveData: loadedSave, settings: settings)

        self.settings.onSettingsChanged = { [weak self] in
            self?.applySettings()
        }

        do {
            let metalRenderer = try GameRenderer(engine: self)
            self.renderer = metalRenderer
            self.scene.buildSharedGPUResources(device: metalRenderer.device, quality: settings.graphicsQuality)
        } catch {
            self.initializationError = error.localizedDescription
            print("[GameEngine] Metal initialization failed: \(error.localizedDescription)")
        }
    }

    public func applySettings() {
        scene.playerController.model.applyOutfit(settings.outfitPreset)
        scene.chunkManager.updateChunks(around: scene.playerController.position, quality: settings.graphicsQuality)
    }

    public func startGame() {
        isInMainMenu = false
        isPaused = false
        lastFrameTimestamp = CACurrentMediaTime()
        physicsAccumulator = 0
        inputController.clearAll()
    }

    public func pauseGame() {
        isPaused = true
        inputController.clearAll()
        saveProgress()
    }

    public func resumeGame() {
        isPaused = false
        lastFrameTimestamp = CACurrentMediaTime()
        physicsAccumulator = 0
    }

    public func returnToMainMenu() {
        saveProgress()
        isPaused = true
        isInMainMenu = true
        inputController.clearAll()
    }

    public func resetWorldPosition() {
        saveManager.resetSave()
        let def = PlayerSaveData.defaultSpawn
        let groundY = scene.worldGenerator.terrainHeight(at: def.posX, z: def.posZ)
        scene.playerController.teleport(to: SIMD3<Float>(def.posX, groundY + 0.1, def.posZ), yaw: def.yaw)
        scene.cameraController.configure(yaw: def.cameraYaw, pitch: def.cameraPitch, distance: def.cameraDistance, focusPoint: scene.playerController.position)
        scene.chunkManager.updateChunks(around: scene.playerController.position, quality: settings.graphicsQuality)
    }

    @discardableResult
    public func saveProgress() -> Bool {
        let data = scene.makeSaveData()
        return saveManager.save(data)
    }

    public func handleEnterBackground() {
        saveProgress()
        inputController.clearAll()
        scene.chunkManager.releaseMemory()
        lastFrameTimestamp = 0
    }

    public func handleEnterForeground() {
        lastFrameTimestamp = CACurrentMediaTime()
        physicsAccumulator = 0
        fpsMonitor.reset()
    }

    /// Called once per display frame by GameRenderer.
    public func tickFrame() {
        let now = CACurrentMediaTime()
        if lastFrameTimestamp == 0 {
            lastFrameTimestamp = now
            return
        }

        let rawDt = now - lastFrameTimestamp
        lastFrameTimestamp = now
        fpsMonitor.recordFrame(deltaTime: max(rawDt, 0.0001))

        // Clamp delta time to protect against huge spikes after returning from background
        let dt = Math3D.clamp(Float(rawDt), min: 0.0001, max: maxDeltaTime)

        if isInMainMenu {
            // Gentle cinematic orbit around player while on main menu
            let idleSnap = InputController.FrameInputSnapshot(
                moveVector: .zero,
                cameraDelta: SIMD2<Float>(dt * 12.0, 0),
                zoomDelta: 0,
                jumpTriggered: false,
                sprintActive: false,
                interactTriggered: false,
                cameraResetTriggered: false
            )
            scene.updateVariableSystems(dt: dt, input: idleSnap, settings: settings)
            return
        }

        if isPaused {
            return
        }

        let input = inputController.consumeFrameSnapshot()

        // Fixed time-step physics loop
        physicsAccumulator += dt
        var subSteps = 0
        var jumpConsumed = false
        while physicsAccumulator >= fixedTimeStep && subSteps < 4 {
            let stepInput = InputController.FrameInputSnapshot(
                moveVector: input.moveVector,
                cameraDelta: .zero,
                zoomDelta: 0,
                jumpTriggered: input.jumpTriggered && !jumpConsumed,
                sprintActive: input.sprintActive,
                interactTriggered: false,
                cameraResetTriggered: false
            )
            jumpConsumed = true
            scene.stepFixedPhysics(
                input: stepInput,
                controlSensitivity: settings.controlSensitivity,
                fixedDt: fixedTimeStep
            )
            physicsAccumulator -= fixedTimeStep
            subSteps += 1
        }

        // Variable time-step animation, lighting, camera, and chunk streaming
        scene.updateVariableSystems(dt: dt, input: input, settings: settings)

        // Interact button handling
        if input.interactTriggered {
            if let landmark = scene.nearbyInteractable() {
                onInteractFeedback?(landmark.message)
            } else {
                let loc = scene.currentLocationLabel()
                onInteractFeedback?("Exploring \(loc). Walk toward plazas, parks, or the boardwalk to discover landmarks.")
            }
        }

        // Periodic auto-save every 25 seconds
        autoSaveAccumulator += dt
        if autoSaveAccumulator >= 25.0 {
            autoSaveAccumulator = 0
            saveProgress()
        }

        // Throttled HUD updates (10 Hz) to avoid unnecessary SwiftUI redraws
        hudNotifyAccumulator += dt
        if hudNotifyAccumulator >= 0.10 {
            hudNotifyAccumulator = 0
            let pos = scene.playerController.position
            let telemetry = HUDTelemetry(
                fps: fpsMonitor.currentFPS,
                locationName: scene.currentLocationLabel(),
                movementState: scene.playerController.movementState.rawValue,
                nearbyPrompt: scene.nearbyInteractable()?.title,
                coordinatesText: String(format: "X: %.0f  Y: %.1f  Z: %.0f", pos.x, pos.y, pos.z),
                drawCalls: renderer?.lastDrawCallCount ?? 0
            )
            onTelemetryUpdate?(telemetry)
        }
    }
}
