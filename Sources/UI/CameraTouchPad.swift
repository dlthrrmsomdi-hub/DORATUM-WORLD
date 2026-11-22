import SwiftUI
import UIKit
import simd

public struct CameraTouchPad: UIViewRepresentable {
    public let onDragDelta: (SIMD2<Float>) -> Void
    public let onZoomDelta: (Float) -> Void

    public init(
        onDragDelta: @escaping (SIMD2<Float>) -> Void,
        onZoomDelta: @escaping (Float) -> Void
    ) {
        self.onDragDelta = onDragDelta
        self.onZoomDelta = onZoomDelta
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onDragDelta: onDragDelta, onZoomDelta: onZoomDelta)
    }

    public func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDragDelta = onDragDelta
        context.coordinator.onZoomDelta = onZoomDelta
    }

    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDragDelta: (SIMD2<Float>) -> Void
        var onZoomDelta: (Float) -> Void
        private var lastScale: CGFloat = 1.0

        init(onDragDelta: @escaping (SIMD2<Float>) -> Void, onZoomDelta: @escaping (Float) -> Void) {
            self.onDragDelta = onDragDelta
            self.onZoomDelta = onZoomDelta
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            if gesture.state == .changed {
                onDragDelta(SIMD2<Float>(Float(translation.x), Float(translation.y)))
                gesture.setTranslation(.zero, in: view)
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastScale = 1.0
            case .changed:
                let delta = Float(gesture.scale - lastScale)
                lastScale = gesture.scale
                onZoomDelta(delta)
            default:
                lastScale = 1.0
            }
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
