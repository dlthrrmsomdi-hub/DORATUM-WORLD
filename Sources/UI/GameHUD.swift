import SwiftUI

public struct GameHUD: View {
    @ObservedObject public var coordinator: GameCoordinator
    @State private var sprintToggled: Bool = false

    public init(coordinator: GameCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        GeometryReader { geo in
            let isCompact = min(geo.size.width, geo.size.height) < 420
            let joystickSize: CGFloat = isCompact ? 116 : 138
            let actionSize: CGFloat = isCompact ? 56 : 66

            ZStack {
                // Right-half multi-touch camera drag & pinch surface behind buttons
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: geo.size.width * 0.36)
                        .allowsHitTesting(false)

                    CameraTouchPad(
                        onDragDelta: { delta in
                            coordinator.engine.inputController.addCameraDelta(delta)
                        },
                        onZoomDelta: { zoom in
                            coordinator.engine.inputController.addZoomDelta(zoom)
                        }
                    )
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Top HUD bar: Location, Player Status, FPS, Pause
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "location.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.35, green: 0.68, blue: 1.0))
                                Text(coordinator.locationName)
                                    .font(.system(size: isCompact ? 12 : 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            HStack(spacing: 10) {
                                Text(coordinator.movementState.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 0.45, green: 0.78, blue: 1.0))
                                Text(coordinator.coordinatesText)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.75))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.54))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )

                        Spacer()

                        // FPS Counter + Camera Reset + Pause Button
                        HStack(spacing: 8) {
                            Text("\(coordinator.fps) FPS")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(coordinator.fps >= 45 ? Color.green : Color.yellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.54))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )

                            Button {
                                coordinator.resetCamera()
                            } label: {
                                Image(systemName: "camera.rotate.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Color.black.opacity(0.54))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
                            }

                            Button {
                                coordinator.pauseGame()
                            } label: {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 38, height: 38)
                                    .background(Color(red: 0.14, green: 0.42, blue: 0.86).opacity(0.85))
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // Status or Landmark Toast Banner
                    if let banner = coordinator.statusBannerMessage {
                        Text(banner)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.08, green: 0.15, blue: 0.28).opacity(0.86))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.blue.opacity(0.5), lineWidth: 1))
                            .padding(.top, 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if let nearby = coordinator.nearbyLandmarkTitle {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                                .font(.caption)
                            Text("Near \(nearby) — Tap Interact")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(.top, 10)
                    }

                    Spacer()

                    // Bottom Controls: Left Joystick + Right Action Cluster
                    HStack(alignment: .bottom) {
                        VirtualJoystick(size: joystickSize) { vec in
                            coordinator.engine.inputController.setMoveVector(vec)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 12) {
                            HStack(spacing: 12) {
                                ActionButton(
                                    title: "SPRINT",
                                    systemImage: "figure.run",
                                    size: actionSize * 0.88,
                                    accentColor: Color.orange,
                                    isToggleActive: sprintToggled,
                                    onTap: {
                                        sprintToggled.toggle()
                                        coordinator.engine.inputController.setSprintPressed(sprintToggled)
                                    }
                                )

                                ActionButton(
                                    title: "INTERACT",
                                    systemImage: "sparkles",
                                    size: actionSize * 0.88,
                                    accentColor: Color.cyan,
                                    onTap: {
                                        coordinator.engine.inputController.triggerInteract()
                                    }
                                )
                            }

                            ActionButton(
                                title: "JUMP",
                                systemImage: "arrow.up",
                                size: actionSize * 1.08,
                                accentColor: Color(red: 0.20, green: 0.56, blue: 0.98),
                                onPressChanged: { pressed in
                                    coordinator.engine.inputController.setJumpPressed(pressed)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}
