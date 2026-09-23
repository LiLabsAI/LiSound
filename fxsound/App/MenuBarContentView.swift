import SwiftUI

struct MenuBarContentView: View {
    let controller: AppController

    var body: some View {
        Button {
            controller.togglePower()
        } label: {
            HStack {
                Image(systemName: controller.state.powerOn ? "stop.circle" : "play.circle")
                Text(controller.state.powerOn ? "FxSound: On" : "FxSound: Off")
            }
        }
        Divider()

        Section("Presets") {
            ForEach(controller.state.presets.prefix(8)) { preset in
                Button {
                    controller.selectPreset(id: preset.id)
                } label: {
                    HStack {
                        Text(preset.name)
                        if preset.id == controller.state.selectedPresetID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(!controller.state.powerOn)
            }
        }

        Section("Output") {
            Button {
                controller.setFollowSystemDefault(true)
            } label: {
                HStack {
                    Text("Follow System Default")
                    if controller.state.followSystemDefault {
                        Image(systemName: "checkmark")
                    }
                }
            }
            ForEach(controller.state.sortedOutputs) { device in
                Button {
                    controller.selectOutput(uid: device.uid)
                } label: {
                    HStack {
                        Image(systemName: device.transportSymbol)
                        Text(device.name)
                        if !controller.state.followSystemDefault,
                           device.uid == controller.state.selectedOutputUID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()
        Button("Open FxSound") {
            controller.toggleMainWindow?()
        }
        Button("Quit FxSound") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
