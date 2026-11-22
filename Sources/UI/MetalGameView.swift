import SwiftUI
import MetalKit

public struct MetalGameView: UIViewRepresentable {
    public let renderer: GameRenderer
    public let fpsLimit: Int
    public let isPaused: Bool

    public init(renderer: GameRenderer, fpsLimit: Int, isPaused: Bool) {
        self.renderer = renderer
        self.fpsLimit = fpsLimit
        self.isPaused = isPaused
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = renderer.device
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearDepth = 1.0
        view.preferredFramesPerSecond = fpsLimit
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.delegate = renderer
        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        if uiView.preferredFramesPerSecond != fpsLimit {
            uiView.preferredFramesPerSecond = fpsLimit
        }
        // Keep rendering the static paused frame at low rate or pause cleanly
        uiView.isPaused = isPaused
    }
}
