import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    var openMainWindow: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
                Text("MacSlap")
                    .font(.headline)
                Spacer()
                Text("\(appState.slapCount) slaps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Status indicators
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(appState.slapEnabled ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text("Slap Detection")
                    Spacer()
                    Toggle("", isOn: $appState.slapEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }

                HStack {
                    Circle()
                        .fill(appState.lidEnabled ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text("Lid Angle")
                    Spacer()
                    Toggle("", isOn: $appState.lidEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }

                if appState.lastSlapMagnitude > 0 {
                    HStack {
                        Text("Last slap:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(appState.lastSlapMagnitude, specifier: "%.1f")g")
                            .font(.caption.monospacedDigit())
                    }
                }

                if appState.lidEnabled && appState.currentLidAngle > 0 {
                    HStack {
                        Text("Lid angle:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(appState.currentLidAngle, specifier: "%.0f") deg")
                            .font(.caption.monospacedDigit())
                    }
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Reset Counter") {
                    appState.resetCount()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Settings...") {
                    openMainWindow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button("Quit MacSlap") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 280)
    }
}
