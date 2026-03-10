import SwiftUI

struct EditVisitTimeSheet: View {
    let visit: LocationVisitRecord
    let place: SavedPlace?
    let colorScheme: ColorScheme
    let onSave: (Date, Date?) async -> String?

    @Environment(\.dismiss) private var dismiss

    @State private var draftEntryTime: Date
    @State private var draftExitTime: Date
    @State private var isOngoing: Bool
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(
        visit: LocationVisitRecord,
        place: SavedPlace?,
        colorScheme: ColorScheme,
        onSave: @escaping (Date, Date?) async -> String?
    ) {
        self.visit = visit
        self.place = place
        self.colorScheme = colorScheme
        self.onSave = onSave
        _draftEntryTime = State(initialValue: visit.entryTime)
        _draftExitTime = State(initialValue: visit.exitTime ?? Date())
        _isOngoing = State(initialValue: visit.exitTime == nil)
    }

    private var entryBinding: Binding<Date> {
        Binding(
            get: { draftEntryTime },
            set: { draftEntryTime = mergedTime(from: $0, into: draftEntryTime) }
        )
    }

    private var exitBinding: Binding<Date> {
        Binding(
            get: { draftExitTime },
            set: { draftExitTime = mergedTime(from: $0, into: draftExitTime) }
        )
    }

    private var validationMessage: String? {
        guard !isOngoing else { return nil }
        guard draftExitTime > draftEntryTime else {
            return "End time must be after the start time."
        }
        return nil
    }

    private var summaryDurationText: String {
        guard !isOngoing else { return "Still ongoing" }

        let minutes = max(Int(draftExitTime.timeIntervalSince(draftEntryTime) / 60), 1)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        return "\(remainingMinutes)m"
    }

    private var visitDateText: String {
        visit.entryTime.formatted(date: .complete, time: .omitted)
    }

    var body: some View {
        ZStack {
            AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .bottomTrailing)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    headerCard
                    timeEditorCard
                    summaryCard
                    footerActions
                }
                .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
        }
        .presentationBg()
        .interactiveDismissDisabled(isSaving)
        .alert("Couldn't Save", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Please try again.")
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit Visit")
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .tracking(0.3)

                    Text(place?.displayName ?? "Visit")
                        .font(FontManager.geist(size: 26, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    Text(visitDateText)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(Color.shadcnTileBackground(colorScheme))
                )
                .buttonStyle(PlainButtonStyle())
                .disabled(isSaving)
            }

            HStack(alignment: .top, spacing: 20) {
                visitStatText(
                    title: "Current",
                    value: timeRangeText(for: visit.entryTime, exitTime: visit.exitTime)
                )

                visitStatText(
                    title: "Duration",
                    value: visit.durationMinutes.map(durationText(minutes:)) ?? "Active"
                )
            }
        }
        .padding(20)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topTrailing,
            cornerRadius: 28,
            highlightStrength: 0.72
        )
    }

    private var timeEditorCard: some View {
        VStack(spacing: 18) {
            timeWheelSection(
                title: "Arrived",
                subtitle: "Adjust when the visit started.",
                selection: entryBinding
            )

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Still ongoing")
                            .font(FontManager.geist(size: 15, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text("Turn this on if the visit does not have an end time yet.")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }

                    Spacer()

                    Toggle("", isOn: $isOngoing)
                        .labelsHidden()
                        .tint(Color.appTextPrimary(colorScheme))
                }

                if !isOngoing {
                    timeWheelSection(
                        title: "Left",
                        subtitle: "Adjust when the visit ended.",
                        selection: exitBinding
                    )
                }
            }

            if let validationMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red.opacity(0.85))

                    Text(validationMessage)
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(.red.opacity(0.9))

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                        .fill(Color.red.opacity(colorScheme == .dark ? 0.16 : 0.08))
                )
            }
        }
        .padding(18)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .bottomLeading,
            cornerRadius: 28,
            highlightStrength: 0.6
        )
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Updated timeline")
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))

                Text(timeRangeText(for: draftEntryTime, exitTime: isOngoing ? nil : draftExitTime))
                    .font(FontManager.geist(size: 20, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                Text(summaryDurationText)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
            }

            Spacer()

            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme).opacity(0.82))
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                        .fill(Color.shadcnTileBackground(colorScheme))
                )
        }
        .padding(18)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topLeading,
            cornerRadius: 26,
            highlightStrength: 0.52
        )
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                dismiss()
            }
            .font(FontManager.geist(size: 16, weight: .semibold))
            .foregroundColor(Color.appTextPrimary(colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.shadcnTileBackground(colorScheme))
            )
            .buttonStyle(PlainButtonStyle())
            .disabled(isSaving)

            Button(action: saveChanges) {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .tint(colorScheme == .dark ? .black : .white)
                    }

                    Text(isSaving ? "Saving" : "Save Changes")
                        .font(FontManager.geist(size: 16, weight: .semibold))
                }
                .foregroundColor(colorScheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isSaving || validationMessage != nil)
            .opacity((isSaving || validationMessage != nil) ? 0.6 : 1)
        }
    }

    private func timeWheelSection(
        title: String,
        subtitle: String,
        selection: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            Text(subtitle)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))

            CustomTimePicker(selection: selection, minuteInterval: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipped()
        }
    }

    private func visitStatText(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .textCase(.uppercase)

            Text(value)
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveChanges() {
        guard !isSaving else { return }

        Task {
            isSaving = true
            let message = await onSave(draftEntryTime, isOngoing ? nil : draftExitTime)
            isSaving = false

            if let message {
                saveErrorMessage = message
            } else {
                dismiss()
            }
        }
    }

    private func mergedTime(from source: Date, into target: Date) -> Date {
        let calendar = Calendar.current
        let sourceComponents = calendar.dateComponents([.hour, .minute], from: source)
        return calendar.date(
            bySettingHour: sourceComponents.hour ?? 0,
            minute: sourceComponents.minute ?? 0,
            second: 0,
            of: target
        ) ?? source
    }

    private func timeRangeText(for entryTime: Date, exitTime: Date?) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        if let exitTime {
            return "\(formatter.string(from: entryTime)) - \(formatter.string(from: exitTime))"
        }

        return "Started at \(formatter.string(from: entryTime))"
    }

    private func durationText(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }

        return "\(remainingMinutes)m"
    }
}
