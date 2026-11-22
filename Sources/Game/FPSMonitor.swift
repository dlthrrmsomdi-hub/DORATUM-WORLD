import Foundation

public final class FPSMonitor {
    private var frameCount: Int = 0
    private var accumulatedTime: Double = 0.0
    public private(set) var currentFPS: Int = 60
    public private(set) var frameTimeMs: Double = 16.6

    public init() {}

    public func recordFrame(deltaTime: Double) {
        frameCount += 1
        accumulatedTime += deltaTime
        if accumulatedTime >= 0.35 {
            let avgDt = accumulatedTime / Double(max(frameCount, 1))
            frameTimeMs = avgDt * 1000.0
            currentFPS = Int((1.0 / max(avgDt, 0.0001)).rounded())
            frameCount = 0
            accumulatedTime = 0.0
        }
    }

    public func reset() {
        frameCount = 0
        accumulatedTime = 0.0
    }
}
