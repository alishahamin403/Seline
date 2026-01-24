import Foundation
import SwiftUI
import Combine

// MARK: - Block Document Controller

class BlockDocumentController: ObservableObject {
    @Published var blocks: [AnyBlock] = []
    @Published var focusedBlockId: UUID?

    private var cancellables = Set<AnyCancellable>()
    private var autoSaveWorkItem: DispatchWorkItem?

    // MARK: - Initialization

    init(blocks: [AnyBlock] = []) {
        self.blocks = blocks.isEmpty ? [AnyBlock.text(TextBlock())] : blocks
    }

    // MARK: - Block Creation

    func createBlock(type: BlockType, after blockId: UUID? = nil) {
        let newBlock: AnyBlock

        switch type {
        case .text:
            newBlock = .text(TextBlock())
        case .heading1:
            newBlock = .heading(HeadingBlock(level: 1))
        case .heading2:
            newBlock = .heading(HeadingBlock(level: 2))
        case .heading3:
            newBlock = .heading(HeadingBlock(level: 3))
        case .bulletList:
            newBlock = .bulletList(BulletListBlock())
        case .numberedList:
            let number = calculateNextNumber(after: blockId)
            newBlock = .numberedList(NumberedListBlock(number: number))
        case .checkbox:
            newBlock = .checkbox(CheckboxBlock())
        case .quote:
            newBlock = .quote(QuoteBlock())
        case .code:
            newBlock = .code(CodeBlock())
        case .divider:
            newBlock = .divider(DividerBlock())
        case .table:
            newBlock = .table(TableBlock())
        }

        if let afterId = blockId, let index = blocks.firstIndex(where: { $0.id == afterId }) {
            blocks.insert(newBlock, at: index + 1)
        } else {
            blocks.append(newBlock)
        }

        focusedBlockId = newBlock.id
    }

    // MARK: - Block Updates

    func updateBlock(_ blockId: UUID, content: String) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let oldContent = blocks[index].content
        blocks[index].content = content

        // Only check for markdown shortcuts when user types a space
        // This prevents content from disappearing while typing
        if content.hasSuffix(" ") && !oldContent.hasSuffix(" ") {
            detectAndConvertMarkdownShortcuts(at: index)
        }

