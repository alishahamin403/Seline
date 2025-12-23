import SwiftUI

struct BlockTypePickerView: View {
    let currentBlockId: UUID?
    let controller: BlockDocumentController
    @Environment(\.colorScheme) var colorScheme
    @Binding var isPresented: Bool

    private let blockTypes: [BlockType] = [
        .text,
        .heading1,
        .heading2,
        .heading3,
        .bulletList,
        .numberedList,
        .checkbox,
        .quote,
        .code,
        .divider
    ]

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(blockTypes, id: \.self) { type in
                        Button(action: {
                            if let blockId = currentBlockId {
                                controller.updateBlockType(blockId, to: type)
                            }
                            isPresented = false
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 18))
                                    .foregroundColor(.blue)
                                    .frame(width: 28)

                                Text(type.placeholder)
                                    .font(.system(size: 16))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                Spacer()

                                if let blockId = currentBlockId,
                                   let block = controller.blocks.first(where: { $0.id == blockId }),
                                   block.blockType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Change Block Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Quick Action Toolbar

struct BlockToolbar: View {
    let controller: BlockDocumentController
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Heading buttons
                ToolbarButton(icon: "textformat.size.larger", title: "H1") {
                    if let id = controller.focusedBlockId {
                        controller.updateBlockType(id, to: .heading1)
                    }
                }

                ToolbarButton(icon: "textformat.size", title: "H2") {
                    if let id = controller.focusedBlockId {
                        controller.updateBlockType(id, to: .heading2)
                    }
                }

                Divider()
                    .frame(height: 24)

                // List buttons
                ToolbarButton(icon: "list.bullet", title: "Bullet") {
                    if let id = controller.focusedBlockId {
                        controller.updateBlockType(id, to: .bulletList)
                    }
                }

                ToolbarButton(icon: "list.number", title: "Number") {
                    if let id = controller.focusedBlockId {
                        controller.updateBlockType(id, to: .numberedList)
                    }
                }

                ToolbarButton(icon: "checkmark.square", title: "Todo") {
                    if let id = controller.focusedBlockId {
                        controller.updateBlockType(id, to: .checkbox)
                    }
                }

                Divider()
                    .frame(height: 24)

                // Other blocks
                ToolbarButton(icon: "quote.bubble", title: "Quote") {
                    if let id = controller.focusedBlockId {
                        controller.updateBlockType(id, to: .quote)
                    }
                }

                ToolbarButton(icon: "chevron.left.forwardslash.chevron.right", title: "Code") {
                    if let id = controller.focusedBlockId {
                        controller.updateBlockType(id, to: .code)
                    }
                }

                ToolbarButton(icon: "minus", title: "Divider") {
                    if let id = controller.focusedBlockId {
                        controller.createBlock(type: .divider, after: id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

struct ToolbarButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
            .frame(width: 56, height: 52)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BlockToolbar_Previews: PreviewProvider {
    static var previews: some View {
        let controller = BlockDocumentController()
        return VStack {
            Spacer()
            BlockToolbar(controller: controller)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
