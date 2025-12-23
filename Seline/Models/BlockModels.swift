import Foundation
import SwiftUI

// MARK: - Block Protocol

protocol Block: Identifiable, Codable, Equatable {
    var id: UUID { get }
    var content: String { get set }
    var blockType: BlockType { get }
    var createdAt: Date { get }
    var metadata: BlockMetadata { get set }
}

// MARK: - Block Types

enum BlockType: String, Codable {
    case text
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case checkbox
    case quote
    case code
    case divider

    var placeholder: String {
        switch self {
        case .text: return "Type something..."
        case .heading1: return "Heading 1"
        case .heading2: return "Heading 2"
        case .heading3: return "Heading 3"
        case .bulletList: return "List item"
        case .numberedList: return "List item"
        case .checkbox: return "To-do"
        case .quote: return "Quote"
        case .code: return "Code"
        case .divider: return ""
        }
    }

    var icon: String {
        switch self {
        case .text: return "text.alignleft"
        case .heading1: return "textformat.size.larger"
        case .heading2: return "textformat.size"
        case .heading3: return "textformat"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .checkbox: return "checkmark.square"
        case .quote: return "quote.bubble"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .divider: return "minus"
        }
    }
}

// MARK: - Block Metadata

struct BlockMetadata: Codable, Equatable {
    var isBold: Bool = false
    var isItalic: Bool = false
    var isUnderline: Bool = false
    var isStrikethrough: Bool = false
    var isChecked: Bool = false // For checkbox blocks
    var indentLevel: Int = 0
    var color: String? = nil
    var backgroundColor: String? = nil

    static var empty: BlockMetadata {
        BlockMetadata()
    }
}

// MARK: - Text Formatting

struct TextRange: Codable, Equatable {
    let location: Int
    let length: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

struct FormattedRange: Codable, Equatable {
    let range: TextRange
    let isBold: Bool
    let isItalic: Bool
    let isUnderline: Bool
    let isCode: Bool
}

// MARK: - Concrete Block Implementations

struct TextBlock: Block {
    let id: UUID
    var content: String
    var createdAt: Date
    var metadata: BlockMetadata

    var blockType: BlockType { .text }

    init(id: UUID = UUID(), content: String = "", metadata: BlockMetadata = .empty) {
        self.id = id
        self.content = content
        self.createdAt = Date()
        self.metadata = metadata
    }
}

struct HeadingBlock: Block {
    let id: UUID
    var content: String
    var createdAt: Date
    var metadata: BlockMetadata
    var level: Int // 1, 2, or 3

    var blockType: BlockType {
        switch level {
        case 1: return .heading1
        case 2: return .heading2
        default: return .heading3
        }
    }

    init(id: UUID = UUID(), content: String = "", level: Int = 1, metadata: BlockMetadata = .empty) {
        self.id = id
        self.content = content
        self.level = min(max(level, 1), 3)
        self.createdAt = Date()
        self.metadata = metadata
    }
}

struct BulletListBlock: Block {
    let id: UUID
    var content: String
    var createdAt: Date
    var metadata: BlockMetadata

    var blockType: BlockType { .bulletList }

    init(id: UUID = UUID(), content: String = "", metadata: BlockMetadata = .empty) {
        self.id = id
        self.content = content
        self.createdAt = Date()
        self.metadata = metadata
    }
}

struct NumberedListBlock: Block {
    let id: UUID
    var content: String
    var createdAt: Date
    var metadata: BlockMetadata
    var number: Int

    var blockType: BlockType { .numberedList }

    init(id: UUID = UUID(), content: String = "", number: Int = 1, metadata: BlockMetadata = .empty) {
        self.id = id
        self.content = content
        self.number = number
        self.createdAt = Date()
        self.metadata = metadata
    }
}

struct CheckboxBlock: Block {
    let id: UUID
    var content: String
    var createdAt: Date
    var metadata: BlockMetadata

    var blockType: BlockType { .checkbox }

    var isChecked: Bool {
        get { metadata.isChecked }
        set { metadata.isChecked = newValue }
    }

    init(id: UUID = UUID(), content: String = "", isChecked: Bool = false, metadata: BlockMetadata = .empty) {
        self.id = id
        self.content = content
        self.createdAt = Date()
        var meta = metadata
        meta.isChecked = isChecked
        self.metadata = meta
    }
}

struct QuoteBlock: Block {
    let id: UUID
    var content: String
    var createdAt: Date
    var metadata: BlockMetadata

