import SwiftUI

struct MenuBarContentView: View {
    let controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            controller.togglePower()
        } label: {
            HStack {
                Image(systemName: controller.state.powerOn ? "stop.circle" : "play.circle")
                Text(controller.state.powerOn ? "Sovate: On" : "Sovate: Off")
            }
        }
        Divider()

        Section("Presets") {
            ForEach(controller.state.presets) { preset in
                Button {
                    controller.selectPreset(id: preset.id)
                } label: {
                    menuItemLabel(title: preset.name, isChecked: preset.id == controller.state.selectedPresetID)
                }
                .disabled(!controller.state.powerOn)
            }
        }

        Section("Output") {
            Button {
                controller.setFollowSystemDefault(true)
            } label: {
                menuItemLabel(title: "Follow System Default",
                              isChecked: controller.state.followSystemDefault)
            }
            ForEach(controller.state.sortedOutputs) { device in
                Button {
                    controller.selectOutput(uid: device.uid)
                } label: {
                    menuItemLabel(title: device.name,
                                  isChecked: !controller.state.followSystemDefault
                                      && device.uid == controller.state.selectedOutputUID)
                }
            }
        }

        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
        }
        .keyboardShortcut(",")
        Button("Open Sovate") {
            controller.toggleMainWindow?()
        }
        Button("Quit Sovate") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// macOS 26 strips SF Symbol images from menu item labels — a text tick is the
    /// only rendering that reliably marks the active config.
    private func menuItemLabel(title: String, isChecked: Bool) -> some View {
        Text(isChecked ? "✓ \(title)" : title)
    }
}
