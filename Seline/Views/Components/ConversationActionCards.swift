import SwiftUI

struct NoteDraftCard: View {
    let draft: NoteDraftInfo
    let status: AgentActionDraftStatus
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(title: "Note Draft", status: status)

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(FontManager.geist(size: 15, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Text(draft.content)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.75))
                    .lineLimit(6)
            }

            if status == .pending {
                actionButtons(confirmLabel: "Open Draft", onConfirm: onConfirm, onCancel: onCancel)
            }
        }
        .actionCardSurface(colorScheme: colorScheme)
    }
}

struct EmailPreviewCard: View {
    let preview: EmailPreviewInfo
    let onOpenEmail: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(title: "Latest Email", status: nil)

            Button(action: onOpenEmail) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.senderName)
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.62))
                            Text(preview.subject)
                                .font(FontManager.geist(size: 15, weight: .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Text(preview.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.5))
                            .multilineTextAlignment(.trailing)
                    }

                    if !preview.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary")
                                .font(FontManager.geist(size: 11, weight: .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.55))
                                .textCase(.uppercase)
                                .tracking(0.5)

                            Text(preview.summary)
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.82))
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Text(preview.bodyPreview)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.68))
                        .multilineTextAlignment(.leading)
                        .lineLimit(6)
                }
            }
            .buttonStyle(PlainButtonStyle())

            if !preview.attachments.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Attachments")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.55))
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ForEach(preview.attachments) { attachment in
                        AttachmentRow(
                            attachment: attachment,
                            emailMessageId: preview.gmailMessageId
                        )
                    }
                }
            }
        }
        .actionCardSurface(colorScheme: colorScheme)
    }
}

struct LivePlacePreviewCard: View {
    let preview: LivePlacePreviewInfo
    let folderName: String?
    let status: AgentActionDraftStatus?
    let showSaveActions: Bool
    let onOpenPlace: (PlaceSearchResult) -> Void
    let onConfirmSave: (String?) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var sharedLocationManager = SharedLocationManager.shared
    @State private var selectedCategory = ""
    @State private var showingCategoryPicker = false

    private var primaryResult: PlaceSearchResult? {
        preview.results.first(where: { $0.id == preview.selectedPlaceId }) ?? preview.results.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow(title: "Nearby Place", status: status)

            if let primaryResult {
                Button(action: {
                    onOpenPlace(primaryResult)
                }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryResult.name)
                            .font(FontManager.geist(size: 15, weight: .semibold))
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        Text(primaryResult.address)
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.72))

                        if let prompt = preview.prompt, !prompt.isEmpty {
                            Text(prompt)
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PlainButtonStyle())

                SearchResultsMapView(
                    searchResults: preview.results,
                    currentLocation: sharedLocationManager.currentLocation,
                    onResultTap: { result in
                        onOpenPlace(result)
                    }
                )

                if preview.results.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Other Nearby Matches")
                            .font(FontManager.geist(size: 11, weight: .semibold))
                            .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.55))
                            .textCase(.uppercase)
                            .tracking(0.5)

                        ForEach(Array(preview.results.dropFirst().prefix(3)), id: \.id) { result in
                            Button(action: {
                                onOpenPlace(result)
                            }) {
                                Text(result.address)
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.68))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                if let folderName, !folderName.isEmpty {
                    Text("Folder: \(folderName)")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.62))
                }

                if showSaveActions && status == .pending {
                    actionButtons(confirmLabel: "Confirm Save") {
                        if let folderName, !folderName.isEmpty {
                            onConfirmSave(folderName)
                        } else {
                            selectedCategory = preferredStartingCategory
                            showingCategoryPicker = true
                        }
                    } onCancel: {
                        onCancel()
                    }
                }
            }
        }
        .actionCardSurface(colorScheme: colorScheme)
        .sheet(isPresented: $showingCategoryPicker) {
            CategoryPickerView(
                selectedCategory: $selectedCategory,
                onSave: { category in
                    onConfirmSave(category)
                }
            )
            .presentationBg()
        }
    }

    private var preferredStartingCategory: String {
        locationsManager.categories.first ??
        Array(locationsManager.userFolders).sorted().first ??
        "Restaurants"
    }
}

private func headerRow(title: String, status: AgentActionDraftStatus?) -> some View {
    HStack {
        Text(title)
            .font(FontManager.geist(size: 12, weight: .semibold))
            .foregroundColor(.primary.opacity(0.58))
            .textCase(.uppercase)
            .tracking(0.7)

        Spacer()

        if let status {
            ActionDraftStatusChip(status: status)
        }
    }
}

private func actionButtons(
    confirmLabel: String,
    onConfirm: @escaping () -> Void,
    onCancel: @escaping () -> Void
) -> some View {
    HStack(spacing: 10) {
        Button(action: onCancel) {
            Text("Cancel")
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.72))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PlainButtonStyle())

        Button(action: onConfirm) {
            Text(confirmLabel)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct ActionDraftStatusChip: View {
    let status: AgentActionDraftStatus
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(label)
            .font(FontManager.geist(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .cancelled: return "Cancelled"
        }
    }

    private var color: Color {
        switch status {
        case .pending: return .orange
        case .confirmed: return .green
        case .cancelled: return .gray
        }
    }
}

private extension View {
    func actionCardSurface(colorScheme: ColorScheme) -> some View {
        self
            .padding(14)
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
