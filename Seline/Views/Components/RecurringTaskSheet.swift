import SwiftUI

struct RecurringTaskSheet: View {
    let task: TaskItem
    let onFrequencySelected: (RecurrenceFrequency) -> Void

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private var blueColor: Color {
        colorScheme == .dark ?
            Color.white :
            Color.black
    }

    var body: some View {
        VStack(spacing: 0) {
                // Task info header
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "repeat")
                            .foregroundColor(blueColor)
                            .font(.system(size: 20, weight: .medium))

                        Text("Make Recurring")
                            .font(.shadcnTextLgSemibold)
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Task:")
                            .font(.shadcnTextSm)
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                        Text(task.title)
                            .font(.shadcnTextBase)
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                                    .fill(
                                        colorScheme == .dark ?
                                            Color.black.opacity(0.3) : Color.gray.opacity(0.1)
                                    )
                            )

                        Text("Originally scheduled for \(task.weekday.displayName)")
                            .font(.shadcnTextXs)
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Frequency options
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                        FrequencyTile(
                            frequency: frequency,
                            onTap: {
                                onFrequencySelected(frequency)
                                dismiss()
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .background(
                colorScheme == .dark ?
                    Color.gmailDarkBackground : Color.white
            )
            .navigationTitle("Recurring Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                }
            }
        }
}

struct FrequencyTile: View {
    let frequency: RecurrenceFrequency
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme

    private var blueColor: Color {
        colorScheme == .dark ?
            Color.white :
            Color.black
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Icon
                Image(systemName: frequency.icon)
                    .foregroundColor(blueColor)
                    .font(.system(size: 28, weight: .medium))

                // Title
                Text(frequency.displayName)
                    .font(.shadcnTextBaseMedium)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                    .fill(
                        colorScheme == .dark ?
                            Color.black.opacity(0.3) : Color.gray.opacity(0.05)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                            .stroke(
                                colorScheme == .dark ?
                                    Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    RecurringTaskSheet(
        task: TaskItem(title: "Sample recurring task", weekday: .monday),
        onFrequencySelected: { _ in }
    )
}