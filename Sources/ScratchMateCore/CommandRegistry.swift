import Foundation

/// Central command registry. Resolves `::` triggers and filters by language scope.
/// The Phase 3 bundles will register their commands here as well.
public final class CommandRegistry: @unchecked Sendable {
    private var commands: [TextCommand]
    private var byTrigger: [String: TextCommand]

    public init(commands: [TextCommand] = NativeCommands.all()) {
        self.commands = commands
        self.byTrigger = Dictionary(
            commands.map { ($0.trigger, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Every registered command.
    public var allCommands: [TextCommand] { commands }

    /// Registers a new command (overwrites if the trigger collides).
    public func register(_ command: TextCommand) {
        if let idx = commands.firstIndex(where: { $0.trigger == command.trigger }) {
            commands[idx] = command
        } else {
            commands.append(command)
        }
        byTrigger[command.trigger] = command
    }

    /// Resolves a command by its exact trigger (for example, "::sort").
    public func command(forTrigger trigger: String) -> TextCommand? {
        byTrigger[trigger]
    }

    /// Filters commands whose trigger starts with the typed prefix, respecting the
    /// active language scope. Orders by relevance (exact match first, then alphabetical).
    public func matches(prefix: String, languageId: String = "markdown") -> [TextCommand] {
        let needle = prefix.lowercased()
        return commands
            .filter { $0.appliesTo(languageId: languageId) }
            .filter { needle.isEmpty || $0.trigger.lowercased().hasPrefix(needle) || $0.title.lowercased().contains(needle) }
            .sorted { lhs, rhs in
                let lExact = lhs.trigger.lowercased() == needle
                let rExact = rhs.trigger.lowercased() == needle
                if lExact != rExact { return lExact }
                return lhs.trigger < rhs.trigger
            }
    }
}
