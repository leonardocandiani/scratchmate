import Foundation

/// Where the command reads its input text from.
public enum CommandInput: String, Sendable {
    case document    // the whole note content
    case selection   // only the current selection (falls back to the document if nothing is selected)
    case none        // reads nothing (for example, generating a uuid)
}

/// What to do with the text the command produces.
public enum CommandOutput: String, Sendable {
    case replaceDocument   // replaces the whole content
    case replaceSelection  // replaces only the selection
    case insert            // inserts at the cursor
    case clipboard         // copies to the clipboard, leaves the note untouched
    case newNote           // creates a new note
    case file              // exports to a file
}

/// Context available at runtime while the command runs. Mirrors the SM_*
/// variables from the plan: selection, line, word, language, path, workspace, branch.
public struct CommandContext: Sendable {
    public var selectedText: String
    public var currentLine: String
    public var currentWord: String
    public var languageId: String
    public var filePath: String?
    public var workspaceRoot: String?
    public var gitBranch: String?
    public var noteContent: String
    public var noteTitle: String
    /// Injectable clock that keeps time-based commands (date) deterministic in tests.
    public var now: Date

    public init(
        selectedText: String = "",
        currentLine: String = "",
        currentWord: String = "",
        languageId: String = "markdown",
        filePath: String? = nil,
        workspaceRoot: String? = nil,
        gitBranch: String? = nil,
        noteContent: String = "",
        noteTitle: String = "",
        now: Date = Date()
    ) {
        self.selectedText = selectedText
        self.currentLine = currentLine
        self.currentWord = currentWord
        self.languageId = languageId
        self.filePath = filePath
        self.workspaceRoot = workspaceRoot
        self.gitBranch = gitBranch
        self.noteContent = noteContent
        self.noteTitle = noteTitle
        self.now = now
    }

    /// Exposes the context as a dictionary of SM_* variables (for a future plugin runtime).
    public func environment() -> [String: String] {
        var env: [String: String] = [
            "SM_SELECTED_TEXT": selectedText,
            "SM_CURRENT_LINE": currentLine,
            "SM_CURRENT_WORD": currentWord,
            "SM_LANGUAGE_ID": languageId,
            "SM_NOTE_CONTENT": noteContent,
            "SM_NOTE_TITLE": noteTitle,
        ]
        if let filePath { env["SM_FILE_PATH"] = filePath }
        if let workspaceRoot { env["SM_WORKSPACE_ROOT"] = workspaceRoot }
        if let gitBranch { env["SM_GIT_BRANCH"] = gitBranch }
        return env
    }
}

/// A command declares its identity, `::` trigger, input/output contract, language
/// scope and the transformation. Native version of the command model from the plan.
public struct TextCommand: Sendable {
    public let id: String
    public let title: String
    public let trigger: String
    public let input: CommandInput
    public let output: CommandOutput
    /// TextMate scopes the command applies to (empty = any language).
    public let scope: [String]
    public let run: @Sendable (_ inputText: String, _ context: CommandContext) -> String

    public init(
        id: String,
        title: String,
        trigger: String,
        input: CommandInput,
        output: CommandOutput,
        scope: [String] = [],
        run: @escaping @Sendable (_ inputText: String, _ context: CommandContext) -> String
    ) {
        self.id = id
        self.title = title
        self.trigger = trigger
        self.input = input
        self.output = output
        self.scope = scope
        self.run = run
    }

    /// True if the command applies to the given languageId (empty scope = always).
    /// Compares by equality of the first segment after "source." (not by substring,
    /// so "source.javascript" does not match "java").
    public func appliesTo(languageId: String) -> Bool {
        guard !scope.isEmpty else { return true }
        return scope.contains { scope in
            let base = scope.hasPrefix("source.") ? String(scope.dropFirst("source.".count)) : scope
            let firstSegment = base.split(separator: ".").first.map(String.init) ?? base
            return firstSegment == languageId
        }
    }
}
