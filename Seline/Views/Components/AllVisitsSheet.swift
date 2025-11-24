import SwiftUI

struct AllVisitsSheet: View {
    @Binding var allLocations: [(id: UUID, displayName: String, visitCount: Int)]
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("All Visits")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(colorScheme == .dark ? Color.black : Color.white)

                Divider()

                // List of all locations
                if allLocations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "map.circle")
                            .font(.system(size: 48))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))

                        Text("No visits yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text("Start exploring to see your visited places here")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(allLocations.enumerated()), id: \.element.id) { index, location in
                                VStack(spacing: 0) {
                                    HStack(spacing: 12) {
                                        // Rank badge
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    index == 0 ? Color(red: 1.0, green: 0.84, blue: 0) :
                                                    index == 1 ? Color(red: 0.7, green: 0.7, blue: 0.7) :
                                                    index == 2 ? Color(red: 0.8, green: 0.5, blue: 0.2) :
                                                    Color(red: 0.2039, green: 0.6588, blue: 0.3255)
                                                )

                                            Text("\(index + 1)")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                        .frame(width: 32, height: 32)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(location.displayName)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                                .lineLimit(2)

                                            Text("\(location.visitCount) visit\(location.visitCount == 1 ? "" : "s")")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)

                                    if index < allLocations.count - 1 {
                                        Divider()
                                            .padding(.horizontal, 16)
                                    }
                                }
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
        isPresented: .constant(true)
    )
}
