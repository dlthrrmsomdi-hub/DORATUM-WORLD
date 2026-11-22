import Foundation
import SwiftUI
import Combine

public enum AppScreenState {
    case mainMenu
    case playing
    case paused
    case graphicsError(String)
}

@MainActor
public final class GameCoordinator: ObservableObject {
    public let engine: GameEngine

    @Published public var screenState: AppScreenState = .mainMenu
    @Published public var fps: Int = 60
    @Published public var locationName: String = "Downtown — Doratum Bay"
    @Published public var movementState: String = "Idle"
    @Published public var coordinatesText: String = "X: 0  Y: 2.2  Z: 18"
    @Published public var nearbyLandmarkTitle: String?
    @Published public var statusBannerMessage: String?

    @Published public var showSettingsSheet: Bool = false
    @Published public var showAboutSheet: Bool = false

    private var bannerDismissTask: Task<Void, Never>?

    public init() {
        let engine = GameEngine()
        self.engine = engine

        if let error = engine.initializationError {
            self.screenState = .graphicsError(error)
        } else {
            self.screenState = .mainMenu
        }

        engine.onTelemetryUpdate = { [weak self] telemetry in
            Task { @MainActor in
                guard let self else { return }
                self.fps = telemetry.fps
                self.locationName = telemetry.locationName
                self.movementState = telemetry.movementState
                self.coordinatesText = telemetry.coordinatesText
                self.nearbyLandmarkTitle = telemetry.nearbyPrompt
            }
        }

        engine.onInteractFeedback = { [weak self] message in
            Task { @MainActor in
                self?.showStatusBanner(message)
            }
        }
    }

    public func playGame() {
        guard engine.initializationError == nil else { return }
        engine.startGame()
        screenState = .playing
    }

    public func pauseGame() {
        guard case .playing = screenState else { return }
        engine.pauseGame()
        screenState = .paused
    }

    public func resumeGame() {
        guard case .paused = screenState else { return }
        engine.resumeGame()
        screenState = .playing
    }

    public func returnToMainMenu() {
        engine.returnToMainMenu()
        screenState = .mainMenu
    }

    public func saveNow() {
        let ok = engine.saveProgress()
        showStatusBanner(ok ? "Progress saved locally." : "Unable to save progress.")
    }

    public func resetSpawnPosition() {
        engine.resetWorldPosition()
        showStatusBanner("Player returned to Doratum Bay Plaza.")
    }

    public func resetCamera() {
        engine.inputController.triggerCameraReset()
    }

    public func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if case .playing = screenState {
                engine.pauseGame()
                screenState = .paused
            }
            engine.handleEnterBackground()
        case .inactive:
            engine.inputController.clearAll()
        case .active:
            engine.handleEnterForeground()
        @unknown default:
            break
        }
    }

    public func showStatusBanner(_ message: String) {
        bannerDismissTask?.cancel()
        statusBannerMessage = message
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.statusBannerMessage = nil
        }
    }
}
