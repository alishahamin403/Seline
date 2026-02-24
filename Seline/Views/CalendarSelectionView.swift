import SwiftUI
import EventKit

/// View for selecting which iPhone calendars to sync with Seline
struct CalendarSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var calendars: [CalendarMetadata] = []
    @State private var preferences: CalendarSyncPreferences = CalendarSyncPreferences.load()
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasChanges = false

    // Group calendars by source type
    private var groupedCalendars: [(CalendarSourceType, [CalendarMetadata])] {
        let grouped = Dictionary(grouping: calendars) { $0.sourceType }
        return grouped.sorted { $0.key.displayName < $1.key.displayName }
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
    }

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading calendars...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if calendars.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No Calendars Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Please check your calendar permissions in Settings")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    calendarList
                }
            }
            .navigationTitle("Select Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAndDismiss()
                    }
                    .disabled(!hasChanges)
                    .fontWeight(.semibold)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .task {
            await loadCalendars()
        }
    }

    private var calendarList: some View {
        List {
            Section {
                Text("Select which calendars you want to sync with Seline. Events from selected calendars will appear in your timeline and can be marked as complete.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if selectedCount > 0 {
                Section {
                    HStack {
                        Text("\(selectedCount) calendar\(selectedCount == 1 ? "" : "s") selected")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(selectedCount == calendars.count ? "Deselect All" : "Select All") {
                            if selectedCount == calendars.count {
                                preferences.deselectAll()
                            } else {
                                preferences.selectAll(calendarIds: calendars.map { $0.id })
                            }
                            hasChanges = true
                        }
                        .font(.footnote)
                    }
                }
            }

            ForEach(groupedCalendars, id: \.0) { sourceType, calendarsInGroup in
                Section(header: sectionHeader(for: sourceType)) {
                    ForEach(calendarsInGroup) { calendar in
                        CalendarRow(
                            calendar: calendar,
                            isSelected: preferences.isSelected(calendarId: calendar.id)
                        ) { isSelected in
                            if isSelected {
                                preferences.select(calendarId: calendar.id)
                            } else {
                                preferences.deselect(calendarId: calendar.id)
                            }
                            hasChanges = true
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(for sourceType: CalendarSourceType) -> some View {
        HStack(spacing: 8) {
            Image(systemName: sourceType.iconName)
                .font(.footnote)
            Text(sourceType.displayName)
                .textCase(.uppercase)
        }
    }

    private var selectedCount: Int {
        calendars.filter { preferences.isSelected(calendarId: $0.id) }.count
    }

    private func loadCalendars() async {
        isLoading = true
        defer { isLoading = false }

        do {
            calendars = await CalendarSyncService.shared.fetchAvailableCalendars()
            if calendars.isEmpty {
                errorMessage = "No calendars available. Please check permissions."
                showError = true
            }
        } catch {
            errorMessage = "Failed to load calendars: \(error.localizedDescription)"
            showError = true
        }
    }

    private func saveAndDismiss() {
        preferences.save()
        print("✅ Saved calendar selection: \(preferences.selectedCalendarIds.count) calendars")

        // Notify that calendar selection changed - trigger a resync
        NotificationCenter.default.post(name: .calendarSelectionChanged, object: nil)

        dismiss()
    }
}

// MARK: - Calendar Row

struct CalendarRow: View {
    let calendar: CalendarMetadata
    let isSelected: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack(spacing: 12) {
                // Calendar color indicator
                Circle()
                    .fill(hexToColor(calendar.color))
                    .frame(width: 12, height: 12)

                // Calendar title
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                        .foregroundColor(.primary)
                        .font(.body)

                    if !calendar.allowsContentModifications {
                        Text("Read-only")
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Helper to convert hex string to Color
    private func hexToColor(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return .gray
        }

        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let calendarSelectionChanged = Notification.Name("calendarSelectionChanged")
}

// MARK: - Preview

#Preview {
    CalendarSelectionView()
}
