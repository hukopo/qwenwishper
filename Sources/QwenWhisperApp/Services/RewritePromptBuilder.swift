import Foundation

enum RewritePromptBuilder {
    static let defaultSystemPrompt: String = """
        Ты редактор русской диктовки после ASR.
        Превращай сырой транскрипт в аккуратный письменный русский текст.
        Сохраняй исходный смысл, факты, порядок мыслей, имена, числа, даты, адреса, URL и названия.
        Исправляй пунктуацию, регистр, грамматику, согласование, пробелы и только очевидные ошибки распознавания речи.
        Не пересказывай и не сокращай текст без необходимости.
        Не добавляй новые факты, оценки, выводы или детали, которых не было в исходнике.
        Если фраза уже нормальная, измени её минимально.
        Верни только итоговый исправленный текст без пояснений.
        """

    static func systemPrompt(mode: RewriteMode, locale: Locale) -> String {
        switch mode {
        case .aggressive:
            if locale.identifier.hasPrefix("ru") {
                return defaultSystemPrompt
            }

            return """
            You are an editor for speech-to-text transcripts.
            Rewrite the transcript into clean written text in the source language.
            Preserve meaning, facts, names, numbers, dates, URLs, and ordering of ideas.
            Fix punctuation, casing, grammar, spacing, and only obvious ASR mistakes.
            Do not summarize, embellish, or invent new information.
            If the transcript is already good, change it minimally.
            Output only the final corrected text.
            """
        }
    }

    static func userPrompt(for inputText: String) -> String {
        """
        Исправь этот транскрипт и верни только итоговый текст:

        \(inputText)
        """
    }

    static func sanitizeModelOutput(_ output: String) -> String {
        // Strip Qwen3-style chain-of-thought blocks (<think>…</think>) before
        // extracting the final answer. Qwen2.5 never emits these.
        let withoutThinking = output.replacingOccurrences(
            of: "<think>[\\s\\S]*?</think>\\s*",
            with: "",
            options: .regularExpression
        )
        return withoutThinking
            .replacingOccurrences(of: "^```(?:\\w+)?\\n?", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
            .collapsingWhitespace()
    }
}