    var blockType: BlockType { .quote }

    init(id: UUID = UUID(), content: String = "", metadata: BlockMetadata = .empty) {
        self.id = id
        self.content = content
        self.createdAt = Date()
        self.metadata = metadata
    }
}

struct CodeBlock: Block {
    let id: UUID
    var content: String
    var createdAt: Date
    var metadata: BlockMetadata
    var language: String?

    var blockType: BlockType { .code }

    init(id: UUID = UUID(), content: String = "", language: String? = nil, metadata: BlockMetadata = .empty) {
        self.id = id
        self.content = content
        self.language = language
        self.createdAt = Date()
        self.metadata = metadata
    }
}

struct DividerBlock: Block {
    let id: UUID
    var content: String = ""
    var createdAt: Date
    var metadata: BlockMetadata

    var blockType: BlockType { .divider }

    init(id: UUID = UUID(), metadata: BlockMetadata = .empty) {
        self.id = id
        self.createdAt = Date()
        self.metadata = metadata
    }
}

// MARK: - Type-Erased Block Container

enum AnyBlock: Codable, Equatable, Identifiable {
    case text(TextBlock)
    case heading(HeadingBlock)
    case bulletList(BulletListBlock)
    case numberedList(NumberedListBlock)
    case checkbox(CheckboxBlock)
    case quote(QuoteBlock)
    case code(CodeBlock)
    case divider(DividerBlock)

    var id: UUID {
        switch self {
        case .text(let block): return block.id
        case .heading(let block): return block.id
        case .bulletList(let block): return block.id
        case .numberedList(let block): return block.id
        case .checkbox(let block): return block.id
        case .quote(let block): return block.id
        case .code(let block): return block.id
        case .divider(let block): return block.id
        }
    }

    var content: String {
        get {
            switch self {
            case .text(let block): return block.content
            case .heading(let block): return block.content
            case .bulletList(let block): return block.content
            case .numberedList(let block): return block.content
            case .checkbox(let block): return block.content
            case .quote(let block): return block.content
            case .code(let block): return block.content
            case .divider(let block): return block.content
            }
        }
        set {
            switch self {
            case .text(var block):
                block.content = newValue
                self = .text(block)
            case .heading(var block):
                block.content = newValue
                self = .heading(block)
            case .bulletList(var block):
                block.content = newValue
                self = .bulletList(block)
            case .numberedList(var block):
                block.content = newValue
                self = .numberedList(block)
            case .checkbox(var block):
                block.content = newValue
                self = .checkbox(block)
            case .quote(var block):
                block.content = newValue
                self = .quote(block)
            case .code(var block):
                block.content = newValue
                self = .code(block)
            case .divider: break
            }
        }
    }

    var blockType: BlockType {
        switch self {
        case .text: return .text
        case .heading(let block): return block.blockType
        case .bulletList: return .bulletList
        case .numberedList: return .numberedList
        case .checkbox: return .checkbox
        case .quote: return .quote
        case .code: return .code
        case .divider: return .divider
        }
    }

    var metadata: BlockMetadata {
        get {
            switch self {
            case .text(let block): return block.metadata
            case .heading(let block): return block.metadata
            case .bulletList(let block): return block.metadata
            case .numberedList(let block): return block.metadata
            case .checkbox(let block): return block.metadata
            case .quote(let block): return block.metadata
            case .code(let block): return block.metadata
            case .divider(let block): return block.metadata
            }
        }
        set {
            switch self {
            case .text(var block):
                block.metadata = newValue
                self = .text(block)
            case .heading(var block):
                block.metadata = newValue
                self = .heading(block)
            case .bulletList(var block):
                block.metadata = newValue
                self = .bulletList(block)
            case .numberedList(var block):
                block.metadata = newValue
                self = .numberedList(block)
            case .checkbox(var block):
                block.metadata = newValue
                self = .checkbox(block)
            case .quote(var block):
                block.metadata = newValue
                self = .quote(block)
            case .code(var block):
                block.metadata = newValue
                self = .code(block)
            case .divider(var block):
                block.metadata = newValue
                self = .divider(block)
            }
        }
    }
}
