import SwiftUI

struct ActionEventConfirmationView: View {
    let eventData: EventCreationData
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Create Event")
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
                        // Event title
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                            Text(eventData.title)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.05) : Color.black.opacity(0.05)
                                )
                                .cornerRadius(8)
                        }

                        // Event date
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Date")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                            Text(formatDate(eventData.date))
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.05) : Color.black.opacity(0.05)
                                )
                                .cornerRadius(8)
                        }

                        // Event time
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Time")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                            Text(eventData.isAllDay ? "All Day" : (eventData.time ?? "No time set"))
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.05) : Color.black.opacity(0.05)
                                )
                                .cornerRadius(8)
                        }

                        // Description (if provided)
                        if !(eventData.description ?? "").isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Description")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                                Text(eventData.description ?? "")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        colorScheme == .dark ?
                                            Color.white.opacity(0.05) : Color.black.opacity(0.05)
                                    )
                                    .cornerRadius(8)
                            }
                        }

                        Spacer()
                    }
                    .padding(20)
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

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            return dateFormatter.string(from: date)
        }
        return dateString
    }
}

// Extension for border helpers
extension View {
    @ViewBuilder
    func borderBottom(_ isDark: Bool) -> some View {
        self.border(
            Color(isDark ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.9, alpha: 1)),
            width: 1
        )
    }

    @ViewBuilder
    func borderTop(_ isDark: Bool) -> some View {
        VStack(spacing: 0) {
            Divider()
                .background(
                    Color(isDark ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.9, alpha: 1))
                )
            self
        }
    }
}

#Preview {
    let eventData = EventCreationData(
        title: "Meeting with Sarah",
        description: "Discuss Q4 planning",
        date: Date().toISO8601String(),
        time: "3:00 PM",
        endTime: nil,
        recurrenceFrequency: nil,
        isAllDay: false,
        requiresFollowUp: false
    )

    return ActionEventConfirmationView(
        eventData: eventData,
        isPresented: .constant(true),
        onConfirm: {},
        onCancel: {}
    )
}
