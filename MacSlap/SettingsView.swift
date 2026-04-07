import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            SlapSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Slap", systemImage: "hand.raised.fill")
                }

            LidSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Lid Angle", systemImage: "laptopcomputer")
                }

            ScreenWakeSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Screen", systemImage: "lock.open.fill")
                }

            ChargerSettingsTab()
                .environmentObject(appState)
                .tabItem {
                    Label("Charger", systemImage: "bolt.fill")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding(20)
    }
}

// MARK: - Detection Indicator

struct DetectionIndicator: View {
    let label: String
    let icon: String
    let lastTriggered: Date
    let detail: String

    @State private var flash = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(flash ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .animation(.easeOut(duration: 0.6), value: flash)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(flash ? .white : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(flash ? .primary : .secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if flash {
                Text("TRIGGERED")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else {
                Text("Waiting...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(flash ? Color.green.opacity(0.1) : Color.clear)
                .animation(.easeOut(duration: 0.6), value: flash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(flash ? Color.green.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
                .animation(.easeOut(duration: 0.6), value: flash)
        )
        .onChange(of: lastTriggered) { _, _ in
            withAnimation {
                flash = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation {
                    flash = false
                }
            }
        }
    }
}

// MARK: - Hardware Error Banner

struct HardwareErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hardware Not Available")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.85))
        )
    }
}

// MARK: - Slap Settings

struct SlapSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            if appState.slapEnabled && !appState.slapSensorAvailable {
                Section {
                    HardwareErrorBanner(
                        message: "Accelerometer not found. Requires Apple Silicon M1 Pro or later. Standard M1 and Intel Macs are not supported."
                    )
                }
            }

            Section {
                Toggle("Enable Slap Detection", isOn: $appState.slapEnabled)
                    .toggleStyle(.switch)
            }

            if appState.slapEnabled {
                Section("Live Test") {
                    DetectionIndicator(
                        label: "Slap Detection",
                        icon: "hand.raised.fill",
                        lastTriggered: appState.lastSlapTime,
                        detail: appState.lastSlapMagnitude > 0
                            ? String(format: "Last: %.1fg force — %d slaps total", appState.lastSlapMagnitude, appState.slapCount)
                            : "Slap your MacBook to test!"
                    )
                }
            }

            Section("Sensitivity") {
                HStack {
                    Text("Light tap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $appState.slapSensitivity, in: 0.5...8.0, step: 0.1)
                    Text("Hard slap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Current: \(appState.slapSensitivity, specifier: "%.1f") g-force threshold")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Cooldown") {
                HStack {
                    Text("Rapid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $appState.slapCooldown, in: 0.1...3.0, step: 0.1)
                    Text("Slow")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Wait \(appState.slapCooldown, specifier: "%.1f")s between triggers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound") {
                SoundPicker(
                    selectedURL: $appState.slapSoundURL,
                    defaultLabel: "Slap (Default)",
                    soundManager: appState.soundManager
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Lid Settings

struct LidSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            if appState.lidEnabled && !appState.lidSensorAvailable {
                Section {
                    HardwareErrorBanner(
                        message: "Lid angle sensor not found. Requires Apple Silicon M1 Pro or later with SPU hinge sensor."
                    )
                }
            }

            Section {
                Toggle("Enable Lid Angle Detection", isOn: $appState.lidEnabled)
                    .toggleStyle(.switch)

                Text("Plays a sound when you move the lid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.lidEnabled {
                Section("Live Test") {
                    DetectionIndicator(
                        label: "Lid Movement",
                        icon: "laptopcomputer",
                        lastTriggered: appState.lastLidTriggerTime,
                        detail: appState.currentLidAngle > 0
                            ? String(format: "Angle: %.0f° — speed: %.0f°/s", appState.currentLidAngle, appState.lidMovementSpeed)
                            : "Move the lid to test!"
                    )
                }
            }

            Section("Sensitivity") {
                HStack {
                    Text("Sensitive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $appState.lidAngleThreshold, in: 1.0...30.0, step: 1.0)
                    Text("Relaxed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Trigger when angle changes by \(Int(appState.lidAngleThreshold)) degrees")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sound") {
                SoundPicker(
                    selectedURL: $appState.lidSoundURL,
                    defaultLabel: "Fart (Default)",
                    soundManager: appState.soundManager
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Screen Wake Settings

struct ScreenWakeSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Enable Screen Wake/Sleep Sounds", isOn: $appState.screenWakeEnabled)
                    .toggleStyle(.switch)

                Text("Plays a sound when you open the lid, unlock, or lock your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.screenWakeEnabled {
                Section("Live Test") {
                    DetectionIndicator(
                        label: "Screen",
                        icon: "lock.open.fill",
                        lastTriggered: appState.lastScreenEventTime,
                        detail: !appState.lastScreenEvent.isEmpty
                            ? "Last: \(appState.lastScreenEvent)"
                            : "Lock or unlock your Mac to test!"
                    )
                }
            }

            Section("Wake / Unlock Sound") {
                SoundPicker(
                    selectedURL: $appState.screenWakeSoundURL,
                    defaultLabel: "Blow (Default)",
                    soundManager: appState.soundManager
                )
            }

            Section("Sleep / Lock Sound") {
                SoundPicker(
                    selectedURL: $appState.screenSleepSoundURL,
                    defaultLabel: "Purr (Default)",
                    soundManager: appState.soundManager
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Charger Settings

struct ChargerSettingsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Enable Charger Detection", isOn: $appState.chargerEnabled)
                    .toggleStyle(.switch)

                Text("Plays a sound when you plug in or unplug the charger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.chargerEnabled {
                Section("Live Test") {
                    DetectionIndicator(
                        label: "Charger",
                        icon: "bolt.fill",
                        lastTriggered: appState.lastChargerTime,
                        detail: !appState.lastChargerEvent.isEmpty
                            ? "Last event: \(appState.lastChargerEvent)"
                            : "Plug or unplug charger to test!"
                    )
                }
            }

            Section("Plug-in Sound") {
                SoundPicker(
                    selectedURL: $appState.chargerPlugSoundURL,
                    defaultLabel: "Plug (Default)",
                    soundManager: appState.soundManager
                )
            }

            Section("Unplug Sound") {
                SoundPicker(
                    selectedURL: $appState.chargerUnplugSoundURL,
                    defaultLabel: "Unplug (Default)",
                    soundManager: appState.soundManager
                )
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sound Picker

struct SoundPicker: View {
    @Binding var selectedURL: URL?
    let defaultLabel: String
    let soundManager: SoundManager

    @State private var systemSounds: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Current: \(selectedURL?.lastPathComponent ?? defaultLabel)")
                        .font(.body)
                    if let url = selectedURL {
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Button("Preview") {
                    if let url = selectedURL {
                        soundManager.preview(url: url)
                    } else if defaultLabel.contains("Slap") {
                        if let url = soundManager.defaultSlapSound() { soundManager.preview(url: url) }
                    } else if defaultLabel.contains("Fart") {
                        if let url = soundManager.defaultLidSound() { soundManager.preview(url: url) }
                    } else if defaultLabel.contains("Plug") {
                        if let url = soundManager.defaultChargerPlugSound() { soundManager.preview(url: url) }
                    } else if defaultLabel.contains("Unplug") {
                        if let url = soundManager.defaultChargerUnplugSound() { soundManager.preview(url: url) }
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Button("Choose File...") {
                    chooseCustomSound()
                }
                .buttonStyle(.borderedProminent)

                Button("Use Default") {
                    selectedURL = nil
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Text("System Sounds")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(systemSounds, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            selectedURL = url
                            soundManager.preview(url: url)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedURL == url ? .accentColor : nil)
                    }
                }
            }
            .onAppear {
                systemSounds = SoundManager.systemSounds()
            }
        }
    }

    private func chooseCustomSound() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Sound File"
        panel.allowedContentTypes = [
            .audio, .aiff, .wav, .mp3,
            .init(filenameExtension: "m4a")!,
            .init(filenameExtension: "caf")!,
            .init(filenameExtension: "ogg")!,
        ].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedURL = url
            soundManager.preview(url: url)
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("MacSlap")
                .font(.largeTitle.bold())

            Text("Version 1.0")
                .foregroundStyle(.secondary)

            Text("Slap your MacBook. It reacts.")
                .font(.title3)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Detects physical slaps via microphone", systemImage: "hand.raised")
                Label("Monitors lid angle changes", systemImage: "laptopcomputer")
                Label("Sounds on screen wake/sleep", systemImage: "lock.open.fill")
                Label("Detects charger plug/unplug", systemImage: "bolt.fill")
                Label("Choose your own sounds", systemImage: "speaker.wave.3")
                Label("Volume scales with impact force", systemImage: "dial.medium")
            }
            .font(.body)

            Spacer()
        }
        .padding()
    }
}
