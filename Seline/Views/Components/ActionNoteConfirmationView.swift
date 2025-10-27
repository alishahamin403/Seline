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
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Create Note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Button(action: {
                        onCancel()
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(20)
                .background(colorScheme == .dark ? Color.black : Color.white)
                .borderBottom(colorScheme == .dark)

                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        // Note title
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                            TextField("Note title", text: $noteTitle)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(12)
                                .background(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.05) : Color.black.opacity(0.05)
                                )
                                .cornerRadius(8)
                        }

                        // Note content
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Content (Optional)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                            TextEditor(text: $noteContent)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(12)
                                .frame(minHeight: 120)
                                .background(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.05) : Color.black.opacity(0.05)
                                )
                                .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding(20)
                }
                .onAppear {
                    noteTitle = noteData.title
                    noteContent = noteData.content
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        onCancel()
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(
                                colorScheme == .dark ?
                                    Color.white.opacity(0.1) : Color.black.opacity(0.1)
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        // Update the note data before confirming
                        // Note: We'd need to pass back the updated values
                        onConfirm()
                        isPresented = false
                    }) {
                        Text("Create")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(20)
                .background(colorScheme == .dark ? Color.black : Color.white)
                .borderTop(colorScheme == .dark)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