        // Auto-renumber if this is a numbered list
        if case .numberedList = blocks[index] {
            renumberNumberedLists()
        }
    }

    func updateBlockType(_ blockId: UUID, to newType: BlockType) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let currentBlock = blocks[index]
        let content = currentBlock.content
        let metadata = currentBlock.metadata
        let wasNumberedList = currentBlock.blockType == .numberedList

        let newBlock: AnyBlock

        switch newType {
        case .text:
            newBlock = .text(TextBlock(content: content, metadata: metadata))
        case .heading1:
            newBlock = .heading(HeadingBlock(content: content, level: 1, metadata: metadata))
        case .heading2:
            newBlock = .heading(HeadingBlock(content: content, level: 2, metadata: metadata))
        case .heading3:
            newBlock = .heading(HeadingBlock(content: content, level: 3, metadata: metadata))
        case .bulletList:
            newBlock = .bulletList(BulletListBlock(content: content, metadata: metadata))
        case .numberedList:
            let number = calculateNextNumber(after: index > 0 ? blocks[index - 1].id : nil)
            newBlock = .numberedList(NumberedListBlock(content: content, number: number, metadata: metadata))
        case .checkbox:
            newBlock = .checkbox(CheckboxBlock(content: content, metadata: metadata))
        case .quote:
            newBlock = .quote(QuoteBlock(content: content, metadata: metadata))
        case .code:
            newBlock = .code(CodeBlock(content: content, metadata: metadata))
        case .divider:
            newBlock = .divider(DividerBlock(metadata: metadata))
        case .table:
            newBlock = .table(TableBlock(metadata: metadata))
        }

        blocks[index] = newBlock

        // Renumber if converting to/from numbered list
        if wasNumberedList || newType == .numberedList {
            renumberNumberedLists()
        }
    }

    // MARK: - Block Operations

    func deleteBlock(_ blockId: UUID) {
        guard blocks.count > 1 else {
            // Don't delete the last block, just clear it
            if let index = blocks.firstIndex(where: { $0.id == blockId }) {
                blocks[index].content = ""
            }
            return
        }

        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        let wasNumberedList = blocks[index].blockType == .numberedList

        // Focus previous block
        if index > 0 {
            focusedBlockId = blocks[index - 1].id
        } else if index < blocks.count - 1 {
            focusedBlockId = blocks[index + 1].id
        }

        blocks.remove(at: index)

        // Renumber if we deleted a numbered list
        if wasNumberedList {
            renumberNumberedLists()
        }
    }

    func mergeWithPreviousBlock(_ blockId: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }), index > 0 else { return }

        let currentContent = blocks[index].content
        let previousBlock = blocks[index - 1]

        // Merge content into previous block
        blocks[index - 1].content = previousBlock.content + currentContent

        // Remove current block
        blocks.remove(at: index)

        // Focus previous block
        focusedBlockId = previousBlock.id
    }

    func splitBlock(_ blockId: UUID, at position: Int) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        let currentBlock = blocks[index]
        let content = currentBlock.content

        guard position >= 0 && position <= content.count else { return }

        let beforeContent = String(content.prefix(position))
        let afterContent = String(content.suffix(content.count - position))

        // Update current block with before content
        blocks[index].content = beforeContent

        // Create new block with after content (same type)
        let newBlock: AnyBlock

        switch currentBlock.blockType {
        case .text:
            newBlock = .text(TextBlock(content: afterContent, metadata: currentBlock.metadata))
        case .heading1:
            newBlock = .heading(HeadingBlock(content: afterContent, level: 1, metadata: currentBlock.metadata))
        case .heading2:
            newBlock = .heading(HeadingBlock(content: afterContent, level: 2, metadata: currentBlock.metadata))
        case .heading3:
            newBlock = .heading(HeadingBlock(content: afterContent, level: 3, metadata: currentBlock.metadata))
        case .bulletList:
            newBlock = .bulletList(BulletListBlock(content: afterContent, metadata: currentBlock.metadata))
        case .numberedList:
            let number = calculateNextNumber(after: blockId)
            newBlock = .numberedList(NumberedListBlock(content: afterContent, number: number, metadata: currentBlock.metadata))
        case .checkbox:
            newBlock = .checkbox(CheckboxBlock(content: afterContent, metadata: currentBlock.metadata))
        case .quote:
            newBlock = .quote(QuoteBlock(content: afterContent, metadata: currentBlock.metadata))
        case .code:
            newBlock = .code(CodeBlock(content: afterContent, metadata: currentBlock.metadata))
        case .divider:
            newBlock = .text(TextBlock(content: afterContent, metadata: currentBlock.metadata))
        case .table:
            newBlock = .text(TextBlock(content: afterContent, metadata: currentBlock.metadata))
        }

        blocks.insert(newBlock, at: index + 1)
        focusedBlockId = newBlock.id
    }

    func moveBlock(from source: IndexSet, to destination: Int) {
        blocks.move(fromOffsets: source, toOffset: destination)
        renumberNumberedLists()
    }

    func increaseIndent(_ blockId: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        blocks[index].metadata.indentLevel = min(blocks[index].metadata.indentLevel + 1, 5)
    }

    func decreaseIndent(_ blockId: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }
        blocks[index].metadata.indentLevel = max(blocks[index].metadata.indentLevel - 1, 0)
    }

    func toggleCheckbox(_ blockId: UUID) {
        guard let index = blocks.firstIndex(where: { $0.id == blockId }) else { return }

        if case .checkbox(var block) = blocks[index] {
            block.metadata.isChecked.toggle()
            blocks[index] = .checkbox(block)
        }
    }

    // MARK: - Markdown Shortcuts

    private func detectAndConvertMarkdownShortcuts(at index: Int) {
        guard index < blocks.count else { return }

        let block = blocks[index]
        let content = block.content.trimmingCharacters(in: .whitespaces)

        // Empty block shortcuts
        if content.isEmpty { return }

        // Heading shortcuts
        if content.hasPrefix("# ") {
            blocks[index].content = String(content.dropFirst(2).trimmingCharacters(in: .whitespaces))
            updateBlockType(block.id, to: .heading1)
        } else if content.hasPrefix("## ") {
            blocks[index].content = String(content.dropFirst(3).trimmingCharacters(in: .whitespaces))
            updateBlockType(block.id, to: .heading2)
        } else if content.hasPrefix("### ") {
            blocks[index].content = String(content.dropFirst(4).trimmingCharacters(in: .whitespaces))
            updateBlockType(block.id, to: .heading3)
        }
        // Bullet list shortcut
        else if content.hasPrefix("- ") || content.hasPrefix("* ") {
            blocks[index].content = String(content.dropFirst(2).trimmingCharacters(in: .whitespaces))
            updateBlockType(block.id, to: .bulletList)
        }
        // Numbered list shortcut
        else if content.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
            if let match = content.firstMatch(of: #/^(\d+)\.\s/#) {
                blocks[index].content = String(content[match.range.upperBound...].trimmingCharacters(in: .whitespaces))
                updateBlockType(block.id, to: .numberedList)
            }
        }
        // Checkbox shortcut
        else if content.hasPrefix("[] ") || content.hasPrefix("[ ] ") {
            blocks[index].content = String(content.dropFirst(content.hasPrefix("[] ") ? 3 : 4).trimmingCharacters(in: .whitespaces))
            updateBlockType(block.id, to: .checkbox)
        }
        // Quote shortcut
        else if content.hasPrefix("> ") {
            blocks[index].content = String(content.dropFirst(2).trimmingCharacters(in: .whitespaces))
            updateBlockType(block.id, to: .quote)
        }
        // Code block shortcut
        else if content.hasPrefix("```") {
            blocks[index].content = String(content.dropFirst(3).trimmingCharacters(in: .whitespaces))
            updateBlockType(block.id, to: .code)
        }
        // Divider shortcut (exact match, no trailing space needed)
        else if content == "---" || content == "***" || content == "--- " || content == "*** " {
            blocks[index] = .divider(DividerBlock())
        }
    }

    // MARK: - Helper Functions

    private func calculateNextNumber(after blockId: UUID?) -> Int {
        guard let afterId = blockId,
              let index = blocks.firstIndex(where: { $0.id == afterId }) else {
            return 1
        }

        if case .numberedList(let block) = blocks[index] {
            return block.number + 1
        }

        return 1
    }

    private func renumberNumberedLists() {
        var currentNumber = 1
        var lastIndentLevel = 0
        var numberStack: [Int: Int] = [0: 1] // Track number for each indent level

        for (index, block) in blocks.enumerated() {
            if case .numberedList(var numbered) = block {
                let indentLevel = numbered.metadata.indentLevel

                // If indent level increased, start new numbering
                if indentLevel > lastIndentLevel {
                    numberStack[indentLevel] = 1
                }
                // If indent level decreased or stayed same, continue numbering at that level
                else if indentLevel < lastIndentLevel {
                    // Reset all deeper levels
                    for level in (indentLevel + 1)...5 {
                        numberStack[level] = nil
                    }
                }

                let number = numberStack[indentLevel] ?? 1
                numbered.number = number
                blocks[index] = .numberedList(numbered)

                numberStack[indentLevel] = number + 1
                lastIndentLevel = indentLevel
            } else {
                // Reset numbering when we hit a non-numbered-list block
                numberStack = [0: 1]
                lastIndentLevel = 0
            }
        }
    }

    // MARK: - Serialization

    func toMarkdown() -> String {
        blocks.map { block in
            let indent = String(repeating: "  ", count: block.metadata.indentLevel)

            switch block {
            case .text(let b):
                return indent + b.content
            case .heading(let b):
                let hashes = String(repeating: "#", count: b.level)
                return indent + "\(hashes) \(b.content)"
            case .bulletList(let b):
                return indent + "- \(b.content)"
            case .numberedList(let b):
                return indent + "\(b.number). \(b.content)"
            case .checkbox(let b):
                let checkbox = b.metadata.isChecked ? "[x]" : "[ ]"
                return indent + "\(checkbox) \(b.content)"
            case .quote(let b):
                return indent + "> \(b.content)"
            case .code(let b):
                return indent + "```\n\(b.content)\n```"
            case .divider:
                return indent + "---"
            case .table(let b):
                // Convert table to markdown format
                guard !b.rows.isEmpty else { return "" }
                var lines: [String] = []
                
                // Header row
                if let headerRow = b.rows.first {
                    let headerLine = "| " + headerRow.map { $0.content.isEmpty ? " " : $0.content }.joined(separator: " | ") + " |"
                    lines.append(indent + headerLine)
                    
                    // Separator row
                    let separatorLine = "|" + headerRow.map { _ in "---" }.joined(separator: "|") + "|"
                    lines.append(indent + separatorLine)
                }
                
                // Data rows
                for row in b.rows.dropFirst() {
                    let rowLine = "| " + row.map { $0.content.isEmpty ? " " : $0.content }.joined(separator: " | ") + " |"
                    lines.append(indent + rowLine)
                }
                
                return lines.joined(separator: "\n")
            }
        }.joined(separator: "\n")
    }

    func toPlainText() -> String {
        blocks.map { $0.content }.joined(separator: "\n")
    }

    // MARK: - Persistence

    func scheduleAutoSave(saveHandler: @escaping () -> Void) {
        autoSaveWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            saveHandler()
        }

        autoSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }
}

