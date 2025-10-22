import Foundation
import SwiftUI

// MARK: - Todo Item Models

/// Represents a single todo item
struct TodoItem: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var isCompleted: Bool
    var dateCreated: Date
    var dateModified: Date

    init(text: String, isCompleted: Bool = false) {
        self.id = UUID()
        self.text = text
        self.isCompleted = isCompleted
        self.dateCreated = Date()
        self.dateModified = Date()
    }

    mutating func toggle() {
        isCompleted.toggle()
        dateModified = Date()
    }

    mutating func updateText(_ newText: String) {
        text = newText
        dateModified = Date()
    }
}

/// Represents a todo list embedded in a note
struct NoteTodoList: Identifiable, Codable, Hashable {
    var id: UUID
    var items: [TodoItem]
    var dateCreated: Date
    var dateModified: Date

    init(items: [TodoItem] = []) {
        self.id = UUID()
        self.items = items.isEmpty ? [
            TodoItem(text: ""),
            TodoItem(text: ""),
            TodoItem(text: ""),
            TodoItem(text: ""),
            TodoItem(text: "")
        ] : items
        self.dateCreated = Date()
        self.dateModified = Date()
    }

    /// Add a new todo item
    mutating func addItem(_ text: String = "") {
        let newItem = TodoItem(text: text)
        items.append(newItem)
        dateModified = Date()
    }

    /// Remove a todo item
    mutating func removeItem(at index: Int) {
        guard index < items.count && items.count > 1 else { return }
        items.remove(at: index)
        dateModified = Date()
    }

    /// Toggle completion state of a todo item
    mutating func toggleItem(at index: Int) {
        guard index < items.count else { return }
        items[index].toggle()
        dateModified = Date()
    }

    /// Update text of a todo item
    mutating func updateItem(at index: Int, text: String) {
        guard index < items.count else { return }
        items[index].updateText(text)
        dateModified = Date()
    }

    /// Get completion percentage
    var completionPercentage: Int {
        guard !items.isEmpty else { return 0 }
        let completed = items.filter { $0.isCompleted }.count
        return Int((Double(completed) / Double(items.count)) * 100)
    }

    /// Convert to markdown format
    func toMarkdown() -> String {
        items.map { item in
            let checkbox = item.isCompleted ? "[x]" : "[ ]"
            return "- \(checkbox) \(item.text)"
        }.joined(separator: "\n")
    }

    /// Create todo list from markdown string
    static func fromMarkdown(_ markdown: String) -> NoteTodoList? {
        let lines = markdown.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        var items: [TodoItem] = []

        for line in lines {
            // Match todo patterns: "- [ ] text" or "- [x] text"
            // Also match: "* [ ] text", "• [ ] text"
            if line.hasPrefix("- [ ]") || line.hasPrefix("- []") {
                let text = line.replacingOccurrences(of: "- [ ]", with: "")
                    .replacingOccurrences(of: "- []", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(text: text, isCompleted: false))
            } else if line.hasPrefix("- [x]") || line.hasPrefix("- [X]") {
                let text = line.replacingOccurrences(of: "- [x]", with: "")
                    .replacingOccurrences(of: "- [X]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(text: text, isCompleted: true))
            } else if line.hasPrefix("* [ ]") || line.hasPrefix("* []") {
                let text = line.replacingOccurrences(of: "* [ ]", with: "")
                    .replacingOccurrences(of: "* []", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(text: text, isCompleted: false))
            } else if line.hasPrefix("* [x]") || line.hasPrefix("* [X]") {
                let text = line.replacingOccurrences(of: "* [x]", with: "")
                    .replacingOccurrences(of: "* [X]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(text: text, isCompleted: true))
            } else if line.hasPrefix("• [ ]") || line.hasPrefix("• []") {
                let text = line.replacingOccurrences(of: "• [ ]", with: "")
                    .replacingOccurrences(of: "• []", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(text: text, isCompleted: false))
            } else if line.hasPrefix("• [x]") || line.hasPrefix("• [X]") {
                let text = line.replacingOccurrences(of: "• [x]", with: "")
                    .replacingOccurrences(of: "• [X]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                items.append(TodoItem(text: text, isCompleted: true))
            }
        }

        guard !items.isEmpty else { return nil }

        return NoteTodoList(items: items)
    }

    /// Create todo list from any text (bullet points, numbered lists, or plain lines)
    static func fromText(_ text: String) -> NoteTodoList? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        var items: [TodoItem] = []

        for line in lines {
            var todoText = line

            // Remove bullet points (-, *, •)
            if todoText.hasPrefix("- ") {
                todoText = String(todoText.dropFirst(2))
            } else if todoText.hasPrefix("* ") {
                todoText = String(todoText.dropFirst(2))
            } else if todoText.hasPrefix("• ") {
                todoText = String(todoText.dropFirst(2))
            }

            // Remove numbered list markers (1. 2. 3. etc.)
            let numberPattern = /^(\d+)\.\s+/
            if let match = todoText.firstMatch(of: numberPattern) {
                todoText = String(todoText[match.range.upperBound...])
            }

            // Trim and add as todo item
            let trimmedText = todoText.trimmingCharacters(in: .whitespaces)
            if !trimmedText.isEmpty {
                items.append(TodoItem(text: trimmedText, isCompleted: false))
            }
        }

        guard !items.isEmpty else { return nil }

        return NoteTodoList(items: items)
    }
}

// MARK: - Todo Marker

/// Helper to insert todo list markers in note content
struct TodoMarker {
    static func marker(for todoId: UUID) -> String {
        return "[TODO:\(todoId.uuidString)]"
    }

    static func extractTodoId(from marker: String) -> UUID? {
        let pattern = "\\[TODO:([0-9A-F-]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: marker, range: NSRange(marker.startIndex..., in: marker)),
              let range = Range(match.range(at: 1), in: marker) else {
            return nil
        }
        return UUID(uuidString: String(marker[range]))
    }

    static func hasTodoMarker(_ text: String) -> Bool {
        let pattern = "\\[TODO:[0-9A-F-]+\\]"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func extractAllTodoIds(from text: String) -> [UUID] {
        let pattern = "\\[TODO:([0-9A-F-]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match -> UUID? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return UUID(uuidString: String(text[range]))
        }
    }
}
