import SwiftUI

public struct ActionButton: View {
    public let title: String
    public let systemImage: String
    public let size: CGFloat
    public let accentColor: Color
    public let isToggleActive: Bool
    public let onPressChanged: ((Bool) -> Void)?
    public let onTap: (() -> Void)?

    @State private var isPressed: Bool = false

    public init(
        title: String,
        systemImage: String,
        size: CGFloat = 62,
        accentColor: Color = Color(red: 0.20, green: 0.55, blue: 0.96),
        isToggleActive: Bool = false,
        onPressChanged: ((Bool) -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.size = size
        self.accentColor = accentColor
        self.isToggleActive = isToggleActive
        self.onPressChanged = onPressChanged
        self.onTap = onTap
    }

    private var highlighted: Bool {
        isPressed || isToggleActive
    }

    public var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.34, weight: .semibold))
            Text(title)
                .font(.system(size: max(9, size * 0.16), weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .frame(width: size, height: size)
        .background(
            Circle()
                .fill(highlighted ? accentColor.opacity(0.85) : Color.black.opacity(0.48))
        )
        .overlay(
            Circle()
                .stroke(highlighted ? Color.white.opacity(0.9) : Color.white.opacity(0.28), lineWidth: highlighted ? 2 : 1.5)
        )
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeOut(duration: 0.08), value: isPressed)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onPressChanged?(true)
                        onTap?()
                    }
                }
                .onEnded { _ in
                    if isPressed {
                        isPressed = false
                        onPressChanged?(false)
                    }
                }
        )
    }
}
