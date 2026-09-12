import SwiftUI

/// Server theme id from `GET/POST /api/theme` (`dark` | `light` | `ube`).
enum AppTheme: String, CaseIterable, Identifiable {
    case dark
    case light
    case ube

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .ube: return "Ube"
        }
    }

    /// Match system chrome (nav bar / `.secondary`) to custom surfaces.
    var preferredColorScheme: ColorScheme {
        self == .light ? .light : .dark
    }

    /// Tokens from `ui/static/style.css` (read 2026-09-12 from portableai main).
    var colors: ThemeColors {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .ube: return .ube
        }
    }

    static func parse(_ raw: String?) -> AppTheme {
        AppTheme(rawValue: raw ?? "") ?? .dark
    }
}

/// Explicit hex colors — never use system `.secondary` / `.primary` on these surfaces.
struct ThemeColors {
    let main: Color
    let sidebar: Color
    let assistantBubble: Color
    let userBubble: Color
    let input: Color
    let accent: Color
    let textPrimary: Color
    let textMuted: Color
    let textBrand: Color
    let active: Color
    let bubbleBorder: Color
    let danger: Color

    /// `:root[data-theme="dark"]`
    static let dark = ThemeColors(
        main: Color(hex: 0x141218),
        sidebar: Color(hex: 0x171717),
        assistantBubble: Color(hex: 0x2F2F2F),
        userBubble: Color(hex: 0x303030),
        input: Color(hex: 0x2F2F2F),
        accent: Color(hex: 0x10A37F),
        textPrimary: Color(hex: 0xECECEC),
        textMuted: Color(hex: 0xB8B8B8), // web `--text-tagline` — clearer than `--text-muted` #9b9b9b on chat chrome
        textBrand: Color(hex: 0xFFFFFF),
        active: Color(hex: 0x343541),
        bubbleBorder: .clear,
        danger: Color(hex: 0xE05252)
    )

    /// `:root[data-theme="light"]`
    static let light = ThemeColors(
        main: Color(hex: 0xF3EEF6),
        sidebar: Color(hex: 0xE8E0EF),
        assistantBubble: Color(hex: 0xFFFFFF),
        userBubble: Color(hex: 0xE4D4F0),
        input: Color(hex: 0xFFFFFF),
        accent: Color(hex: 0x9B2A94),
        textPrimary: Color(hex: 0x1F1728),
        textMuted: Color(hex: 0x6A6078),
        textBrand: Color(hex: 0x1F1728),
        active: Color(hex: 0xD4C4E6),
        bubbleBorder: Color(hex: 0x46285A, opacity: 0.12),
        danger: Color(hex: 0xC0392B)
    )

    /// `:root[data-theme="ube"]`
    static let ube = ThemeColors(
        main: Color(hex: 0x1C1424),
        sidebar: Color(hex: 0x24182E),
        assistantBubble: Color(hex: 0x3A2748),
        userBubble: Color(hex: 0x4A2F5C),
        input: Color(hex: 0x322040),
        accent: Color(hex: 0xC47BB2),
        textPrimary: Color(hex: 0xF6EAF8),
        textMuted: Color(hex: 0xC4A8CC),
        textBrand: Color(hex: 0xFFFFFF),
        active: Color(hex: 0x4E3362),
        bubbleBorder: Color(hex: 0xE8C8F0, opacity: 0.10),
        danger: Color(hex: 0xE07080)
    )
}

/// Backward-compatible name used across views — always the *current* theme
/// via `ThemeColorsKey` / `appState.colors`. Prefer `@Environment(\.themeColors)`.
typealias Brand = ThemeColors

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue = ThemeColors.dark
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
