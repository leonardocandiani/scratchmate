import Foundation

/// Colors (hex/rgba) the preview uses to stay coherent with the editor theme.
public struct MarkdownPalette: Sendable {
    public let background: String
    public let foreground: String
    public let accent: String
    public let secondary: String
    public let codeBackground: String
    public let border: String
    public let isDark: Bool

    public init(
        background: String, foreground: String, accent: String,
        secondary: String, codeBackground: String, border: String, isDark: Bool = true
    ) {
        self.background = background
        self.foreground = foreground
        self.accent = accent
        self.secondary = secondary
        self.codeBackground = codeBackground
        self.border = border
        self.isDark = isDark
    }
}

/// Hand-written markdown -> HTML converter (no external dependency), to feed
/// the editor preview. Covers the common .md subset: headings, emphasis, inline
/// and block code, lists, blockquote, hr, links and paragraphs. It lives in the
/// core on purpose: the parsing is testable without WebKit or AppKit.
public enum MarkdownRenderer {

    /// Converts markdown into the HTML body (without `<html>`/`<head>`).
    public static func renderHTMLBody(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var html: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Blank line: block separator.
            if trimmed.isEmpty { i += 1; continue }

            // Code fence ```lang ... ```
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1  // skips the closing fence
                let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                html.append("<pre><code\(cls)>\(escape(code.joined(separator: "\n")))</code></pre>")
                continue
            }

            // Heading #..######
            if let heading = parseHeading(trimmed) {
                html.append("<h\(heading.level)>\(inline(heading.text))</h\(heading.level)>")
                i += 1; continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                html.append("<hr>")
                i += 1; continue
            }

