import SwiftUI

struct ActionNoteConfirmationView: View {
    let noteData: NoteCreationData
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var noteTitle: String = ""
    @State private var noteContent: String = ""

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                    isPresented = false
                }

            // Glassy card
            VStack(spacing: 0) {
                // Header - Minimal
                HStack {
                    Text("New Note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    Button(action: {
                        onCancel()
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.shadcnMuted(colorScheme))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 24) {
                        // Note title - Minimal
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Note title", text: $noteTitle)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .padding(.bottom, 8)
                                .overlay(
                                    VStack(spacing: 0) {
                                        Spacer()
                                        Divider()
                                            .opacity(0.3)
                                    }
                                )
                        }

                        Divider()
                            .opacity(0.2)

                        // Note content - Minimal
                        VStack(alignment: .leading, spacing: 10) {
                            TextEditor(text: $noteContent)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .frame(minHeight: 140)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.shadcnMuted(colorScheme).opacity(0.2), lineWidth: 1)
                                )

                            Text("Add any additional details")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color.shadcnMuted(colorScheme))
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                .onAppear {
                    noteTitle = noteData.title
                    noteContent = noteData.content
                }

                // Action Buttons - Minimal
                HStack(spacing: 16) {
                    Button(action: {
                        onCancel()
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.shadcnMuted(colorScheme))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }

                    Button(action: {
                        onConfirm()
                        isPresented = false
                    }) {
                        Text("Create")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white : Color.black)
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.8))
                        .blur(radius: 10)
                )
            }
            .frame(maxWidth: min(UIScreen.main.bounds.width - 32, 480))
            .frame(height: min(UIScreen.main.bounds.height * 0.7, 580))
            .background(
                ZStack {
                    if colorScheme == .dark {
                        Color.black.opacity(0.7)
                    } else {
                        Color.white.opacity(0.9)
                    }

                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
            )
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 10)
        }
    }
}

#Preview {
    let noteData = NoteCreationData(
        title: "Meeting Notes",
        content: "",
        formattedContent: ""
    )

    return ActionNoteConfirmationView(
        noteData: noteData,
        isPresented: .constant(true),
        onConfirm: {},
        onCancel: {}
    )
}
