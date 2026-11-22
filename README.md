# DORATUM WORLD

A native 3D Open World Sandbox game for **iPhone and iPad** built from scratch with **Swift**, **SwiftUI**, **Apple Metal**, and **MetalKit** (zero external dependencies).

## World: Doratum Bay
- **Downtown**: High-rise towers, office buildings, multi-lane avenues, sidewalks, crosswalks, and the Central Doratum Spire plaza.
- **Residential District**: Pitched-roof homes, neighborhood streets, and garden trees.
- **Coastal Area**: Sandy shoreline, seaside boardwalk, palm trees, rocks, and an animated 3D ocean water shader.
- **Park Area**: Rolling green hills, walking trails, broadleaf/pine forests, and boulders.

## Architecture
- `Sources/App/`: Entry point (`DoratumWorldApp.swift`) and root SwiftUI container (`ContentView.swift`).
- `Sources/Game/`: `GameEngine`, `GameCoordinator`, `GameRenderer` (Metal), `WorldScene`, `WorldGenerator`, `ChunkManager`, and `FPSMonitor`.
- `Sources/Player/`: `PlayerController`, `CharacterModel` (multi-part 3D human), and `CharacterAnimation` (procedural walk/run/sprint/jump/fall/landing).
- `Sources/Camera/`: `CameraController` (third-person follow, smooth orbit, pinch zoom, raycast building collision avoidance).
- `Sources/Physics/`: `PhysicsWorld` (fixed timestep, gravity, friction, jumping) and `CollisionWorld` (chunk-indexed AABB solver & raycast).
- `Sources/Graphics/`: `ShaderTypes`, `MeshFactory`, `MaterialSystem`, and `LightingSystem`.
- `Sources/Shaders/`: `WorldShaders.metal` (opaque, instanced vegetation, and animated water shaders with directional/ambient/specular lighting and distance fog).
- `Sources/Input/`: `InputController` (multi-touch safe state).
- `Sources/UI/`: `MainMenuView`, `GameHUD`, `VirtualJoystick`, `CameraTouchPad`, `ActionButton`, `PauseMenu`, `SettingsView`, and `MetalGameView`.
- `Sources/Data/`: `GameSettings` (`UserDefaults`) and `SaveManager` (JSON save/load with corruption fallback).

## Building Unsigned IPA on GitHub Actions (No Mac Required)
1. Push this repository to GitHub (`main` branch).
2. GitHub Actions (`macos-latest`) automatically installs XcodeGen, runs `xcodegen generate`, builds the iOS app with `CODE_SIGNING_ALLOWED=NO`, packages `Payload/DORATUM WORLD.app` into `DORATUM-WORLD-unsigned.ipa`, validates integrity, and uploads the artifact named `DORATUM-WORLD-Unsigned-IPA`.
3. Download the artifact in Termux with `gh run download -n DORATUM-WORLD-Unsigned-IPA` and sign/sideload with your preferred iOS signing tool.
