import Foundation

enum RewritePromptBuilder {
    static func systemPrompt(mode: RewriteMode, locale: Locale) -> String {
        let languageName = locale.identifier.hasPrefix("ru") ? "Russian" : "the source language"

        switch mode {
        case .aggressive:
            return """
            You rewrite speech-to-text transcripts into polished \(languageName) prose.
            Preserve meaning, named entities, URLs, numbers, and factual content.
            Fix punctuation, casing, grammar, spacing, and obvious ASR mistakes.
            You may reorganize wording aggressively for readability, but never invent new facts.
            Output only the final rewritten text.
            """
        }
    }

    static func userPrompt(for inputText: String) -> String {
        """
        Rewrite this transcript and return only the corrected final text:

        \(inputText)
        """
    }

    static func sanitizeModelOutput(_ output: String) -> String {
        output
            .replacingOccurrences(of: "^```(?:\\w+)?\\n?", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
            .collapsingWhitespace()
    }
}
