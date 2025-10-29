import SwiftUI

struct NoteUpdateConfirmationView: View {
    let updateData: NoteUpdateData
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var contentToAdd: String = ""

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
                    Text("Update Note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 24) {
                        // Target note title
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Updating")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.shadcnMuted(colorScheme))

                            HStack(spacing: 8) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.blue)

                                Text(updateData.noteTitle)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.shadcnForeground(colorScheme))

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }

                        Divider()
                            .opacity(0.2)

                        // Content to add
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Adding to note")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color.shadcnMuted(colorScheme))

                            TextEditor(text: $contentToAdd)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .frame(minHeight: 120)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.shadcnMuted(colorScheme).opacity(0.2), lineWidth: 1)
                                )

                            Text("Modify if needed before confirming")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color.shadcnMuted(colorScheme))
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
                .onAppear {
                    contentToAdd = updateData.contentToAdd
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
                        Text("Update")
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
            .frame(height: min(UIScreen.main.bounds.height * 0.75, 620))
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
    let updateData = NoteUpdateData(
        noteTitle: "Meeting Notes",
        contentToAdd: "Q4 planning discussion: Need to increase budget by 15% for new initiatives. Timeline: Q1 2024.",
        formattedContentToAdd: "Q4 planning discussion: Need to increase budget by 15% for new initiatives. Timeline: Q1 2024."
    )

    NoteUpdateConfirmationView(
        updateData: updateData,
        isPresented: .constant(true),
        onConfirm: {},
        onCancel: {}
    )
}
