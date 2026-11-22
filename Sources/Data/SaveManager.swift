import Foundation
import simd

public struct PlayerSaveData: Codable {
    public var posX: Float
    public var posY: Float
    public var posZ: Float
    public var yaw: Float
    public var cameraYaw: Float
    public var cameraPitch: Float
    public var cameraDistance: Float
    public var lastKnownLocation: String
    public var savedTimestamp: TimeInterval

    public var position: SIMD3<Float> {
        SIMD3<Float>(posX, posY, posZ)
    }

    public static let defaultSpawn = PlayerSaveData(
        posX: 0.0,
        posY: 2.4,
        posZ: 18.0,
        yaw: 0.0,
        cameraYaw: 0.0,
        cameraPitch: 0.28,
        cameraDistance: 7.5,
        lastKnownLocation: "Downtown Plaza — Doratum Bay",
        savedTimestamp: Date().timeIntervalSince1970
    )

    public func isValid(worldHalfExtent: Float) -> Bool {
        guard
            posX.isFinite, posY.isFinite, posZ.isFinite,
            yaw.isFinite, cameraYaw.isFinite, cameraPitch.isFinite, cameraDistance.isFinite
        else {
            return false
        }
        if abs(posX) > worldHalfExtent || abs(posZ) > worldHalfExtent {
            return false
        }
        if posY < -5.0 || posY > 120.0 {
            return false
        }
        return true
    }
}

public final class SaveManager {
    private let fileManager: FileManager
    private let saveFileName = "doratum_world_save.json"

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    private func saveFileURL() -> URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("DORATUM_WORLD", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                print("[SaveManager] Failed to create save directory: \(error.localizedDescription)")
                return nil
            }
        }
        return dir.appendingPathComponent(saveFileName)
    }

    @discardableResult
    public func save(_ data: PlayerSaveData) -> Bool {
        guard let url = saveFileURL() else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded = try encoder.encode(data)
            try encoded.write(to: url, options: .atomic)
            return true
        } catch {
            print("[SaveManager] Failed to write save file: \(error.localizedDescription)")
            return false
        }
    }

    public func load(worldHalfExtent: Float = 380.0) -> PlayerSaveData {
        guard let url = saveFileURL(), fileManager.fileExists(atPath: url.path) else {
            return .defaultSpawn
        }
        do {
            let raw = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(PlayerSaveData.self, from: raw)
            if decoded.isValid(worldHalfExtent: worldHalfExtent) {
                return decoded
            } else {
                print("[SaveManager] Loaded save data failed validation; reverting to default spawn.")
                return .defaultSpawn
            }
        } catch {
            print("[SaveManager] Corrupted or unreadable save file (\(error.localizedDescription)); using default spawn.")
            return .defaultSpawn
        }
    }

    public func resetSave() {
        guard let url = saveFileURL(), fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            print("[SaveManager] Failed to remove save file: \(error.localizedDescription)")
        }
    }
}
