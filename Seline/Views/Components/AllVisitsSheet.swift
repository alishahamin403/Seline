import SwiftUI

struct AllVisitsSheet: View {
    @Binding var allLocations: [(id: UUID, displayName: String, visitCount: Int)]
    @Binding var isPresented: Bool
    let onLocationTap: ((UUID) -> Void)?
    var savedPlaces: [SavedPlace] = []
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    private var visitedLocations: [(id: UUID, displayName: String, visitCount: Int)] {
        allLocations.filter { $0.visitCount > 0 }
    }


    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("All Visits")
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Spacer()

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(FontManager.geist(size: 18, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(colorScheme == .dark ? Color.black : Color.white)

                // List of all locations
                if visitedLocations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "map.circle")
                            .font(FontManager.geist(size: 48, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))

                        Text("No visits yet")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text("Start exploring to see your visited places here")
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visitedLocations.enumerated()), id: \.element.id) { index, location in
                                Button(action: {
                                    onLocationTap?(location.id)
                                    isPresented = false
                                }) {
                                    VStack(spacing: 0) {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(location.displayName)
                                                    .font(FontManager.geist(size: 14, weight: .medium))
                                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                                    .lineLimit(2)

                                                Text("\(location.visitCount) visit\(location.visitCount == 1 ? "" : "s")")
                                                    .font(FontManager.geist(size: 12, weight: .regular))
                                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(FontManager.geist(size: 12, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }

                Spacer()
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationBarHidden(true)
        }
    }
}

#Preview {
    AllVisitsSheet(
        allLocations: .constant([
            (id: UUID(), displayName: "Coffee Shop Downtown", visitCount: 24),
            (id: UUID(), displayName: "Gym - Main Street", visitCount: 18),
            (id: UUID(), displayName: "Office Building", visitCount: 16),
            (id: UUID(), displayName: "Park Near Home", visitCount: 12),
            (id: UUID(), displayName: "Restaurant District", visitCount: 8)
        ]),
        isPresented: .constant(true),
        onLocationTap: nil
    )
}
