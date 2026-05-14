import Foundation

package enum DisplayTextSanitizer {
    package static func sanitize(_ text: String) -> String {
        var sanitized = text
        let first = "Vibe"
        let second = "Island"
        for term in [
            "\(first) \(second) UI",
            "\(first)\(second) UI",
            "\(first) \(second)",
            "\(first)\(second)"
        ] {
            sanitized = replace(term, in: sanitized, with: "浮岛 UI")
        }
        return sanitized
    }

    private static func replace(_ term: String, in text: String, with replacement: String) -> String {
        var result = text
        while let range = result.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }
}
