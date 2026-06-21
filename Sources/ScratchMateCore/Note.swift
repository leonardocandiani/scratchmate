import Foundation

/// A temporary scratchpad note. Plain text content with an optional language
/// for highlighting and command context.
public struct Note: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var content: String
    /// VS Code style language identifier (ts, py, swift, json, markdown...).
    public var languageId: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Fixed slot 1..9 for quick access, or nil if the note is not pinned.
    public var slot: Int?
    /// When the note expires and becomes a cleanup candidate, or nil for a permanent note.
    public var expiresAt: Date?

    public init(
        id: Int64 = 0,
        title: String = "",
        content: String = "",
        languageId: String = "markdown",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        slot: Int? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.languageId = languageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.slot = slot
        self.expiresAt = expiresAt
    }

    /// Derives a readable title from the first non-empty line of the content.
    public static func derivedTitle(from content: String, max: Int = 60) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if firstLine.isEmpty { return "Untitled note" }
        return firstLine.count > max ? String(firstLine.prefix(max)) + "…" : firstLine
    }
}
