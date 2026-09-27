import Foundation
import SwiftUI

/// Renders the markdown subset model replies typically use (bold, lists,
/// paragraphs) via Foundation's markdown parser — same role as the web
/// UI's `renderMarkdown`, without a hand-rolled parser.
enum ChatMarkdown {
    private static let options: AttributedString.MarkdownParsingOptions = {
        var options = AttributedString.MarkdownParsingOptions()
        // `.full` is required for list / paragraph presentation intents;
        // `.inlineOnly` would leave `- item` as literal asterisks/dashes.
        options.interpretedSyntax = .full
        return options
    }()

    static func attributed(_ raw: String) -> AttributedString {
        guard !raw.isEmpty else { return AttributedString() }
        if let parsed = try? AttributedString(markdown: raw, options: options) {
            return parsed
        }
        return AttributedString(raw)
    }
}
