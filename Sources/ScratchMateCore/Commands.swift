import Foundation

/// The native Phase 1 commands. Each one is a pure text transformation,
/// which keeps the core testable without touching AppKit or I/O.
public enum NativeCommands {

    /// The 10 Phase 1 commands from the plan, in declaration order.
    public static func all() -> [TextCommand] {
        [
            date, uuid, formatJSON, sortLines, dedupe,
            caseTransform, commentLines, wrapSelection, copyCodeBlock, exportMarkdown,
        ]
    }

    // MARK: - 1. date

    public static let date = TextCommand(
        id: "date",
        title: "Insert ISO 8601 date/time",
        trigger: "::date",
        input: .none,
        output: .insert
    ) { _, ctx in
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: ctx.now)
    }

    // MARK: - 2. uuid

    public static let uuid = TextCommand(
        id: "uuid",
        title: "Generate UUID",
        trigger: "::uuid",
        input: .none,
        output: .insert
    ) { _, _ in
        Foundation.UUID().uuidString.lowercased()
    }

    // MARK: - 3. format JSON

    public static let formatJSON = TextCommand(
        id: "format-json",
        title: "Format JSON (pretty-print)",
        trigger: "::json",
        input: .document,
        output: .replaceDocument
    ) { text, _ in
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              // A top-level scalar (42, true, "x", null) parses with .fragmentsAllowed
              // but JSONSerialization.data(withJSONObject:) below rejects it with an
              // ObjC exception that `try?` cannot catch, crashing the app. Guard it.
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let result = String(data: pretty, encoding: .utf8)
        else {
            // Invalid JSON: returns the text untouched so the content is not destroyed.
            return text
        }
        return result
    }

    // MARK: - 4. sort lines

    public static let sortLines = TextCommand(
        id: "sort-lines",
        title: "Sort lines",
        trigger: "::sort",
        input: .document,
        output: .replaceDocument
    ) { text, _ in
        // Normalise CRLF/CR so a stray \r does not skew the comparison.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let sorted = lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return sorted.joined(separator: "\n")
    }

    // MARK: - 5. dedupe

    public static let dedupe = TextCommand(
        id: "dedupe",
        title: "Remove duplicate lines",
        trigger: "::dedupe",
        input: .document,
        output: .replaceDocument
    ) { text, _ in
        // Normalise CRLF/CR so "item\r" and "item" count as the same line.
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        var seen = Set<String>()
        var result: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if seen.insert(line).inserted {
                result.append(line)
            }
        }
        return result.joined(separator: "\n")
    }

    // MARK: - 6. case transform

    public static let caseTransform = TextCommand(
        id: "case-transform",
        title: "Toggle uppercase/lowercase",
        trigger: "::case",
        input: .selection,
        output: .replaceSelection
    ) { text, _ in
        // Toggle: if it is already all uppercase, go to lowercase; otherwise uppercase.
        let hasLower = text.contains { $0.isLowercase }
        return hasLower ? text.uppercased() : text.lowercased()
    }

    // MARK: - 7. comment lines

    public static let commentLines = TextCommand(
        id: "comment-lines",
        title: "Comment lines",
        trigger: "::comment",
        input: .selection,
        output: .replaceSelection
    ) { text, ctx in
        let leader = commentLeader(for: ctx.languageId)
        return text
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? $0 : "\(leader) \($0)" }
            .joined(separator: "\n")
    }

    // MARK: - 8. wrap selection

    public static let wrapSelection = TextCommand(
        id: "wrap-selection",
        title: "Wrap selection in inline code",
        trigger: "::wrap",
        input: .selection,
        output: .replaceSelection
    ) { text, _ in
        "`\(text)`"
    }

    // MARK: - 9. copy code block

    public static let copyCodeBlock = TextCommand(
        id: "copy-code-block",
        title: "Copy as a markdown code block",
        trigger: "::codeblock",
        input: .document,
        output: .clipboard
    ) { text, ctx in
        let lang = ctx.languageId == "markdown" ? "" : ctx.languageId
        return "```\(lang)\n\(text)\n```"
    }

    // MARK: - 10. export markdown

    public static let exportMarkdown = TextCommand(
        id: "export-markdown",
        title: "Export as markdown",
        trigger: "::export",
        input: .document,
        output: .file
    ) { text, ctx in
        let title = ctx.noteTitle.isEmpty ? Note.derivedTitle(from: text) : ctx.noteTitle
        return "# \(title)\n\n\(text)\n"
    }

    // MARK: - Helpers

    /// Line comment prefix per language. Defaults to `//`.
    public static func commentLeader(for languageId: String) -> String {
        switch languageId.lowercased() {
        case "python", "py", "ruby", "rb", "shell", "sh", "bash", "zsh",
             "yaml", "yml", "toml", "perl", "r", "makefile":
            return "#"
        case "sql", "lua", "haskell", "ada":
            return "--"
        case "lisp", "clojure", "scheme":
            return ";"
        case "vim":
            return "\""
        default:
            return "//"
        }
    }
}
