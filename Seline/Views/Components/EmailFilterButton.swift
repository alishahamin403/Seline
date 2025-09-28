import SwiftUI

struct EmailFilterButton: View {
    @StateObject private var filterManager = EmailFilterManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingFilterSheet = false

    let onFiltersChanged: () -> Void

    private var isFiltersActive: Bool {
        filterManager.getEnabledCategoriesCount() < EmailCategory.allCases.count
    }

    var body: some View {
        Button(action: {
            showingFilterSheet = true
        }) {
            ZStack {
                // Background circle
                Circle()
                    .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 40, height: 40)

                // Filter icon
                Image(systemName: isFiltersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(isFiltersActive ?
                        (colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40)) :
                        Color.gray
                    )

                // Active indicator
                if isFiltersActive {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: -2, y: 2)
                        }
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingFilterSheet) {
            EmailFilterSheet(onFiltersChanged: onFiltersChanged)
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        EmailFilterButton(onFiltersChanged: {})

        EmailFilterButton(onFiltersChanged: {})
            .onAppear {
                // Simulate active filters for preview
                EmailFilterManager.shared.toggleCategory(.promotional)
            }
    }
    .padding()
}