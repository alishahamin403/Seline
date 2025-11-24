import SwiftUI

struct AllVisitsSheet: View {
    @Binding var allLocations: [(id: UUID, displayName: String, visitCount: Int)]
    @Binding var isPresented: Bool
    let onLocationTap: ((UUID) -> Void)?
    var savedPlaces: [SavedPlace] = []
    @Environment(\.colorScheme) var colorScheme

    private var visitedLocations: [(id: UUID, displayName: String, visitCount: Int)] {
        allLocations.filter { $0.visitCount > 0 }
    }

    private func iconForLocation(_ locationId: UUID, _ displayName: String) -> String {
        // First check if this location is saved and has a user-selected icon
        if let savedPlace = savedPlaces.first(where: { $0.id == locationId }) {
            return savedPlace.getDisplayIcon()
        }

        // Otherwise, auto-detect based on location name (matching SavedPlace.getDisplayIcon logic)
        let lowerName = displayName.lowercased()

        if lowerName.contains("home") {
            return "house.fill"
        } else if lowerName.contains("work") || lowerName.contains("office") || lowerName.contains("briefcase") {
            return "briefcase.fill"
        } else if lowerName.contains("gym") || lowerName.contains("fitness") {
            return "dumbbell.fill"
        } else if lowerName.contains("pizza") {
            return "pizza"
        } else if lowerName.contains("burger") || lowerName.contains("hamburger") {
            return "hamburger"
        } else if lowerName.contains("pasta") {
            return "fork.knife.circle.fill"
        } else if lowerName.contains("shawarma") || lowerName.contains("kebab") {
            return "burrito"
        } else if lowerName.contains("jamaican") || lowerName.contains("reggae") {
            return "chef.hat"
        } else if lowerName.contains("steak") || lowerName.contains("barbecue") || lowerName.contains("bbq") {
            return "steak"
        } else if lowerName.contains("mexican") || lowerName.contains("taco") {
            return "sun.max.fill"
        } else if lowerName.contains("chinese") {
            return "chopsticks"
        } else if lowerName.contains("haircut") || lowerName.contains("barber") || lowerName.contains("salon") {
            return "scissors"
        } else if lowerName.contains("dental") || lowerName.contains("dentist") {
            return "tooth.fill"
        } else if lowerName.contains("hotel") || lowerName.contains("motel") {
            return "building.fill"
        } else if lowerName.contains("mosque") {
            return "building.2.fill"
        } else if lowerName.contains("smoke") || lowerName.contains("hookah") || lowerName.contains("shisha") {
            return "flame.fill"
        } else if lowerName.contains("restaurant") || lowerName.contains("diner") || lowerName.contains("cafe") || lowerName.contains("food") {
            return "fork.knife"
        } else if lowerName.contains("park") || lowerName.contains("outdoor") {
            return "tree.fill"
        } else if lowerName.contains("hospital") || lowerName.contains("clinic") || lowerName.contains("medical") {
            return "heart.fill"
        } else if lowerName.contains("shop") || lowerName.contains("store") || lowerName.contains("mall") {
            return "bag.fill"
        } else if lowerName.contains("school") || lowerName.contains("university") {
            return "book.fill"
        } else {
            return "mappin.circle.fill"
        }
    }

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

                // List of all locations
                if visitedLocations.isEmpty {
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
                            ForEach(Array(visitedLocations.enumerated()), id: \.element.id) { index, location in
                                Button(action: {
                                    onLocationTap?(location.id)
                                    isPresented = false
                                }) {
                                    VStack(spacing: 0) {
                                        HStack(spacing: 12) {
                                            // Location icon badge
                                            ZStack {
                                                Circle()
                                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))

                                                Image(systemName: iconForLocation(location.id, location.displayName))
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.25))
                                            }
                                            .frame(width: 40, height: 40)

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
