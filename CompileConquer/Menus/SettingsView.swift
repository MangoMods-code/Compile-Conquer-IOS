import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var versionTaps = 0
    @State private var askOwnerCode = false
    @State private var codeEntry = ""
    @State private var wrongCode = false
    @State private var changingCode = false
    @State private var newCode = ""
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Sound") {
                        VStack(alignment: .leading, spacing: 10) {
                            toggle("Sound effects", $settings.soundOn)
                            if settings.soundOn {
                                volume("Effects volume", $settings.soundVolume) { SoundFX.shared.play(.harvest) }
                            }
                            toggle("Music", $settings.musicOn)
                            if settings.musicOn {
                                volume("Music volume", $settings.musicVolume) {}
                            }
                        }
                    }

                    section("Editor") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Code text size").font(Theme.mono(13)).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(Int(settings.codeFontSize)) pt").font(Theme.mono(12, .bold)).foregroundStyle(Theme.accent)
                            }
                            Slider(value: $settings.codeFontSize, in: 10...20, step: 1)
                            Text("move(North)  # preview")
                                .font(.system(size: settings.codeFontSize, design: .monospaced))
                                .foregroundStyle(Theme.blue)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                        }
                    }

                    section("Playback") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Starting speed when you open a level").font(Theme.mono(13)).foregroundStyle(Theme.text)
                            Picker("Speed", selection: $settings.defaultSpeed) {
                                ForEach(0..<GameSession.speeds.count, id: \.self) { i in
                                    Text("\(Int(GameSession.speeds[i]))x").tag(i)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    section("Map & feel") {
                        VStack(spacing: 10) {
                            toggle("Show x and y numbers around the map", $settings.showCoords)
                            toggle("Show crop age tags on the Farm", $settings.showCropAges)
                            toggle("Haptics", $settings.haptics)
                        }
                    }

                    section("Progress") {
                        Button(role: .destructive) { confirmReset = true } label: {
                            Label("Reset all stars and saved code", systemImage: "trash")
                                .font(Theme.mono(13, .bold))
                                .foregroundStyle(Theme.danger)
                        }
                    }

                    if settings.ownerUnlocked {
                        section("Owner") {
                            VStack(alignment: .leading, spacing: 10) {
                                toggle("Play any campaign", $settings.playAnyCampaign)
                                Text("Opens every built campaign and world without finishing the one before. Levels inside a world still unlock in order.")
                                    .font(Theme.mono(10)).foregroundStyle(Theme.dim)
                                HStack {
                                    Button("Change owner code") { newCode = ""; changingCode = true }
                                        .font(Theme.mono(12, .bold)).foregroundStyle(Theme.accent)
                                    Spacer()
                                    Button("Lock owner tools") { settings.lockOwnerTools() }
                                        .font(Theme.mono(12, .bold)).foregroundStyle(Theme.danger)
                                }
                            }
                        }
                    }

                    // Tapping the version 7 times asks for the owner code.
                    Text(AppInfo.versionLabel)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !settings.ownerUnlocked else { return }
                            versionTaps += 1
                            if versionTaps >= 7 { versionTaps = 0; codeEntry = ""; askOwnerCode = true }
                        }
                }
                .padding(20)
            }
            .background(GridBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(Theme.mono(14, .bold))
                }
            }
            .alert("Owner code", isPresented: $askOwnerCode) {
                SecureField("Code", text: $codeEntry)
                Button("Unlock") {
                    if settings.checkOwnerCode(codeEntry) { settings.ownerUnlocked = true } else { wrongCode = true }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("That code isn't right.", isPresented: $wrongCode) { Button("OK", role: .cancel) {} }
            .alert("New owner code", isPresented: $changingCode) {
                SecureField("New code", text: $newCode)
                Button("Save") { if !newCode.trimmingCharacters(in: .whitespaces).isEmpty { settings.setOwnerCode(newCode) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) { GameProgress.shared.resetAll() }
            } message: {
                Text("Every star and every bit of saved code will be deleted.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(Theme.mono(11, .bold)).foregroundStyle(Theme.accent)
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 14)
        }
    }

    private func toggle(_ title: String, _ value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            Text(title).font(Theme.mono(13)).foregroundStyle(Theme.text)
        }
        .tint(Theme.accent)
    }

    private func volume(_ title: String, _ value: Binding<Double>, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(Theme.dim)
            Slider(value: value, in: 0...1, onEditingChanged: { editing in if !editing { onChange() } })
                .tint(Theme.accent)
                .accessibilityLabel(title)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(Theme.dim)
        }
    }
}
