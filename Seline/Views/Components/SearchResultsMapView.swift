import SwiftUI
import MapKit

/// A mini map view that displays search results as red pin annotations
struct SearchResultsMapView: View {
    let searchResults: [PlaceSearchResult]
    let currentLocation: CLLocation?
    let onResultTap: (PlaceSearchResult) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    var body: some View {
        mapContent
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 8, x: 0, y: 2)
            .onAppear {
                updateRegionToFitResults()
            }
            .onChange(of: searchResults.count) { _ in
                updateRegionToFitResults()
            }
    }
    
    private var mapContent: some View {
        Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: searchResults) { result in
            MapAnnotation(coordinate: CLLocationCoordinate2D(
                latitude: result.latitude,
                longitude: result.longitude
            )) {
                pinView(for: result)
            }
        }
    }
    
    private func pinView(for result: PlaceSearchResult) -> some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 14, height: 14)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 14, height: 14)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onResultTap(result)
        }
    }
    
    private func updateRegionToFitResults() {
        // Filter results that have valid coordinates
        let validResults = searchResults.filter { result in
            return result.latitude != 0 && result.longitude != 0
        }
        
        guard !validResults.isEmpty else {
            // If no valid results, center on current location
            if let currentLoc = currentLocation {
                region = MKCoordinateRegion(
                    center: currentLoc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
            return
        }
        
        // Calculate bounding box for all results
        var minLat = validResults[0].latitude
        var maxLat = validResults[0].latitude
        var minLon = validResults[0].longitude
        var maxLon = validResults[0].longitude
        
        for result in validResults {
            minLat = min(minLat, result.latitude)
            maxLat = max(maxLat, result.latitude)
            minLon = min(minLon, result.longitude)
            maxLon = max(maxLon, result.longitude)
        }
        
        // Include current location in the region if available
        if let currentLoc = currentLocation {
            minLat = min(minLat, currentLoc.coordinate.latitude)
            maxLat = max(maxLat, currentLoc.coordinate.latitude)
            minLon = min(minLon, currentLoc.coordinate.longitude)
            maxLon = max(maxLon, currentLoc.coordinate.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        // Add padding to the span
        let latDelta = max(maxLat - minLat, 0.01) * 1.5
        let lonDelta = max(maxLon - minLon, 0.01) * 1.5
        
        let span = MKCoordinateSpan(
            latitudeDelta: latDelta,
            longitudeDelta: lonDelta
        )
        
        withAnimation(.easeInOut(duration: 0.3)) {
            region = MKCoordinateRegion(center: center, span: span)
        }
    }
}

#Preview {
    SearchResultsMapView(
        searchResults: [],
        currentLocation: nil,
        onResultTap: { _ in }
    )
    .padding()
}
