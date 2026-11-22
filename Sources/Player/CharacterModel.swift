import Foundation
import Metal
import simd

public struct CharacterPartRenderItem {
    public let mesh: GPUMesh
    public let modelUniforms: ModelUniforms
}

public final class CharacterModel {
    private var headMesh: GPUMesh?
    private var hairMesh: GPUMesh?
    private var torsoMesh: GPUMesh?
    private var armMesh: GPUMesh?
    private var handMesh: GPUMesh?
    private var legMesh: GPUMesh?
    private var footMesh: GPUMesh?

    public var skinColor = SIMD4<Float>(0.91, 0.74, 0.60, 1.0)
    public var hairColor = SIMD4<Float>(0.16, 0.13, 0.11, 1.0)
    public var shirtColor = SIMD4<Float>(0.14, 0.44, 0.84, 1.0)
    public var pantsColor = SIMD4<Float>(0.15, 0.20, 0.30, 1.0)
    public var shoeColor = SIMD4<Float>(0.90, 0.91, 0.93, 1.0)

    private let meshFactory: MeshFactory
    private let materialSystem: MaterialSystem

    public init(meshFactory: MeshFactory, materialSystem: MaterialSystem) {
        self.meshFactory = meshFactory
        self.materialSystem = materialSystem
    }

    public func applyOutfit(_ preset: OutfitColorPreset) {
        shirtColor = preset.shirtRGBA
        pantsColor = preset.pantsRGBA
    }

    public func buildGPUResources(device: MTLDevice) {
        guard headMesh == nil else { return }

        headMesh = GPUMesh(device: device, meshData: meshFactory.makeSphereMesh(radius: 0.21, stacks: 8, slices: 12), label: "Player_Head")
        hairMesh = GPUMesh(device: device, meshData: meshFactory.makeBoxMesh(size: SIMD3<Float>(0.42, 0.14, 0.42)), label: "Player_Hair")
        torsoMesh = GPUMesh(device: device, meshData: meshFactory.makeBoxMesh(size: SIMD3<Float>(0.50, 0.64, 0.28)), label: "Player_Torso")
        armMesh = GPUMesh(device: device, meshData: meshFactory.makeBoxMesh(size: SIMD3<Float>(0.15, 0.50, 0.15)), label: "Player_Arm")
        handMesh = GPUMesh(device: device, meshData: meshFactory.makeBoxMesh(size: SIMD3<Float>(0.13, 0.13, 0.13)), label: "Player_Hand")
        legMesh = GPUMesh(device: device, meshData: meshFactory.makeBoxMesh(size: SIMD3<Float>(0.18, 0.62, 0.19)), label: "Player_Leg")
        footMesh = GPUMesh(device: device, meshData: meshFactory.makeBoxMesh(size: SIMD3<Float>(0.19, 0.12, 0.30)), label: "Player_Foot")
    }

