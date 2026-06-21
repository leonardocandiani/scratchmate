import Foundation

/// Best-effort language guess from a note's content, used when a note's language
/// is set to "auto". Pure heuristics, no dependency: structural shapes first
/// (JSON, shebang, HTML), then keyword scoring across the supported languages.
/// Returns a languageId from the editor's known set, or "markdown" as the
/// neutral fallback (it renders prose and fenced code reasonably either way).
public enum LanguageDetector {

    public static func detect(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "markdown" }

        // Structural shapes are strong signals, check them before keywords. Require
        // a real parse so "{ just some prose in braces }" is NOT misread as JSON.
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")),
           let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return "json"
        }
        if trimmed.hasPrefix("#!") {
            let firstLine = trimmed.components(separatedBy: "\n").first ?? ""
            if firstLine.contains("/bash") || firstLine.contains("/sh") || firstLine.contains("/zsh") {
                return "shell"
            }
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("<!doctype html") || lower.contains("<html") || lower.contains("</div>") {
            return "html"
        }

        // Keyword scoring: count signals per language, pick the strongest.
        var score: [String: Int] = [:]
        func bump(_ lang: String, _ needles: [String], in haystack: String, weight: Int = 1) {
            for n in needles where haystack.contains(n) { score[lang, default: 0] += weight }
        }
        bump("swift", ["func ", "let ", "var ", "guard ", "import Foundation", "-> ", "@objc", "struct ", "enum "], in: trimmed)
        bump("python", ["def ", "import ", "print(", "elif ", "self.", "__init__", "lambda "], in: trimmed)
        bump("javascript", ["function ", "const ", "=> ", "console.log", "var ", "let ", "require("], in: trimmed)
        bump("typescript", ["interface ", ": string", ": number", "export const", "import type"], in: trimmed)
        bump("go", ["package ", "func ", "import (", ":= ", "fmt."], in: trimmed)
        bump("rust", ["fn ", "let mut", "impl ", "pub fn", "use std", "println!"], in: trimmed)
        // SQL only when the text BEGINS with a statement keyword: prose can contain
        // "select ... from ..." mid-sentence, but rarely opens with it.
        let upper = trimmed.uppercased()
        let sqlOpeners = ["SELECT ", "INSERT INTO ", "UPDATE ", "DELETE FROM ",
                          "CREATE TABLE ", "CREATE ", "ALTER TABLE ", "DROP TABLE ", "WITH "]
        if sqlOpeners.contains(where: { upper.hasPrefix($0) }) {
            score["sql", default: 0] += 3
        }
        bump("shell", ["echo ", "#!/", "export ", "&& ", "| grep", "cd "], in: trimmed)
        bump("markdown", ["# ", "## ", "- ", "* ", "```", "> ", "[", "]("], in: trimmed)

        if let best = score.max(by: { $0.value < $1.value }), best.value > 0 {
            return best.key
        }
        return "markdown"
    }
}