            // Blockquote (consecutive lines starting with >)
            if trimmed.hasPrefix(">") {
                var quote: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quote.append(inline(String(t.dropFirst()).trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                html.append("<blockquote>\(quote.joined(separator: "<br>"))</blockquote>")
                continue
            }

            // Unordered list
            if isUnorderedItem(trimmed) {
                var items: [String] = []
                while i < lines.count, isUnorderedItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let body = String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2))
                    items.append("<li>\(inline(body))</li>")
                    i += 1
                }
                html.append("<ul>\(items.joined())</ul>")
                continue
            }

            // Ordered list
            if isOrderedItem(trimmed) {
                var items: [String] = []
                while i < lines.count, isOrderedItem(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    let body = t.drop(while: { $0 != " " }).trimmingCharacters(in: .whitespaces)
                    items.append("<li>\(inline(String(body)))</li>")
                    i += 1
                }
                html.append("<ol>\(items.joined())</ol>")
                continue
            }

            // Paragraph: consecutive lines until the next blank line/block.
            var para: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if startsNewBlock(t) { break }
                para.append(inline(t))
                i += 1
            }
            if !para.isEmpty {
                html.append("<p>\(para.joined(separator: "<br>"))</p>")
            } else {
                // Guarantees progress even if the line matched no block (for example, a lone "#"),
                // so it never enters an infinite loop.
                html.append("<p>\(inline(line.trimmingCharacters(in: .whitespaces)))</p>")
                i += 1
            }
        }

        return html.joined(separator: "\n")
    }

    /// True if the line starts a block that is not a paragraph. Used to close the
    /// current paragraph. Mirrors the block detectors of the main loop.
    private static func startsNewBlock(_ t: String) -> Bool {
        t.isEmpty || t.hasPrefix("```") || parseHeading(t) != nil
            || t == "---" || t == "***" || t == "___"
            || t.hasPrefix(">") || isUnorderedItem(t) || isOrderedItem(t)
    }

    /// Full HTML document. Without a palette it follows the system light/dark theme;
    /// with a palette it uses the colors of the active editor theme.
    public static func htmlDocument(_ markdown: String, palette: MarkdownPalette? = nil) -> String {
        let style = palette.map(themedCSS) ?? css
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(style)</style></head>
        <body>\(renderHTMLBody(markdown))</body></html>
        """
    }

    /// CSS generated from the active theme colors (keeps the preview coherent with the editor).
    private static func themedCSS(_ p: MarkdownPalette) -> String {
        """
        :root { color-scheme: \(p.isDark ? "dark" : "light"); }
        body { font: 14px/1.6 -apple-system, system-ui, sans-serif; margin: 16px 20px;
               color: \(p.foreground); background: \(p.background); }
        h1,h2,h3,h4,h5,h6 { line-height: 1.25; margin: 1.2em 0 .5em; }
        h1 { font-size: 1.7em; } h2 { font-size: 1.4em; } h3 { font-size: 1.2em; }
        p { margin: .6em 0; }
        code { font-family: ui-monospace, SFMono-Regular, monospace; font-size: .9em;
               color: \(p.foreground); background: \(p.codeBackground); padding: .1em .35em; border-radius: 4px; }
        pre { background: \(p.codeBackground); padding: 12px 14px; border-radius: 8px; overflow-x: auto; }
        pre code { color: \(p.foreground); background: none; padding: 0; }
        blockquote { margin: .6em 0; padding: .2em 0 .2em 14px; border-left: 3px solid \(p.border); color: \(p.secondary); }
        ul, ol { padding-left: 1.4em; margin: .5em 0; }
        li { margin: .2em 0; }
        a { color: \(p.accent); }
        hr { border: none; border-top: 1px solid \(p.border); margin: 1.2em 0; }
        img { max-width: 100%; }
        """
    }

    // MARK: - Blocks

    private struct Heading { let level: Int; let text: String }

    private static func parseHeading(_ line: String) -> Heading? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        return Heading(level: level, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isUnorderedItem(_ t: String) -> Bool {
        t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
    }

    private static func isOrderedItem(_ t: String) -> Bool {
        guard let dotIdx = t.firstIndex(of: ".") else { return false }
        let prefix = t[t.startIndex..<dotIdx]
        return !prefix.isEmpty && prefix.allSatisfy(\.isNumber) && t[dotIdx...].hasPrefix(". ")
    }

    // MARK: - Inline

    /// Applies emphasis, code spans and links to a fragment, escaping HTML first.
    static func inline(_ text: String) -> String {
        // Protects code spans so emphasis does not leak into them.
        var placeholders: [String] = []
        var working = replaceRegex(text, pattern: "`([^`]+)`") { groups in
            let token = "\u{E000}\(placeholders.count)\u{E001}"
            placeholders.append("<code>\(escape(groups[1]))</code>")
            return token
        }

        working = escape(working)
        working = replaceRegex(working, pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") {
            "<img alt=\"\(attrEscape($0[1]))\" src=\"\(sanitizeURL($0[2]))\">"
        }
        working = replaceRegex(working, pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)") {
            "<a href=\"\(sanitizeURL($0[2]))\">\($0[1])</a>"
        }
        working = replaceRegex(working, pattern: "\\*\\*([^*]+)\\*\\*") { "<strong>\($0[1])</strong>" }
        working = replaceRegex(working, pattern: "__([^_]+)__") { "<strong>\($0[1])</strong>" }
        working = replaceRegex(working, pattern: "\\*([^*]+)\\*") { "<em>\($0[1])</em>" }
        working = replaceRegex(working, pattern: "(?<![A-Za-z0-9])_([^_]+)_(?![A-Za-z0-9])") { "<em>\($0[1])</em>" }

        for (idx, value) in placeholders.enumerated() {
            working = working.replacingOccurrences(of: "\u{E000}\(idx)\u{E001}", with: value)
        }
        return working
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Escapes quotes for a value placed inside a double-quoted HTML attribute.
    /// Assumes &, <, > were already escaped upstream by `escape()`; this only
    /// closes the quote-break vector (e.g. `alt="x" onerror="..."`).
    static func attrEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Sanitises a URL for an href/src attribute: blocks executable schemes
    /// (javascript:, data:, vbscript:, file:) and escapes quotes so the URL
    /// cannot break out of the attribute. Relative and http/https/mailto pass.
    static func sanitizeURL(_ url: String) -> String {
        let scheme = url.trimmingCharacters(in: .whitespaces).lowercased()
        if scheme.hasPrefix("javascript:") || scheme.hasPrefix("data:")
            || scheme.hasPrefix("vbscript:") || scheme.hasPrefix("file:") {
            return "#"
        }
        return attrEscape(url)
    }

    /// Replaces each regex match with the closure's return value (receives the captured groups).
    private static func replaceRegex(
        _ text: String, pattern: String, _ transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var groups: [String] = []
            for g in 0..<m.numberOfRanges {
                let r = m.range(at: g)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result += transform(groups)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static let css = """
    :root { color-scheme: light dark; }
    body {
        font: 14px/1.6 -apple-system, system-ui, sans-serif;
        margin: 16px 20px; color: #1d1d1f; background: #fff;
    }
    h1,h2,h3,h4,h5,h6 { line-height: 1.25; margin: 1.2em 0 .5em; }
    h1 { font-size: 1.7em; } h2 { font-size: 1.4em; } h3 { font-size: 1.2em; }
    p { margin: .6em 0; }
    code { font-family: ui-monospace, SFMono-Regular, monospace; font-size: .9em;
           color: #1d1d1f; background: #f0f0f0; padding: .1em .35em; border-radius: 4px; }
    pre { background: #f4f4f4; padding: 12px 14px; border-radius: 8px; overflow-x: auto; }
    pre code { color: inherit; background: none; padding: 0; }
    blockquote { margin: .6em 0; padding: .2em 0 .2em 14px; border-left: 3px solid #ccc; color: #555; }
    ul, ol { padding-left: 1.4em; margin: .5em 0; }
    li { margin: .2em 0; }
    a { color: #0066cc; }
    hr { border: none; border-top: 1px solid #ccc; margin: 1.2em 0; }
    img { max-width: 100%; }
    /* Dark last, to override the base rules. */
    @media (prefers-color-scheme: dark) {
        body { color: #e6e6e6; background: #1e1e1e; }
        code { color: #e6e6e6; background: #2b2b2b; }
        pre { background: #2b2b2b; }
        pre code { color: #e6e6e6; }
        blockquote { color: #a0a0a0; border-color: #444; }
        a { color: #6cb6ff; }
        hr { border-color: #444; }
    }
    """
}
