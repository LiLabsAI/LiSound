import Foundation

enum PermissionState: Equatable {
    case unknown
    case granted
    case denied
    case silentFailure
    case failed(String)

    var isUsable: Bool { self == .granted }
}

/// macOS has no public API to query the audio-capture consent state, and a missing or
/// denied grant can show up as taps that succeed but deliver all-zero audio. The state
/// here is therefore derived from runtime evidence, not a TCC query.
enum Permissions {
    static var settingsDeepLink: String {
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioRecording"
    }
}
