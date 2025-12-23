import SwiftUI

struct CurrentLocationCardWidget: View {
    @Environment(\.colorScheme) var colorScheme

    let currentLocationName: String
    let nearbyLocation: String?
    let nearbyLocationFolder: String?
    let nearbyLocationPlace: SavedPlace?
    let distanceToNearest: Double?
    let elapsedTimeString: String
    let todaysVisits: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)]

    @Binding var selectedPlace: SavedPlace?
    @Binding var showAllLocationsSheet: Bool

    // Modern color scheme helpers
    private var cardBackground: Color {
        Color.shadcnTileBackground(colorScheme)
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark 
            ? Color.white.opacity(0.65)
            : Color.black.opacity(0.65)
    }
    
    private var tertiaryTextColor: Color {
        colorScheme == .dark 
            ? Color.white.opacity(0.45)
            : Color.black.opacity(0.45)
    }
    
    private var activeIndicatorColor: Color {
        Color.green.opacity(0.85)
    }
    
    private var cardShadow: Color {
        colorScheme == .dark 
            ? Color.clear
            : Color.black.opacity(0.04)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Primary Location Section
            Button(action: {
                if let place = nearbyLocationPlace {
                    selectedPlace = place
                }
            }) {
                HStack(spacing: 16) {
                    // Location Icon/Indicator
                    ZStack {
                        Circle()
                            .fill(activeIndicatorColor.opacity(0.15))
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: "location.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(activeIndicatorColor)
                    }
                    
                    // Location Info
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentLocationName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        // Status indicator - more subtle
                        statusIndicatorView
                    }
                    
                    Spacer()
                    
                    // Chevron indicator
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(tertiaryTextColor)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(PlainButtonStyle())
            .allowsParentScrolling()
            
            // Today's Visits Section - Collapsible
            if !todaysVisits.isEmpty {
                Divider()
                    .padding(.vertical, 10)
                    .opacity(0.3)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Today")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(secondaryTextColor)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        Spacer()
                        
                        Button(action: {
                            showAllLocationsSheet = true
                        }) {
                            Text("See All")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(todaysVisits.prefix(3), id: \.id) { visit in
                            visitRowView(visit: visit)
                        }
                    }
                }
            }
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
        .shadow(
            color: cardShadow,
            radius: 20,
            x: 0,
            y: 4
        )
    }
    
    // MARK: - Status Indicator View
    @ViewBuilder
    private var statusIndicatorView: some View {
        if let nearby = nearbyLocation {
            HStack(spacing: 6) {
                // Subtle active indicator
                Circle()
                    .fill(activeIndicatorColor)
                    .frame(width: 5, height: 5)
                
                Text(elapsedTimeString.isEmpty ? "Just arrived" : elapsedTimeString)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(secondaryTextColor)
            }
        } else if let distance = distanceToNearest {
            HStack(spacing: 4) {
                Image(systemName: "location")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tertiaryTextColor)
                
                Text(String(format: "%.1f km away", distance / 1000))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(tertiaryTextColor)
            }
        } else {
            Text("No saved locations nearby")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(tertiaryTextColor)
        }
    }
    
    // MARK: - Visit Row View
    private func visitRowView(visit: (id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)) -> some View {
        HStack(spacing: 10) {
            Text(visit.displayName)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
            
            Spacer()
            
            Text(formatDuration(visit.totalDurationMinutes))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(visit.isActive ? activeIndicatorColor : secondaryTextColor)
        }
        .padding(.vertical, 2)
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }
}