// MARK: - Parsing from Markdown

extension BlockDocumentController {
    static func parseMarkdown(_ markdown: String) -> [AnyBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [AnyBlock] = []
        
        // First, pre-process to detect and convert tables
        var processedLines: [String] = []
        var tableHeaders: [String] = []
        var isInTable = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this is a table row (starts and contains pipes)
            if trimmed.hasPrefix("|") && trimmed.contains("|") {
                // Check if this is a separator row (|---|---|)
                if trimmed.contains("---") || trimmed.contains(":---") || trimmed.contains("---:") {
                    continue // Skip separator rows
                }
                
                // Split by pipe and clean up
                let cells = trimmed.split(separator: "|").map { 
                    String($0).trimmingCharacters(in: .whitespaces) 
                }.filter { !$0.isEmpty }
                
                if cells.isEmpty { continue }
                
                if !isInTable {
                    // First table row = headers
                    tableHeaders = cells
                    isInTable = true
                } else {
                    // Data row - convert to structured format
                    if !cells.isEmpty {
                        // Use first column as section header
                        processedLines.append("## \(cells[0])")
                        
                        // Add remaining columns as bullet points with bold labels
                        for (index, cell) in cells.dropFirst().enumerated() {
                            if index < tableHeaders.count - 1 {
                                let header = tableHeaders[index + 1]
                                processedLines.append("- **\(header):** \(cell)")
                            } else {
                                processedLines.append("- \(cell)")
                            }
                        }
                        processedLines.append("") // Add blank line between rows
                    }
                }
            } else {
                // Not a table row
                if isInTable {
                    // Just exited a table
                    isInTable = false
                    tableHeaders = []
                }
                processedLines.append(trimmed)
            }
        }

