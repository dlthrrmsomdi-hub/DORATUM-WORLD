import SwiftUI

public struct ContentView: View {
    @StateObject private var coordinator = GameCoordinator()

    public init() {}

    public var body: some View {
        GameRootContainer(
            coordinator: coordinator,
            settings: coordinator.engine.settings
        )
    }
}

private struct GameRootContainer: View {
    @ObservedObject var coordinator: GameCoordinator
    @ObservedObject var settings: GameSettings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if let renderer = coordinator.engine.renderer {
                MetalGameView(
                    renderer: renderer,
                    fpsLimit: settings.fpsLimit,
                    isPaused: isRendererPaused
                )
                .ignoresSafeArea()
            } else {
                Color(red: 0.05, green: 0.07, blue: 0.11)
                    .ignoresSafeArea()
            }

            switch coordinator.screenState {
            case .mainMenu:
                MainMenuView(coordinator: coordinator)

            case .playing:
                GameHUD(coordinator: coordinator)

            case .paused:
                GameHUD(coordinator: coordinator)
                    .allowsHitTesting(false)
                PauseMenu(coordinator: coordinator)

            case .graphicsError(let message):
                GraphicsErrorView(message: message)
            }
        }
        .statusBarHidden(isStatusBarHidden)
        .sheet(isPresented: $coordinator.showSettingsSheet) {
            SettingsView(settings: settings)
        }
        .onChange(of: scenePhase) { newPhase in
            coordinator.handleScenePhase(newPhase)
        }
    }

    private var isRendererPaused: Bool {
        switch coordinator.screenState {
        case .paused, .graphicsError:
            return true
        case .mainMenu, .playing:
            return false
        }
    }

    private var isStatusBarHidden: Bool {
        if case .playing = coordinator.screenState {
            return true
        }
        return false
    }
}

private struct GraphicsErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)

            Text("Graphics Engine Unavailable")
                .font(.title2.bold())
                .foregroundColor(.white)

            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("DORATUM WORLD requires an iPhone or iPad with Apple Metal GPU support running iOS 16.0 or later.")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(28)
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
        )
        .padding(24)
    }
}
