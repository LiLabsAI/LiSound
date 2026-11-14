import SwiftUI

extension Color {
    /// Brand gold — rich golden yellow that reads clearly on pure black.
    static let gold = Color(red: 1.0, green: 0.76, blue: 0.08)
    static let deepGold = Color(red: 0.55, green: 0.36, blue: 0.02)
    static let lightGold = Color(red: 1.0, green: 0.88, blue: 0.45)
}

/// App-wide color system: pure black surfaces with a golden accent.
enum LiTheme {
    static let background = Color.black
    static let card = Color(red: 0.06, green: 0.06, blue: 0.06)
    static let cardBorder = Color.gold.opacity(0.22)
    static let accent = Color.gold
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.32)

    static let barGradient = Gradient(colors: [
        Color.lightGold,
        Color.gold,
        Color.deepGold,
    ])

    static let peakColor = Color(red: 1.0, green: 0.93, blue: 0.6)
}
