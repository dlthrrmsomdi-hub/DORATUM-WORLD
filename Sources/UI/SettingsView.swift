import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var settings: GameSettings
    @Environment(\.dismiss) private var dismiss

    public init(settings: GameSettings) {
        self.settings = settings
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Graphics & Performance") {
                    Picker("Graphics Quality", selection: $settings.graphicsQuality) {
                        ForEach(GraphicsQuality.allCases) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Render Distance")
                            Spacer()
                            Text("\(Int(settings.renderDistance)) m")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.renderDistance, in: 80...settings.graphicsQuality.maxRenderDistance, step: 10)
                    }

                    Picker("FPS Limit", selection: $settings.fpsLimit) {
                        Text("30 FPS (Battery)").tag(30)
                        Text("60 FPS (Smooth)").tag(60)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Controls & Camera") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Camera Sensitivity")
                            Spacer()
                            Text(String(format: "%.2fx", settings.cameraSensitivity))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.cameraSensitivity, in: 0.25...2.25, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Control Sensitivity")
                            Spacer()
                            Text(String(format: "%.2fx", settings.controlSensitivity))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.controlSensitivity, in: 0.5...1.8, step: 0.05)
                    }
                }

                Section("Character Style") {
                    Picker("Outfit Colors", selection: $settings.outfitPreset) {
                        ForEach(OutfitColorPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                }

                Section("Audio") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Music Volume")
                            Spacer()
                            Text("\(Int(settings.musicVolume * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.musicVolume, in: 0...1, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Sound Volume")
                            Spacer()
                            Text("\(Int(settings.soundVolume * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.soundVolume, in: 0...1, step: 0.05)
                    }
                }

                Section {
                    Button("Reset All Settings to Defaults", role: .destructive) {
                        settings.resetToDefaults()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
