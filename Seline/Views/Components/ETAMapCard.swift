import SwiftUI
import MapKit

// MARK: - ETA Map Card for Chat
/// A tappable map card that shows route/destination for ETA queries

struct ETAMapCard: View {
    let locationInfo: ETALocationInfo
    @Environment(\.colorScheme) var colorScheme
    @State private var showingActionSheet = false
    
    var body: some View {
        Button(action: {
            HapticManager.shared.selection()
            showingActionSheet = true
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Mini Map Preview
                MapPreviewView(
                    originCoord: originCoordinate,
                    destinationCoord: destinationCoordinate
                )
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                
                // Route Info Bar
                HStack(spacing: 12) {
                    // ETA Info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                            
                            if let driveTime = locationInfo.driveTime {
                                Text(driveTime)
                                    .font(FontManager.geist(size: 14, weight: .semibold))
                                    .foregroundColor(Color.shadcnForeground(colorScheme))
                            }
                            
                            if let distance = locationInfo.distance {
                                Text("• \(distance)")
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.6))
                            }
                        }
                        
                        Text(routeDescription)
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.5))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // Open in Maps button
                    HStack(spacing: 4) {
                        Text("Get Directions")
                            .font(FontManager.geist(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                    }

                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colorScheme == .dark ? Color.white.opacity(0.15) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
            }
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.05))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Open Directions", isPresented: $showingActionSheet) {
            Button("Apple Maps") {
                locationInfo.openInMaps(preferGoogleMaps: false)
            }
            Button("Google Maps") {
                locationInfo.openInMaps(preferGoogleMaps: true)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private var originCoordinate: CLLocationCoordinate2D? {
        guard let lat = locationInfo.originLatitude,
              let lon = locationInfo.originLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    private var destinationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: locationInfo.destinationLatitude,
            longitude: locationInfo.destinationLongitude
        )
    }
    
    private var routeDescription: String {
        if let originName = locationInfo.originName {
            return "\(originName) → \(locationInfo.destinationName)"
        } else {
            return "To \(locationInfo.destinationName)"
        }
    }
}

// MARK: - Map Preview using MapKit

struct MapPreviewView: UIViewRepresentable {
    let originCoord: CLLocationCoordinate2D?
    let destinationCoord: CLLocationCoordinate2D
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.isUserInteractionEnabled = false
        mapView.showsUserLocation = false
        mapView.mapType = .standard // Ensure standard view (not satellite)
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Clear existing annotations and overlays
        mapView.removeAnnotations(mapView.annotations)
        mapView.removeOverlays(mapView.overlays)
        
        // Add destination pin
        let destAnnotation = MKPointAnnotation()
        destAnnotation.coordinate = destinationCoord
        destAnnotation.title = "Destination"
        mapView.addAnnotation(destAnnotation)
        
        // Add origin pin if available
        if let origin = originCoord {
            let originAnnotation = MKPointAnnotation()
            originAnnotation.coordinate = origin
            originAnnotation.title = "Start"
            mapView.addAnnotation(originAnnotation)
            
            // Calculate and show route
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destinationCoord))
            request.transportType = .automobile
            
            let directions = MKDirections(request: request)
            directions.calculate { response, error in
                guard let route = response?.routes.first else { return }
                mapView.addOverlay(route.polyline)
                
                // Fit both points with padding
                let rect = route.polyline.boundingMapRect
                let padding = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
                mapView.setVisibleMapRect(rect, edgePadding: padding, animated: false)
            }
        } else {
            // Just show destination
            let region = MKCoordinateRegion(
                center: destinationCoord,
                latitudinalMeters: 2000,
                longitudinalMeters: 2000
            )
            mapView.setRegion(region, animated: false)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .black
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            
            let identifier = "marker"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            } else {
                view?.annotation = annotation
            }
            
            if annotation.title == "Start" {
                view?.markerTintColor = .darkGray
                view?.glyphImage = UIImage(systemName: "car.fill")
                view?.glyphTintColor = .white
            } else {
                view?.markerTintColor = .black
                view?.glyphImage = UIImage(systemName: "mappin")
                view?.glyphTintColor = .white
            }
            
            return view
        }
    }
}

#Preview {
    VStack {
        ETAMapCard(locationInfo: ETALocationInfo(
            originName: "Airbnb",
            originAddress: "2601 Apricot Ln, Pickering",
            originLatitude: 43.8384,
            originLongitude: -79.0868,
            destinationName: "Lakeridge Ski Resort",
            destinationAddress: "1500 Lakeridge Rd, Uxbridge",
            destinationLatitude: 44.0504,
            destinationLongitude: -79.0697,
            driveTime: "45 min",
            distance: "38 km"
        ))
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}
