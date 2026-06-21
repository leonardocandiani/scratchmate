import Testing
import Foundation
@testable import ScratchMateCore

@Suite("Native commands")
struct CommandsTests {

    @Test("date uses the injected clock and formats as ISO 8601")
    func dateUsesInjectedClock() {
        let ctx = CommandContext(now: Date(timeIntervalSince1970: 1_000_000_000))
        let out = NativeCommands.date.run("", ctx)
        #expect(out == "2001-09-09T01:46:40Z")
    }

    @Test("uuid generates a valid lowercase identifier")
    func uuidIsValid() {
        let out = NativeCommands.uuid.run("", CommandContext())
        #expect(out.count == 36)
        #expect(out == out.lowercased())
        #expect(UUID(uuidString: out) != nil)
    }

    @Test("format JSON pretty-prints with sorted keys")
    func formatJSONSortsKeys() {
        let out = NativeCommands.formatJSON.run(#"{"b":1,"a":2}"#, CommandContext())
        #expect(out.contains("\n"))  // became multiline
        let idxA = out.range(of: "\"a\"")!
        let idxB = out.range(of: "\"b\"")!
        #expect(idxA.lowerBound < idxB.lowerBound)  // a before b
        // And it is still equivalent valid JSON.
        let data = out.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Int]
        #expect(obj == ["a": 2, "b": 1])
    }

    @Test("invalid JSON does not destroy the content")
    func formatJSONInvalidIsNoop() {
        let input = "this is not json {"
        let out = NativeCommands.formatJSON.run(input, CommandContext())
        #expect(out == input)
    }

    @Test("a top-level JSON scalar is a no-op, never a crash")
    func formatJSONScalarIsNoop() {
        // These parse with .fragmentsAllowed but cannot be re-serialized at the top
        // level; the command must return them untouched, not abort the process.
        for scalar in ["42", "true", "false", "null", "3.14", "\"hi\""] {
            #expect(NativeCommands.formatJSON.run(scalar, CommandContext()) == scalar)
        }
    }

    @Test("sort orders the lines")
    func sortLines() {
        let out = NativeCommands.sortLines.run("banana\napple\navocado", CommandContext())
        #expect(out == "apple\navocado\nbanana")
    }

    @Test("dedupe removes duplicates while preserving order")
    func dedupePreservesOrder() {
        let out = NativeCommands.dedupe.run("a\nb\na\nc\nb", CommandContext())
        #expect(out == "a\nb\nc")
    }

    @Test("case toggles between uppercase and lowercase")
    func caseToggle() {
        #expect(NativeCommands.caseTransform.run("Hello", CommandContext()) == "HELLO")
        #expect(NativeCommands.caseTransform.run("HELLO", CommandContext()) == "hello")
    }

    @Test("comment uses the right leader per language")
    func commentLeaderByLanguage() {
        let swift = NativeCommands.commentLines.run("a\nb", CommandContext(languageId: "swift"))
        #expect(swift == "// a\n// b")
        let py = NativeCommands.commentLines.run("a\nb", CommandContext(languageId: "python"))
        #expect(py == "# a\n# b")
        let sql = NativeCommands.commentLines.run("a", CommandContext(languageId: "sql"))
        #expect(sql == "-- a")
    }

    @Test("comment does not prefix an empty line")
    func commentSkipsEmptyLines() {
        let out = NativeCommands.commentLines.run("a\n\nb", CommandContext(languageId: "swift"))
        #expect(out == "// a\n\n// b")
    }

    @Test("wrap surrounds the text with inline code")
    func wrapSelection() {
        #expect(NativeCommands.wrapSelection.run("foo", CommandContext()) == "`foo`")
    }

    @Test("copy code block uses the note language")
    func codeBlockUsesLanguage() {
        let out = NativeCommands.copyCodeBlock.run("let x = 1", CommandContext(languageId: "swift"))
        #expect(out == "```swift\nlet x = 1\n```")
    }

    @Test("copy code block omits the language when it is markdown")
    func codeBlockMarkdownNoLang() {
        let out = NativeCommands.copyCodeBlock.run("text", CommandContext(languageId: "markdown"))
        #expect(out == "```\ntext\n```")
    }

    @Test("export markdown derives the title from the content")
    func exportDerivesTitle() {
        let out = NativeCommands.exportMarkdown.run("My note\nbody", CommandContext())
        #expect(out.hasPrefix("# My note\n\n"))
        #expect(out.contains("body"))
    }

    @Test("there are exactly the 10 Phase 1 commands")
    func phaseOneHasTenCommands() {
        #expect(NativeCommands.all().count == 10)
    }
}
