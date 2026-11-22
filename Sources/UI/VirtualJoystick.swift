import SwiftUI
import simd

public struct VirtualJoystick: View {
    public let size: CGFloat
    public let onMoveChanged: (SIMD2<Float>) -> Void

    @State private var knobOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    public init(size: CGFloat = 132, onMoveChanged: @escaping (SIMD2<Float>) -> Void) {
        self.size = size
        self.onMoveChanged = onMoveChanged
    }

    private var maxRadius: CGFloat {
        size * 0.36
    }

    public var body: some View {
        ZStack {
            // Outer base ring
            Circle()
                .fill(Color.black.opacity(0.40))
                .overlay(
                    Circle()
                        .stroke(isDragging ? Color.blue.opacity(0.85) : Color.white.opacity(0.28), lineWidth: 2)
                )

            // Directional tick markers
            Circle()
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                .frame(width: size * 0.68, height: size * 0.68)

            // Draggable thumbstick knob
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.30, green: 0.62, blue: 0.98).opacity(isDragging ? 0.95 : 0.78),
                            Color(red: 0.10, green: 0.24, blue: 0.48).opacity(0.92)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.24
                    )
                )
                .frame(width: size * 0.42, height: size * 0.42)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.65), lineWidth: 1.5)
                )
                .shadow(color: Color.blue.opacity(0.35), radius: 6)
                .offset(knobOffset)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let dx = value.location.x - size * 0.5
                    let dy = value.location.y - size * 0.5
                    let dist = hypot(dx, dy)
                    let clampedDist = min(dist, maxRadius)
                    let angle = atan2(dy, dx)

                    let clampedX = cos(angle) * clampedDist
                    let clampedY = sin(angle) * clampedDist
                    knobOffset = CGSize(width: clampedX, height: clampedY)

                    let normX = Float(clampedX / max(maxRadius, 1))
                    // Screen Y increases downward; joystick forward is +Y
                    let normY = Float(-clampedY / max(maxRadius, 1))
                    onMoveChanged(SIMD2<Float>(normX, normY))
                }
                .onEnded { _ in
                    isDragging = false
                    withAnimation(.spring(response: 0.18, dampingFraction: 0.72)) {
                        knobOffset = .zero
                    }
                    onMoveChanged(.zero)
                }
        )
    }
}
