import SwiftUI

struct GmailLabelSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var viewModel = GmailLabelSelectionViewModel()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Gmail Labels")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Choose which labels you want to sync to Seline as folders")
                            .font(.system(size: 13))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.98, green: 0.98, blue: 0.98))

                    // Labels List
                    if viewModel.isLoading {
                        VStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.2)
                            Spacer()
                        }
                    } else if viewModel.availableLabels.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "envelope")
                                .font(.system(size: 40))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.gray)
                            Text("No Labels Found")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            Text("You don't have any custom labels in Gmail")
                                .font(.system(size: 13))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                // Select All / Deselect All
                                HStack(spacing: 12) {
                                    Button(action: { viewModel.selectAll() }) {
                                        Label("All", systemImage: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(.blue)

                                    Button(action: { viewModel.deselectAll() }) {
                                        Label("None", systemImage: "circle")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(.gray)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)

                                // Labels
                                ForEach(viewModel.availableLabels) { label in
                                    HStack(spacing: 12) {
                                        // Color circle for Gmail label
                                        Circle()
                                            .fill(Color(hex: label.color?.backgroundColor ?? "#84cae9") ?? Color.blue)
                                            .frame(width: 24, height: 24)

                                        // Label name
                                        Text(label.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)

                                        Spacer()

                                        // Checkbox
                                        Image(systemName: viewModel.isLabelSelected(label.id) ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ?
                                                Color.white.opacity(0.08) :
                                                Color.black.opacity(0.04)
                                            )
                                    )
                                    .onTapGesture {
                                        viewModel.toggleLabel(label.id)
                                    }
                                }

                                Spacer(minLength: 20)
                            }
                            .padding(16)
                        }
                    }

                    // Footer - Action Buttons
                    VStack(spacing: 12) {
                        Button(action: { viewModel.importSelectedLabels() }) {
                            HStack {
                                if viewModel.isImporting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.down.doc")
                                }
                                Text(viewModel.isImporting ? "Importing..." : "Import Selected Labels")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(viewModel.selectedLabelIds.isEmpty || viewModel.isImporting)

                        Button(action: {
                            authManager.showLabelSelection = false
                            dismiss()
                        }) {
                            Text("Skip for Now")
                                .font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ?
                                            Color.white.opacity(0.1) :
                                            Color.black.opacity(0.08)
                                        )
                                )
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                    .padding(16)
                    .background(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.98, green: 0.98, blue: 0.98))
                }
            }
            .navigationBarBackButtonHidden(true)
            .alert("Import Complete", isPresented: $viewModel.showImportSuccess) {
                Button("Done", action: {
                    authManager.showLabelSelection = false
                    dismiss()
                })
            } message: {
                Text("Successfully imported \(viewModel.importedCount) label(s)")
            }
        }
        .onAppear {
            viewModel.fetchAvailableLabels()
        }
    }
}

// MARK: - View Model

@MainActor
class GmailLabelSelectionViewModel: ObservableObject {
    @Published var availableLabels: [GmailLabel] = []
    @Published var selectedLabelIds: Set<String> = []
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var showImportSuccess = false
    @Published var importedCount = 0

    private let gmailLabelService = GmailLabelService.shared
    private let labelSyncService = LabelSyncService.shared

    func fetchAvailableLabels() {
        isLoading = true
        Task {
            do {
                print("📋 Fetching available Gmail labels...")
                let labels = try await gmailLabelService.fetchAllCustomLabels()
                self.availableLabels = labels.sorted { $0.name < $1.name }
                print("✅ Fetched \(labels.count) labels")
                self.isLoading = false
            } catch {
                print("❌ Error fetching labels: \(error)")
                self.isLoading = false
            }
        }
    }

    func isLabelSelected(_ labelId: String) -> Bool {
        selectedLabelIds.contains(labelId)
    }

    func toggleLabel(_ labelId: String) {
        if selectedLabelIds.contains(labelId) {
            selectedLabelIds.remove(labelId)
        } else {
            selectedLabelIds.insert(labelId)
        }
    }

    func selectAll() {
        selectedLabelIds = Set(availableLabels.map { $0.id })
    }

    func deselectAll() {
        selectedLabelIds.removeAll()
    }

    func importSelectedLabels() {
        isImporting = true
        Task {
            do {
                print("📥 Importing \(selectedLabelIds.count) selected labels...")
                let selectedLabels = availableLabels.filter { selectedLabelIds.contains($0.id) }

                // Import each selected label
                for (index, label) in selectedLabels.enumerated() {
                    print("➡️ Importing label \(index + 1)/\(selectedLabels.count): '\(label.name)'")
                    try await labelSyncService.importLabel(label, progress: (index + 1, selectedLabels.count))
                }

                self.importedCount = selectedLabels.count
                self.isImporting = false
                self.showImportSuccess = true
                print("✅ Successfully imported \(selectedLabels.count) labels")
            } catch {
                print("❌ Error importing labels: \(error)")
                self.isImporting = false
            }
        }
    }
}

#Preview {
    GmailLabelSelectionView()
}
