import SwiftUI

struct RootView: View {
    @Environment(AppController.self) private var controller
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            header
            statusArea
            Divider().overlay(LiTheme.cardBorder)
            content
        }
        .frame(minWidth: 380, minHeight: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiTheme.background)
        .preferredColorScheme(.dark)
        .tint(LiTheme.accent)
        .background(MainWindowAccessor())
    }

    private var header: some View {
        HStack(spacing: 12) {
            PowerButton(isOn: state.powerOn) {
                controller.togglePower()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    LiSoundLogo()
                        .frame(width: 20, height: 18)
                    Text("LiSound")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(LiTheme.textPrimary)
                }
                Text(state.powerOn ? "Processing system audio" : "Power is off")
                    .font(.caption)
                    .foregroundStyle(state.powerOn ? LiTheme.accent : LiTheme.textSecondary)
            }

            Spacer(minLength: 8)

            Picker("View", selection: Binding(
                get: { state.viewIsPro },
                set: { controller.setViewIsPro($0) })) {
                Text("Lite").tag(false)
                Text("Pro").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .focusable(false)
            .frame(width: 128)
        }
        .padding()
    }

    @ViewBuilder
    private var statusArea: some View {
        VStack(spacing: 8) {
            if let error = state.engineError {
                StatusCard(icon: "exclamationmark.triangle", tint: .orange,
                           title: "Audio engine error", message: error) {
                    Button("Retry") { controller.powerOn() }
                        .buttonStyle(.borderedProminent)
                }
            }
            if state.showPermissionHelp || state.permissionState == .silentFailure {
                StatusCard(icon: "hand.raised", tint: .yellow,
                           title: "Audio recording permission needed",
                           message: "Allow microphone/audio access for LiSound in System Settings → Privacy & Security → Audio Recording, then retry.") {
                    Button("Open System Settings") {
                        if let url = URL(string: Permissions.settingsDeepLink) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Retry") {
                        state.showPermissionHelp = false
                        controller.powerOff()
                        controller.powerOn()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if state.viewIsPro {
            ProView()
        } else {
            LiteView()
        }
    }
}

struct StatusCard<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(LiTheme.textPrimary)
                Text(message).font(.callout).foregroundStyle(LiTheme.textSecondary)
                HStack { actions }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.3)))
    }
}

struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let appDelegate = NSApp.delegate as? AppDelegate, let window = view.window else { return }
            appDelegate.registerMainWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
