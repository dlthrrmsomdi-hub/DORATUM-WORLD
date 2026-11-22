import Foundation
import simd

public final class InputController {
    private let lock = NSLock()

    private var _moveVector: SIMD2<Float> = .zero
    private var _cameraDelta: SIMD2<Float> = .zero
    private var _zoomDelta: Float = 0.0
    private var _jumpQueued: Bool = false
    private var _isJumpHeld: Bool = false
    private var _isSprintHeld: Bool = false
    private var _interactQueued: Bool = false
    private var _cameraResetQueued: Bool = false

    public init() {}

    public func setMoveVector(_ vector: SIMD2<Float>) {
        lock.lock()
        let len = simd_length(vector)
        _moveVector = len > 1.0 ? vector / len : vector
        lock.unlock()
    }

    public func addCameraDelta(_ delta: SIMD2<Float>) {
        lock.lock()
        _cameraDelta += delta
        lock.unlock()
    }

    public func addZoomDelta(_ delta: Float) {
        lock.lock()
        _zoomDelta += delta
        lock.unlock()
    }

    public func setJumpPressed(_ pressed: Bool) {
        lock.lock()
        if pressed && !_isJumpHeld {
            _jumpQueued = true
        }
        _isJumpHeld = pressed
        lock.unlock()
    }

    public func setSprintPressed(_ pressed: Bool) {
        lock.lock()
        _isSprintHeld = pressed
        lock.unlock()
    }

    public func triggerInteract() {
        lock.lock()
        _interactQueued = true
        lock.unlock()
    }

    public func triggerCameraReset() {
        lock.lock()
        _cameraResetQueued = true
        lock.unlock()
    }

    public func clearAll() {
        lock.lock()
        _moveVector = .zero
        _cameraDelta = .zero
        _zoomDelta = 0.0
        _jumpQueued = false
        _isJumpHeld = false
        _isSprintHeld = false
        _interactQueued = false
        _cameraResetQueued = false
        lock.unlock()
    }

    public struct FrameInputSnapshot {
        public let moveVector: SIMD2<Float>
        public let cameraDelta: SIMD2<Float>
        public let zoomDelta: Float
        public let jumpTriggered: Bool
        public let sprintActive: Bool
        public let interactTriggered: Bool
        public let cameraResetTriggered: Bool
    }

    public func consumeFrameSnapshot() -> FrameInputSnapshot {
        lock.lock()
        let snap = FrameInputSnapshot(
            moveVector: _moveVector,
            cameraDelta: _cameraDelta,
            zoomDelta: _zoomDelta,
            jumpTriggered: _jumpQueued,
            sprintActive: _isSprintHeld,
            interactTriggered: _interactQueued,
            cameraResetTriggered: _cameraResetQueued
        )
        _cameraDelta = .zero
        _zoomDelta = 0.0
        _jumpQueued = false
        _interactQueued = false
        _cameraResetQueued = false
        lock.unlock()
        return snap
    }
}
