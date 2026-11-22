import SwiftUI

public struct PauseMenu: View {
    @ObservedObject public var coordinator: GameCoordinator

    public init(coordinator: GameCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("PAUSED")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundColor(.white)

                Text(coordinator.locationName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(red: 0.52, green: 0.78, blue: 1.0))
                    .padding(.bottom, 6)

                pauseButton(title: "RESUME", icon: "play.fill", primary: true) {
                    coordinator.resumeGame()
                }

                pauseButton(title: "SAVE GAME", icon: "square.and.arrow.down.fill", primary: false) {
                    coordinator.saveNow()
                }

                pauseButton(title: "RESET SPAWN", icon: "location.north.circle.fill", primary: false) {
                    coordinator.resetSpawnPosition()
                    coordinator.resumeGame()
                }

                pauseButton(title: "SETTINGS", icon: "slider.horizontal.3", primary: false) {
                    coordinator.showSettingsSheet = true
                }

                pauseButton(title: "RETURN TO MAIN MENU", icon: "house.fill", primary: false, destructive: true) {
                    coordinator.returnToMainMenu()
                }
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(Color(red: 0.08, green: 0.10, blue: 0.15).opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.blue.opacity(0.45), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.6), radius: 24)
            .padding(.horizontal, 20)
        }
    }

    private func pauseButton(
        title: String,
        icon: String,
        primary: Bool,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(1)
            }
            .foregroundColor(destructive ? Color(red: 1.0, green: 0.52, blue: 0.52) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                primary
                    ? Color(red: 0.14, green: 0.46, blue: 0.92)
                    : Color.white.opacity(0.10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(primary ? 0.35 : 0.14), lineWidth: 1)
            )
        }
    }
}
