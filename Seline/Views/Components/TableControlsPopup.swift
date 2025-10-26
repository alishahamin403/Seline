import SwiftUI

struct TableControlsPopup: View {
    @Environment(\.colorScheme) var colorScheme

    let canAddRow: Bool
    let canAddColumn: Bool
    let onAddRow: () -> Void
    let onAddColumn: () -> Void
    let onDeleteTable: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Add Row option
            Button(action: {
                HapticManager.shared.buttonTap()
                onAddRow()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 14, weight: .medium))
                    Text("Add Row")
                        .font(.system(size: 14, weight: .regular))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .disabled(!canAddRow)
            .foregroundColor(!canAddRow ? .gray : (colorScheme == .dark ? .white : .black))

            Divider()
                .padding(.vertical, 0)

            // Add Column option
            Button(action: {
                HapticManager.shared.buttonTap()
                onAddColumn()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("Add Column")
                        .font(.system(size: 14, weight: .regular))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .disabled(!canAddColumn)
            .foregroundColor(!canAddColumn ? .gray : (colorScheme == .dark ? .white : .black))

            Divider()
                .padding(.vertical, 0)

            // Delete Table option
            Button(action: {
                HapticManager.shared.buttonTap()
                showDeleteConfirm = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                    Text("Delete Table")
                        .font(.system(size: 14, weight: .regular))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .foregroundColor(.red)
        }
        .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
        .alert("Delete Table?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                HapticManager.shared.delete()
                onDeleteTable()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

#Preview {
    TableControlsPopup(
        canAddRow: true,
        canAddColumn: true,
        onAddRow: { print("Add row") },
        onAddColumn: { print("Add column") },
        onDeleteTable: { print("Delete table") }
    )
    .padding()
}
