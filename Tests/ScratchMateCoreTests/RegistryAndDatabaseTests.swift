import Testing
import Foundation
@testable import ScratchMateCore

@Suite("Command registry")
struct CommandRegistryTests {

    @Test("resolves a command by its exact trigger")
    func resolvesByTrigger() {
        let registry = CommandRegistry()
        #expect(registry.command(forTrigger: "::sort")?.id == "sort-lines")
        #expect(registry.command(forTrigger: "::nonexistent") == nil)
    }

    @Test("filters by trigger prefix")
    func matchesByPrefix() {
        let registry = CommandRegistry()
        let hits = registry.matches(prefix: "::d")
        #expect(hits.contains { $0.id == "date" })
        #expect(hits.contains { $0.id == "dedupe" })
        #expect(!hits.contains { $0.id == "sort-lines" })
    }

    @Test("also filters by substring in the title")
    func matchesByTitle() {
        let registry = CommandRegistry()
        let hits = registry.matches(prefix: "json")
        #expect(hits.contains { $0.id == "format-json" })
    }

    @Test("an empty query returns every applicable command")
    func emptyQueryReturnsAll() {
        let registry = CommandRegistry()
        #expect(registry.matches(prefix: "").count == 10)
    }

    @Test("a scoped command only shows up for the right language")
    func scopeFiltering() {
        let scoped = TextCommand(
            id: "ts-only", title: "TS only", trigger: "::tsonly",
            input: .document, output: .replaceDocument, scope: ["source.ts"]
        ) { text, _ in text }
        let registry = CommandRegistry()
        registry.register(scoped)
        #expect(registry.matches(prefix: "::tsonly", languageId: "ts").contains { $0.id == "ts-only" })
        #expect(!registry.matches(prefix: "::tsonly", languageId: "python").contains { $0.id == "ts-only" })
    }

    @Test("scope does not match a language by substring (java vs javascript)")
    func scopeNoSubstringMatch() {
        let cmd = TextCommand(
            id: "x", title: "x", trigger: "::x", input: .document,
            output: .replaceDocument, scope: ["source.javascript"]
        ) { t, _ in t }
        #expect(cmd.appliesTo(languageId: "javascript"))
        #expect(!cmd.appliesTo(languageId: "java"))
        #expect(!cmd.appliesTo(languageId: "script"))
    }

    @Test("register overwrites a colliding trigger")
    func registerOverwrites() {
        let registry = CommandRegistry()
        let custom = TextCommand(
            id: "custom-sort", title: "Custom sort", trigger: "::sort",
            input: .document, output: .replaceDocument
        ) { text, _ in text }
        registry.register(custom)
        #expect(registry.command(forTrigger: "::sort")?.id == "custom-sort")
    }
}

@Suite("SQLite storage")
struct DatabaseTests {

    private func makeDB() throws -> Database {
        try Database(path: ":memory:")
    }

    @Test("insert assigns an id and persists")
    func insertAssignsID() throws {
        let db = try makeDB()
        let saved = try db.insert(Note(content: "hello world", languageId: "swift"))
        #expect(saved.id > 0)
        let fetched = try db.note(id: saved.id)
        #expect(fetched?.content == "hello world")
        #expect(fetched?.languageId == "swift")
    }

    @Test("update changes the content")
    func updateChangesContent() throws {
        let db = try makeDB()
        var note = try db.insert(Note(content: "before"))
        note.content = "after"
        try db.update(note)
        #expect(try db.note(id: note.id)?.content == "after")
    }

    @Test("delete removes the note")
    func deleteRemoves() throws {
        let db = try makeDB()
        let note = try db.insert(Note(content: "temp"))
        try db.delete(id: note.id)
        #expect(try db.note(id: note.id) == nil)
    }

    @Test("recentNotes orders by updated_at desc")
    func recentOrdering() throws {
        let db = try makeDB()
        let old = Date(timeIntervalSince1970: 1000)
        let new = Date(timeIntervalSince1970: 2000)
        _ = try db.insert(Note(content: "old", updatedAt: old))
        _ = try db.insert(Note(content: "new", updatedAt: new))
        let recent = try db.recentNotes()
        #expect(recent.first?.content == "new")
    }

    @Test("search finds by substring in title or content")
    func searchFindsSubstring() throws {
        let db = try makeDB()
        _ = try db.insert(Note(title: "Recipe", content: "chocolate cake"))
        _ = try db.insert(Note(title: "Code", content: "let x = 1"))
        #expect(try db.search("cake").count == 1)
        #expect(try db.search("CODE").count == 1)  // LIKE is case-insensitive for ASCII
        #expect(try db.search("nonexistent").isEmpty)
    }

    @Test("search escapes the LIKE wildcards")
    func searchEscapesWildcards() throws {
        let db = try makeDB()
        _ = try db.insert(Note(content: "axb"))
        _ = try db.insert(Note(content: "a_b"))
        let hits = try db.search("a_b")
        #expect(hits.count == 1)
        #expect(hits.first?.content == "a_b")
    }

    @Test("purgeExpired removes only the expired notes")
    func purgeExpiredRemovesPast() throws {
        let db = try makeDB()
        let now = Date(timeIntervalSince1970: 5000)
        _ = try db.insert(Note(content: "expired", expiresAt: Date(timeIntervalSince1970: 4000)))
        _ = try db.insert(Note(content: "future", expiresAt: Date(timeIntervalSince1970: 6000)))
        _ = try db.insert(Note(content: "permanent", expiresAt: nil))
        let removed = try db.purgeExpired(now: now)
        #expect(removed == 1)
        #expect(try db.recentNotes().count == 2)
    }
}
