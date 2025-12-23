import SwiftUI

struct BlockListView: View {
    @ObservedObject var controller: BlockDocumentController
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(controller.blocks.enumerated()), id: \.element.id) { index, block in
                    if block.blockType == .divider {
                        DividerBlockView()
                            .id(block.id)
                    } else {
                        BlockEditorView(
                            block: block,
                            isFocused: Binding(
                                get: { controller.focusedBlockId == block.id },
                                set: { newValue in
                                    if newValue {
                                        controller.focusedBlockId = block.id
                                    }
                                }
                            ),
                            onContentChange: { newContent in
                                controller.updateBlock(block.id, content: newContent)
                            },
                            onReturn: {
                                handleReturn(for: block, at: index)
                            },
                            onBackspace: {
                                handleBackspace(for: block, at: index)
                            },
                            onTab: {
                                controller.increaseIndent(block.id)
                            },
                            onShiftTab: {
                                controller.decreaseIndent(block.id)
                            }
                        )
                        .id(block.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // Focus this block when tapped
                            controller.focusedBlockId = block.id
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .clipped()
    }

    private func handleReturn(for block: AnyBlock, at index: Int) {
        // Create new block after current one
        let newBlockType: BlockType

        // Determine new block type based on current block
        switch block.blockType {
        case .bulletList:
            newBlockType = block.content.isEmpty ? .text : .bulletList
        case .numberedList:
            newBlockType = block.content.isEmpty ? .text : .numberedList
        case .checkbox:
            newBlockType = block.content.isEmpty ? .text : .checkbox
        case .quote:
            newBlockType = block.content.isEmpty ? .text : .quote
        case .code:
            newBlockType = .code
        default:
            newBlockType = .text
        }

        // If current block is empty, convert to text instead of creating new
        if block.content.isEmpty && block.blockType != .text && block.blockType != .code {
            controller.updateBlockType(block.id, to: .text)
        } else {
            controller.createBlock(type: newBlockType, after: block.id)
        }
    }

    private func handleBackspace(for block: AnyBlock, at index: Int) {
        if block.content.isEmpty {
            if index > 0 {
                // Merge with previous block
                controller.mergeWithPreviousBlock(block.id)
            } else {
                // Convert to text if it's the first block
                if block.blockType != .text {
                    controller.updateBlockType(block.id, to: .text)
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BlockListView_Previews: PreviewProvider {
    static var previews: some View {
        let controller = BlockDocumentController(blocks: [
            .heading(HeadingBlock(content: "My Note Title", level: 1)),
            .text(TextBlock(content: "This is a regular paragraph with some text.")),
            .bulletList(BulletListBlock(content: "First bullet point")),
            .bulletList(BulletListBlock(content: "Second bullet point")),
            .numberedList(NumberedListBlock(content: "First numbered item", number: 1)),
            .numberedList(NumberedListBlock(content: "Second numbered item", number: 2)),
            .checkbox(CheckboxBlock(content: "Task to complete", isChecked: false)),
            .checkbox(CheckboxBlock(content: "Completed task", isChecked: true)),
            .quote(QuoteBlock(content: "This is an inspiring quote")),
            .divider(DividerBlock()),
            .text(TextBlock(content: "More text after divider")),
        ])

        return BlockListView(controller: controller)
            .preferredColorScheme(.dark)
    }
}
#endif