        // Now parse the processed lines
        for line in processedLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                continue // Skip empty lines
            }

            // Parse heading
            if let match = trimmed.firstMatch(of: #/^(#{1,3})\s+(.+)/#) {
                let level = match.1.count
                let content = String(match.2)
                blocks.append(.heading(HeadingBlock(content: content, level: level)))
            }
            // Parse bullet list
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2))
                blocks.append(.bulletList(BulletListBlock(content: content)))
            }
            // Parse numbered list
            else if let match = trimmed.firstMatch(of: #/^(\d+)\.\s+(.+)/#) {
                let number = Int(match.1) ?? 1
                let content = String(match.2)
                blocks.append(.numberedList(NumberedListBlock(content: content, number: number)))
            }
            // Parse checkbox
            else if trimmed.hasPrefix("[ ] ") || trimmed.hasPrefix("[x] ") {
                let isChecked = trimmed.hasPrefix("[x]")
                let content = String(trimmed.dropFirst(4))
                blocks.append(.checkbox(CheckboxBlock(content: content, isChecked: isChecked)))
            }
            // Parse quote
            else if trimmed.hasPrefix("> ") {
                let content = String(trimmed.dropFirst(2))
                blocks.append(.quote(QuoteBlock(content: content)))
            }
            // Parse divider
            else if trimmed == "---" || trimmed == "***" {
                blocks.append(.divider(DividerBlock()))
            }
            // Parse code block
            else if trimmed.hasPrefix("```") {
                blocks.append(.code(CodeBlock(content: trimmed)))
            }
            // Default to text
            else {
                blocks.append(.text(TextBlock(content: trimmed)))
            }
        }

        return blocks.isEmpty ? [.text(TextBlock())] : blocks
    }
}
