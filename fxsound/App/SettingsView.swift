import SwiftUI
import Carbon.HIToolbox

private let carbonControlKey = UInt32(controlKey)
private let carbonOptionKey = UInt32(optionKey)
private let carbonShiftKey = UInt32(shiftKey)
private let carbonCmdKey = UInt32(cmdKey)

struct SettingsView: View {
    @Environment(AppController.self) private var controller
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            AudioSettingsTab()
                .tabItem { Label("Audio", systemImage: "hifispeaker") }
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeysSettingsTab()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding()
    }
}

private struct AudioSettingsTab: View {
    @Environment(AppController.self) private var controller
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section("Output device") {
                Toggle("Follow the system default output", isOn: Binding(
                    get: { state.followSystemDefault },
                    set: { controller.setFollowSystemDefault($0) }))
                Toggle("Prioritize newly connected devices", isOn: Binding(
                    get: { controller.prioritizeNewDevices },
                    set: { controller.setPrioritizeNewDevices($0) }))
            }
            Section("Connected devices") {
                ForEach(state.sortedOutputs) { device in
                    HStack {
                        Image(systemName: device.transportSymbol)
                            .frame(width: 20)
                        Text(device.name)
                        Spacer()
                        if device.isDefault {
                            Text("Default").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppController.self) private var controller
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch FxSound at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        if let error = controller.setLaunchAtLogin(newValue) {
                            loginError = error.localizedDescription
                            launchAtLogin = LoginItem.isEnabled
                        } else {
                            loginError = nil
                        }
                    }
                Toggle("Start with power on", isOn: Binding(
                    get: { controller.powerOnAtLaunch },
                    set: { controller.setPowerOnAtLaunch($0) }))
            }
            if let loginError {
                Text(loginError).foregroundStyle(.red).font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HotkeysSettingsTab: View {
    @Environment(AppController.self) private var controller
    @State private var recording: HotkeyCommand?

    var body: some View {
        Form {
            Toggle("Enable global hotkeys", isOn: Binding(
                get: { controller.hotkeysEnabled },
                set: { controller.setHotkeysEnabled($0) }))
            ForEach(HotkeyCommand.allCases) { command in
                HStack {
                    Text(command.title)
                    Spacer()
                    Button {
                        recording = command
                    } label: {
                        Text(currentComboLabel(command))
                            .frame(minWidth: 90)
                    }
                    .disabled(!controller.hotkeysEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $recording) { command in
            HotkeyRecorderSheet(command: command) { combo in
                controller.setHotkeyCombo(combo, for: command)
                recording = nil
            }
        }
    }

    private func currentComboLabel(_ command: HotkeyCommand) -> String {
        if let combo = controller.currentCombo(for: command) {
            return combo.displayString
        }
        return "Not set"
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FxSound for Mac").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Divider()
            Text("A system-wide equalizer and volume booster inspired by the open-source FxSound project for Windows. Preset data ported from FxSound (AGPL v3).")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HotkeyRecorderSheet: View {
    let command: HotkeyCommand
    let onCapture: (HotkeyCombo) -> Void

    @State private var monitor: Any?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text(command.title).font(.headline)
            Text("Press a key combination (⌃ or ⌥ plus a key)…")
                .foregroundStyle(.secondary)
            Button("Cancel") { dismiss() }
        }
        .padding(24)
        .onAppear(perform: installMonitor)
        .onDisappear(perform: removeMonitor)
    }

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags
            let control = flags.contains(.control)
            let option = flags.contains(.option)
            guard control || option else { return event }
            var carbon: UInt32 = 0
            if control { carbon |= carbonControlKey }
            if option { carbon |= carbonOptionKey }
            if flags.contains(.shift) { carbon |= carbonShiftKey }
            if flags.contains(.command) { carbon |= carbonCmdKey }
            removeMonitor()
            onCapture(HotkeyCombo(carbonModifiers: carbon, keyCode: UInt32(event.keyCode)))
            return nil
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
