import Testing
@testable import ScratchMateCore

@Suite("Language detector")
struct LanguageDetectorTests {

    @Test("empty content falls back to markdown")
    func emptyIsMarkdown() {
        #expect(LanguageDetector.detect("") == "markdown")
        #expect(LanguageDetector.detect("   \n  ") == "markdown")
    }

    @Test("a JSON object is detected by its braces")
    func detectsJSON() {
        #expect(LanguageDetector.detect("{ \"name\": \"scratchmate\", \"ok\": true }") == "json")
        #expect(LanguageDetector.detect("[1, 2, 3]") == "json")
    }

    @Test("a shell shebang is detected")
    func detectsShell() {
        #expect(LanguageDetector.detect("#!/usr/bin/env bash\necho hello") == "shell")
    }

    @Test("Swift keywords win over prose")
    func detectsSwift() {
        let code = "import Foundation\nfunc greet() -> String {\n    let name = \"x\"\n    return name\n}"
        #expect(LanguageDetector.detect(code) == "swift")
    }

    @Test("plain prose stays markdown")
    func proseIsMarkdown() {
        #expect(LanguageDetector.detect("Just a quick note about the meeting today.") == "markdown")
    }

    @Test("prose wrapped in braces is not mistaken for JSON")
    func bracesProseIsNotJSON() {
        #expect(LanguageDetector.detect("{ remember to call the client back tomorrow }") != "json")
    }

    @Test("prose with stray SQL-ish words is not mistaken for SQL")
    func proseWordsAreNotSQL() {
        #expect(LanguageDetector.detect("I will select a few items from the box where it fits.") != "sql")
    }

    @Test("a real SELECT..FROM statement is detected as SQL")
    func realSelectIsSQL() {
        #expect(LanguageDetector.detect("SELECT id, name FROM users WHERE active = 1") == "sql")
    }
}
