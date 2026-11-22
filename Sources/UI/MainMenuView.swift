import SwiftUI

public struct MainMenuView: View {
    @ObservedObject public var coordinator: GameCoordinator
    @State private var showExitAlert: Bool = false

    public init(coordinator: GameCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            // Subtle dark slate-blue translucent vignette over live 3D Metal Doratum Bay backdrop
            LinearGradient(
                colors: [
                    Color.black.opacity(0.76),
                    Color(red: 0.06, green: 0.11, blue: 0.20).opacity(0.62),
                    Color.black.opacity(0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Game Logo & Identity
                VStack(spacing: 8) {
                    Text("DORATUM BAY")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(5)
                        .foregroundColor(Color(red: 0.42, green: 0.74, blue: 1.0))

                    Text("DORATUM WORLD")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, Color(red: 0.70, green: 0.86, blue: 1.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .multilineTextAlignment(.center)
                        .shadow(color: Color.blue.opacity(0.45), radius: 14)

                    Text("3D Open World Sandbox • Apple Metal Engine")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.72))
                }

                // Menu Actions
                VStack(spacing: 12) {
                    menuButton(
                        title: "PLAY",
                        icon: "play.fill",
                        primary: true
                    ) {
                        coordinator.playGame()
                    }

                    menuButton(
                        title: "SETTINGS",
                        icon: "slider.horizontal.3",
                        primary: false
                    ) {
                        coordinator.showSettingsSheet = true
                    }

                    menuButton(
                        title: "ABOUT",
                        icon: "info.circle",
                        primary: false
                    ) {
                        coordinator.showAboutSheet = true
                    }

                    menuButton(
                        title: "EXIT",
                        icon: "rectangle.portrait.and.arrow.right",
                        primary: false
                    ) {
                        showExitAlert = true
                    }
                }
                .frame(maxWidth: 320)

                Spacer()

                Text("iOS & iPadOS • Native Swift + Metal")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .alert("Exit DORATUM WORLD", isPresented: $showExitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("On iOS and iPadOS, swipe up from the bottom edge (or press the Home button) to return to the Home Screen. Your progress is automatically saved.")
        }
        .sheet(isPresented: $coordinator.showAboutSheet) {
            AboutWorldView()
        }
    }

    private func menuButton(title: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, primary ? 15 : 13)
            .background(
                primary
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color(red: 0.14, green: 0.48, blue: 0.94), Color(red: 0.08, green: 0.30, blue: 0.72)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    : AnyShapeStyle(Color(white: 0.16).opacity(0.76))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(primary ? Color.white.opacity(0.45) : Color.white.opacity(0.18), lineWidth: 1.2)
            )
        }
    }
}

private struct AboutWorldView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("World") {
                    Text("DORATUM WORLD is a native 3D open-world sandbox set in Doratum Bay, featuring Downtown skyscrapers, Residential avenues, Coastal beaches, and Westside Park.")
                }
                Section("Controls") {
                    Label("Left Joystick: Walk & Run", systemImage: "dpad")
                    Label("Right Screen Drag: Orbit Camera", systemImage: "hand.draw")
                    Label("Pinch Right Side: Zoom Camera", systemImage: "arrow.up.left.and.arrow.down.right")
                    Label("Jump / Sprint / Interact Buttons", systemImage: "gamecontroller")
                }
                Section("Technology") {
                    LabeledContent("Graphics API", value: "Apple Metal + MetalKit")
                    LabeledContent("UI Framework", value: "SwiftUI")
                    LabeledContent("Architecture", value: "Custom 3D Chunk Engine")
                    LabeledContent("Project Owner", value: "DORATUM")
                }
            }
            .navigationTitle("About DORATUM WORLD")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
