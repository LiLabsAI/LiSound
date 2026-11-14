//
//  LiSoundApp.swift
//  LiSound
//

import SwiftUI

@main
struct LiSoundApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = AppController.shared


    var body: some Scene {
        WindowGroup("LiSound", id: "main") {
            RootView()
                .environment(controller)
                .environment(controller.state)
                .onAppear {
                    appDelegate.attach(controller: controller)
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 520)

        MenuBarExtra {
            MenuBarContentView(controller: controller)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.menu)

        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .environment(controller)
                .environment(controller.state)
                .tint(LiTheme.accent)
                .preferredColorScheme(.dark)
                .frame(minWidth: 470, idealWidth: 640, minHeight: 400)
        }
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) weak var controller: AppController?
    private weak var mainWindow: NSWindow?
    private var sigtermSource: DispatchSourceSignal?

    func attach(controller: AppController) {
        guard self.controller == nil else { return }
        self.controller = controller
        controller.toggleMainWindow = { [weak self] in
            self?.toggleMainWindow()
        }
        installSIGTERMHandler()
    }

    /// `kill` sends SIGTERM, which by itself does not run AppKit's graceful
    /// termination (skipping preset autosave and engine teardown) — route it
    /// through `terminate:` so the normal quit path handles everything.
    private func installSIGTERMHandler() {
        guard sigtermSource == nil else { return }
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            NSApp.terminate(nil)
        }
        source.resume()
        sigtermSource = source
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.prepareForTermination()
        return .terminateNow
    }

    private func toggleMainWindow() {
        // Only real app windows qualify — exclude the Settings scene's window so the
        // fallback can't raise it instead of the main window.
        let candidates = NSApp.windows.filter { $0.canBecomeMain && $0.title != "Settings" }
        if let window = mainWindow, window.isVisible {
            window.orderOut(nil)
        } else if let window = mainWindow ?? candidates.first {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