    public func buildRenderItems(
        worldPosition: SIMD3<Float>,
        yaw: Float,
        pose: CharacterPose
    ) -> [CharacterPartRenderItem] {
        guard
            let headMesh, let hairMesh, let torsoMesh,
            let armMesh, let handMesh, let legMesh, let footMesh
        else {
            return []
        }

        let skinParams = materialSystem.material(for: .skin).materialParams
        let fabricParams = materialSystem.material(for: .fabric).materialParams
        let shoeParams = materialSystem.material(for: .concrete).materialParams

        let root = Math3D.translation(worldPosition + SIMD3<Float>(0, pose.bodyBobY, 0)) * Math3D.rotationY(yaw)

        // Torso & Head
        let pelvisY: Float = 0.78
        let torsoPivot = root * Math3D.translation(SIMD3<Float>(0, pelvisY, 0)) * Math3D.rotationX(pose.torsoPitch)
        let torsoMatrix = torsoPivot * Math3D.translation(SIMD3<Float>(0, 0.32, 0))

        let headMatrix = torsoPivot * Math3D.translation(SIMD3<Float>(0, 0.84, 0)) * Math3D.rotationX(pose.headPitch)
        let hairMatrix = headMatrix * Math3D.translation(SIMD3<Float>(0, 0.15, -0.02))

        // Left Arm + Hand
        let leftShoulder = torsoPivot
            * Math3D.translation(SIMD3<Float>(-0.34, 0.58, 0))
            * Math3D.rotationX(pose.leftArmSwingX)
            * Math3D.rotationZ(pose.leftArmOutZ)
        let leftArmMatrix = leftShoulder * Math3D.translation(SIMD3<Float>(0, -0.24, 0))
        let leftHandMatrix = leftShoulder * Math3D.translation(SIMD3<Float>(0, -0.53, 0))

        // Right Arm + Hand
        let rightShoulder = torsoPivot
            * Math3D.translation(SIMD3<Float>(0.34, 0.58, 0))
            * Math3D.rotationX(pose.rightArmSwingX)
            * Math3D.rotationZ(pose.rightArmOutZ)
        let rightArmMatrix = rightShoulder * Math3D.translation(SIMD3<Float>(0, -0.24, 0))
        let rightHandMatrix = rightShoulder * Math3D.translation(SIMD3<Float>(0, -0.53, 0))

        // Left Leg + Foot
        let leftHip = root * Math3D.translation(SIMD3<Float>(-0.14, pelvisY, 0)) * Math3D.rotationX(pose.leftLegSwingX)
        let leftLegMatrix = leftHip * Math3D.translation(SIMD3<Float>(0, -0.32, 0))
        let leftFootMatrix = leftHip * Math3D.translation(SIMD3<Float>(0, -0.68, 0.05))

        // Right Leg + Foot
        let rightHip = root * Math3D.translation(SIMD3<Float>(0.14, pelvisY, 0)) * Math3D.rotationX(pose.rightLegSwingX)
        let rightLegMatrix = rightHip * Math3D.translation(SIMD3<Float>(0, -0.32, 0))
        let rightFootMatrix = rightHip * Math3D.translation(SIMD3<Float>(0, -0.68, 0.05))

        return [
            CharacterPartRenderItem(mesh: torsoMesh, modelUniforms: ModelUniforms(modelMatrix: torsoMatrix, tintColor: shirtColor, materialParams: fabricParams)),
            CharacterPartRenderItem(mesh: headMesh, modelUniforms: ModelUniforms(modelMatrix: headMatrix, tintColor: skinColor, materialParams: skinParams)),
            CharacterPartRenderItem(mesh: hairMesh, modelUniforms: ModelUniforms(modelMatrix: hairMatrix, tintColor: hairColor, materialParams: fabricParams)),
            CharacterPartRenderItem(mesh: armMesh, modelUniforms: ModelUniforms(modelMatrix: leftArmMatrix, tintColor: shirtColor, materialParams: fabricParams)),
            CharacterPartRenderItem(mesh: handMesh, modelUniforms: ModelUniforms(modelMatrix: leftHandMatrix, tintColor: skinColor, materialParams: skinParams)),
            CharacterPartRenderItem(mesh: armMesh, modelUniforms: ModelUniforms(modelMatrix: rightArmMatrix, tintColor: shirtColor, materialParams: fabricParams)),
            CharacterPartRenderItem(mesh: handMesh, modelUniforms: ModelUniforms(modelMatrix: rightHandMatrix, tintColor: skinColor, materialParams: skinParams)),
            CharacterPartRenderItem(mesh: legMesh, modelUniforms: ModelUniforms(modelMatrix: leftLegMatrix, tintColor: pantsColor, materialParams: fabricParams)),
            CharacterPartRenderItem(mesh: footMesh, modelUniforms: ModelUniforms(modelMatrix: leftFootMatrix, tintColor: shoeColor, materialParams: shoeParams)),
            CharacterPartRenderItem(mesh: legMesh, modelUniforms: ModelUniforms(modelMatrix: rightLegMatrix, tintColor: pantsColor, materialParams: fabricParams)),
            CharacterPartRenderItem(mesh: footMesh, modelUniforms: ModelUniforms(modelMatrix: rightFootMatrix, tintColor: shoeColor, materialParams: shoeParams))
        ]
    }
}
