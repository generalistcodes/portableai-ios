import SwiftUI

/// Visual tokens aligned with the web UI dark theme
/// (`ui/static/style.css` `:root[data-theme="dark"]`, last read 2026-09-12).
enum Brand {
    /// Sidebar / chrome — web `--bg-sidebar`
    static let sidebar = Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
    /// Main chat surface — web `--bg-main`
    static let main = Color(red: 20 / 255, green: 18 / 255, blue: 24 / 255)
    /// Interactive accent — web `--accent` (#10a37f)
    static let accent = Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255)
    /// Assistant bubble — web `--bg-assistant-bubble`
    static let assistantBubble = Color(red: 47 / 255, green: 47 / 255, blue: 47 / 255)
    /// User bubble — web `--bg-user-bubble`
    static let userBubble = Color(red: 48 / 255, green: 48 / 255, blue: 48 / 255)
    /// Primary text on dark surfaces — web `--text-primary`
    static let textPrimary = Color(red: 236 / 255, green: 236 / 255, blue: 236 / 255)
    /// Muted text — web `--text-muted`
    static let textMuted = Color(red: 155 / 255, green: 155 / 255, blue: 155 / 255)
    /// Selected / active row — web `--bg-active`
    static let active = Color(red: 52 / 255, green: 53 / 255, blue: 65 / 255)
}
