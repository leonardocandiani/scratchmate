import Testing
@testable import ScratchMateCore

@Suite("Markdown rendering")
struct MarkdownRendererTests {

    @Test("headings become h1..h6")
    func headings() {
        #expect(MarkdownRenderer.renderHTMLBody("# Title") == "<h1>Title</h1>")
        #expect(MarkdownRenderer.renderHTMLBody("### Sub") == "<h3>Sub</h3>")
        // 7 # is not a valid heading, it becomes a paragraph.
        #expect(MarkdownRenderer.renderHTMLBody("####### x").contains("<p>"))
    }

    @Test("bold and italic emphasis")
    func emphasis() {
        #expect(MarkdownRenderer.renderHTMLBody("**strong**") == "<p><strong>strong</strong></p>")
        #expect(MarkdownRenderer.renderHTMLBody("*italic*") == "<p><em>italic</em></p>")
    }

    @Test("inline and block code")
    func code() {
        #expect(MarkdownRenderer.renderHTMLBody("use `let x`") == "<p>use <code>let x</code></p>")
        let fenced = MarkdownRenderer.renderHTMLBody("```swift\nlet x = 1\n```")
        #expect(fenced.contains("<pre><code class=\"language-swift\">let x = 1</code></pre>"))
    }

    @Test("emphasis does not leak into a code span")
    func emphasisDoesNotLeakIntoCode() {
        let out = MarkdownRenderer.renderHTMLBody("`a*b*c`")
        #expect(out == "<p><code>a*b*c</code></p>")
    }

    @Test("HTML is escaped to prevent injection")
    func escapesHTML() {
        let out = MarkdownRenderer.renderHTMLBody("<script>alert(1)</script>")
        #expect(out.contains("&lt;script&gt;"))
        #expect(!out.contains("<script>"))
    }

    @Test("unordered and ordered lists")
    func lists() {
        #expect(MarkdownRenderer.renderHTMLBody("- a\n- b") == "<ul><li>a</li><li>b</li></ul>")
        #expect(MarkdownRenderer.renderHTMLBody("1. a\n2. b") == "<ol><li>a</li><li>b</li></ol>")
    }

    @Test("links become anchors")
    func links() {
        let out = MarkdownRenderer.renderHTMLBody("[site](https://x.com)")
        #expect(out == "<p><a href=\"https://x.com\">site</a></p>")
    }

    @Test("blockquote and horizontal rule")
    func quoteAndRule() {
        #expect(MarkdownRenderer.renderHTMLBody("> quote") == "<blockquote>quote</blockquote>")
        #expect(MarkdownRenderer.renderHTMLBody("---") == "<hr>")
    }

    @Test("the full document embeds the CSS and the body")
    func fullDocument() {
        let doc = MarkdownRenderer.htmlDocument("# Hi")
        #expect(doc.hasPrefix("<!DOCTYPE html>"))
        #expect(doc.contains("<h1>Hi</h1>"))
        #expect(doc.contains("prefers-color-scheme"))
    }

    @Test("a javascript: link is neutralised, not emitted as an href")
    func linkBlocksJavascriptScheme() {
        let out = MarkdownRenderer.renderHTMLBody("[x](javascript:alert(1))")
        #expect(!out.contains("javascript:"))
        #expect(out.contains("href=\"#\""))
    }

    @Test("a quote in a link URL cannot break out of the attribute")
    func linkEscapesQuoteInURL() {
        let out = MarkdownRenderer.renderHTMLBody("[x](h\" onmouseover=\"alert(1))")
        #expect(!out.contains("onmouseover=\"alert"))
    }

    @Test("an image onerror payload cannot break out of the alt attribute")
    func imageEscapesQuoteInAlt() {
        let out = MarkdownRenderer.renderHTMLBody("![a\" onerror=\"alert(1)](x.png)")
        #expect(!out.contains("onerror=\"alert"))
    }
}
