import SwiftUI

struct ReceiptStatsView: View {
    @StateObject private var notesManager = NotesManager.shared
    @State private var currentYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedNote: Note? = nil
    @Environment(\.colorScheme) var colorScheme

    var availableYears: [Int] {
        notesManager.getAvailableReceiptYears()
    }

    var currentYearStats: YearlyReceiptSummary? {
        notesManager.getReceiptStatistics(year: currentYear).first
    }

    var body: some View {
        ZStack {
            // Background
            (colorScheme == .dark ? Color.black : Color(UIColor(white: 0.99, alpha: 1)))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Main card container
                VStack(spacing: 0) {
                    // Year selector header with total
                    HStack(spacing: 12) {
                        if !availableYears.isEmpty && currentYear != availableYears.min() {
                            Button(action: { selectPreviousYear() }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 32, height: 32)
                            }
                        } else {
                            // Placeholder to maintain spacing
                            Color.clear
                                .frame(width: 32, height: 32)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%d", currentYear))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.primary)

                            if let stats = currentYearStats {
                                Text(CurrencyParser.formatAmount(stats.yearlyTotal))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        }

                        Spacer()

                        if !availableYears.isEmpty && currentYear != availableYears.max() {
                            Button(action: { selectNextYear() }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 32, height: 32)
                            }
                        } else {
                            // Placeholder to maintain spacing
                            Color.clear
                                .frame(width: 32, height: 32)
                        }
                    }
                    .padding(16)

                    Divider()
                        .opacity(0.3)

                    // Monthly breakdown
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            if let stats = currentYearStats {
                                if stats.monthlySummaries.isEmpty {
                                    VStack(spacing: 8) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 32, weight: .light))
                                            .foregroundColor(.gray)

                                        Text("No receipts found")
                                            .font(.system(.body, design: .default))
                                            .foregroundColor(.gray)

                                        Text("for this year")
                                            .font(.system(.caption, design: .default))
                                            .foregroundColor(.gray)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                                } else {
                                    ForEach(Array(stats.monthlySummaries.enumerated()), id: \.element.id) { index, monthlySummary in
                                        MonthlySummaryReceiptCard(
                                            monthlySummary: monthlySummary,
                                            isLast: index == stats.monthlySummaries.count - 1,
                                            onReceiptTap: { noteId in
                                                selectedNote = notesManager.notes.first { $0.id == noteId }
                                            }
                                        )

                                        if index < stats.monthlySummaries.count - 1 {
                                            Divider()
                                                .opacity(0.3)
                                        }
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text")
                                        .font(.system(size: 32, weight: .light))
                                        .foregroundColor(.gray)

                                    Text("No receipts found")
                                        .font(.system(.body, design: .default))
                                        .foregroundColor(.gray)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                        }
                    }
                }
                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .cornerRadius(12)
                .padding(12)
            }
        }
        .onAppear {
            // Set current year to the most recent year with data
            if !availableYears.isEmpty {
                currentYear = availableYears.first ?? Calendar.current.component(.year, from: Date())
            }
        }
        .sheet(item: $selectedNote) { note in
            NavigationView {
                NoteEditView(note: note, isPresented: Binding<Bool>(
                    get: { selectedNote != nil },
                    set: { if !$0 { selectedNote = nil } }
                ))
            }
        }
    }

    private func selectPreviousYear() {
        if let previousYear = availableYears.first(where: { $0 < currentYear }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentYear = previousYear
            }
        }
    }

    private func selectNextYear() {
        if let nextYear = availableYears.first(where: { $0 > currentYear }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentYear = nextYear
            }
        }
    }
}

#Preview {
    ReceiptStatsView()
}
