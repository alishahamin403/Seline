import SwiftUI
import CoreLocation

struct WeatherWidget: View {
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var navigationService = NavigationService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase // Track app lifecycle

    var isVisible: Bool = true // Controls whether to fetch data

    @State private var currentTime = Date()
    @State private var locationPreferences: UserLocationPreferences?
    @State private var timer: Timer? // Manual timer that we can start/stop
    @State private var lastWeatherFetch: Date? // Track last fetch

    private var currentWeather: WeatherData? {
        weatherService.weatherData
    }

    private var sunrise: Date {
        currentWeather?.sunrise ?? Date()
    }

    private var sunset: Date {
        currentWeather?.sunset ?? Date()
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }


    @State private var showLocationSetup = false
    @State private var setupLocationSlot: LocationSlot?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                // Weather Card (60%)
                weatherCardButton(width: (geometry.size.width - 8) * 0.6)

            // Navigation Card (40%)
            VStack(spacing: 0) {
                // Location 1 ETA
                NavigationETARow(
                    icon: locationPreferences?.location1Icon ?? "house.fill",
                    eta: navigationService.location1ETA,
                    isLocationSet: locationPreferences?.location1Coordinate != nil,
                    isLoading: navigationService.isLoading,
                    colorScheme: colorScheme,
                    onTap: {
                        if locationPreferences?.location1Coordinate != nil {
                            openNavigation(to: locationPreferences?.location1Coordinate, address: locationPreferences?.location1Address)
                        } else {
                            setupLocationSlot = .location1
                            showLocationSetup = true
                        }
                    },
                    onLongPress: {
                        setupLocationSlot = .location1
                        showLocationSetup = true
                    }
                )

                // Location 2 ETA
                NavigationETARow(
                    icon: locationPreferences?.location2Icon ?? "briefcase.fill",
                    eta: navigationService.location2ETA,
                    isLocationSet: locationPreferences?.location2Coordinate != nil,
                    isLoading: navigationService.isLoading,
                    colorScheme: colorScheme,
                    onTap: {
                        if locationPreferences?.location2Coordinate != nil {
                            openNavigation(to: locationPreferences?.location2Coordinate, address: locationPreferences?.location2Address)
                        } else {
                            setupLocationSlot = .location2
                            showLocationSetup = true
                        }
                    },
                    onLongPress: {
                        setupLocationSlot = .location2
                        showLocationSetup = true
                    }
                )

                // Location 3 ETA
                NavigationETARow(
                    icon: locationPreferences?.location3Icon ?? "fork.knife",
                    eta: navigationService.location3ETA,
                    isLocationSet: locationPreferences?.location3Coordinate != nil,
                    isLoading: navigationService.isLoading,
                    colorScheme: colorScheme,
                    onTap: {
                        if locationPreferences?.location3Coordinate != nil {
                            openNavigation(to: locationPreferences?.location3Coordinate, address: locationPreferences?.location3Address)
                        } else {
                            setupLocationSlot = .location3
                            showLocationSetup = true
                        }
                    },
                    onLongPress: {
                        setupLocationSlot = .location3
                        showLocationSetup = true
                    }
                )

                // Location 4 ETA
                NavigationETARow(
                    icon: locationPreferences?.location4Icon ?? "plus.circle.fill",
                    eta: navigationService.location4ETA,
                    isLocationSet: locationPreferences?.location4Coordinate != nil,
                    isLoading: navigationService.isLoading,
                    colorScheme: colorScheme,
                    onTap: {
                        if locationPreferences?.location4Coordinate != nil {
                            openNavigation(to: locationPreferences?.location4Coordinate, address: locationPreferences?.location4Address)
                        } else {
                            setupLocationSlot = .location4
                            showLocationSetup = true
                        }
                    },
                    onLongPress: {
                        setupLocationSlot = .location4
                        showLocationSetup = true
                    }
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: (geometry.size.width - 8) * 0.4, alignment: .leading)
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            .cornerRadius(12)
            }
            .frame(height: 120)
        }
        .frame(height: 120)
        .padding(.horizontal, 12)
        .sheet(isPresented: $showLocationSetup) {
            LocationEditView(
                locationSlot: setupLocationSlot ?? .location1,
                currentPreferences: locationPreferences,
                onSave: { updatedPreferences in
                    Task {
                        do {
                            try await supabaseManager.saveLocationPreferences(updatedPreferences)
                            locationPreferences = updatedPreferences
                            updateETAs()
                        } catch {
                            print("❌ Failed to save location: \(error)")
                        }
                    }
                }
            )
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // App became active - only refresh if needed, NO automatic timer
                refreshWeatherIfNeeded()
            case .background, .inactive:
                // App went to background - stop timer
                stopWeatherTimer()
            @unknown default:
                break
            }
        }
        .onAppear {
            // NO automatic timer - only manual refresh on appearance
            // Only fetch if visible
            guard isVisible else { return }

            locationService.requestLocationPermission()
            loadLocationPreferences()

            // If we already have a location, fetch weather immediately on appearance
            if let location = locationService.currentLocation {
                Task {
                    await weatherService.fetchWeather(for: location)
                }
            }
        }
        .onChange(of: isVisible) { visible in
            if visible {
                // When becoming visible, start location updates and fetch data
                locationService.requestLocationPermission()
                loadLocationPreferences()

                if let location = locationService.currentLocation {
                    Task {
                        await weatherService.fetchWeather(for: location)
                    }
                }
                // Update ETAs when becoming visible
                updateETAs()

                // Save ETAs to widget so it displays current values
                navigationService.saveETAsToWidget()
            } else {
                // When becoming invisible, stop location updates
                locationService.stopLocationUpdates()
            }
        }
        .onChange(of: locationService.currentLocation) { location in
            // Only update if visible
            guard isVisible else { return }

            if let location = location {
                Task {
                    await weatherService.fetchWeather(for: location)
                    // Update ETAs when current location changes
                    updateETAs()
                }
            }
        }
        .onChange(of: locationPreferences) { _ in
            // Update ETAs when location preferences change
            updateETAs()
        }
    }

    // MARK: - Computed Properties

    private var weatherConditionIcon: Image {
        let description = weatherService.weatherData?.description.lowercased() ?? ""

        // Check for specific weather conditions
        if description.contains("rain") || description.contains("drizzle") {
            return Image(systemName: "cloud.rain.fill")
        } else if description.contains("snow") {
            return Image(systemName: "cloud.snow.fill")
        } else if description.contains("cloud") {
            return Image(systemName: "cloud.fill")
        } else if description.contains("clear") || description.contains("sun") {
            return Image(systemName: "sun.max.fill")
        } else if description.contains("thunder") || description.contains("storm") {
            return Image(systemName: "cloud.bolt.fill")
        } else if description.contains("fog") || description.contains("mist") {
            return Image(systemName: "cloud.fog.fill")
        } else {
            return Image(systemName: "sun.max.fill")
        }
    }

    // MARK: - View Components

    private func weatherCardButton(width: CGFloat) -> some View {
        Button(action: {
            openWeatherApp()
        }) {
            VStack(alignment: .center, spacing: 4) {
                // Row 1: Location | Temperature | Weather Icon
                HStack(spacing: 6) {
                    // Location text
                    Text(weatherService.weatherData?.locationName ?? locationService.locationName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // Separator
                    Text("|")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))

                    // Temperature - regular weight
                    if let temperature = weatherService.weatherData?.temperature {
                        Text("\(temperature)°")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    } else {
                        Text("--°")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    }

                    // Weather condition icon
                    weatherConditionIcon
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                }

                // Row 2: Sunrise and Sunset
                HStack(spacing: 16) {
                    // Sunrise - yellow icon
                    HStack(spacing: 4) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        Text(formatTime(sunrise))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }

                    // Sunset - yellow icon
                    HStack(spacing: 4) {
                        Image(systemName: "sunset.fill")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        Text(formatTime(sunset))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                }

                // Row 3: 6-Day Forecast
                HStack(spacing: 0) {
                    ForEach(weatherService.weatherData?.dailyForecasts ?? [], id: \.day) { forecast in
                        VStack(spacing: 2) {
                            Image(systemName: forecast.iconName)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .frame(height: 12)

                            Text("\(forecast.temperature)°")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                .frame(height: 12)

                            Text(forecast.day)
                                .font(.system(size: 8, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                .frame(height: 10)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: width, height: 120, alignment: .center)
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Methods

    private func loadLocationPreferences() {
        Task {
            do {
                let preferences = try await supabaseManager.loadLocationPreferences()
                await MainActor.run {
                    self.locationPreferences = preferences
                }
                updateETAs()
            } catch {
                print("❌ Failed to load location preferences: \(error)")
            }
        }
    }

    private func updateETAs() {
        guard let preferences = locationPreferences else {
            print("⚠️ Location preferences not loaded yet")
            return
        }

        // If we don't have current location yet, try to request it
        if locationService.currentLocation == nil {
            print("⚠️ Current location not available, requesting...")
            locationService.requestLocationPermission()

            // Try again after a short delay to allow location to be fetched
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                if let currentLocation = locationService.currentLocation {
                    await navigationService.updateETAs(
                        currentLocation: currentLocation,
                        location1: preferences.location1Coordinate,
                        location2: preferences.location2Coordinate,
                        location3: preferences.location3Coordinate,
                        location4: preferences.location4Coordinate
                    )

                    // Save ETAs to widget after calculation completes
                    navigationService.saveETAsToWidget()
                }
            }
            return
        }

        guard let currentLocation = locationService.currentLocation else {
            return
        }

        Task {
            await navigationService.updateETAs(
                currentLocation: currentLocation,
                location1: preferences.location1Coordinate,
                location2: preferences.location2Coordinate,
                location3: preferences.location3Coordinate,
                location4: preferences.location4Coordinate
            )

            // Save ETAs to widget after calculation completes
            navigationService.saveETAsToWidget()
        }
    }

    private func openWeatherApp() {
        // Open the native Weather app
        if let weatherURL = URL(string: "weather://") {
            if UIApplication.shared.canOpenURL(weatherURL) {
                UIApplication.shared.open(weatherURL)
                print("✅ Opened Weather app")
            }
        }
    }

    private func openNavigation(to coordinate: CLLocationCoordinate2D?, address: String?) {
        guard let coordinate = coordinate else {
            print("⚠️ No destination coordinate available")
            return
        }

        // Try Google Maps app first with driving directions
        let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(coordinate.latitude),\(coordinate.longitude)&directionsmode=driving")

        if let googleMapsURL = googleMapsURL,
           UIApplication.shared.canOpenURL(googleMapsURL) {
            UIApplication.shared.open(googleMapsURL)
            print("✅ Opened in Google Maps with driving directions")
        } else {
            // Fallback: Open Google Maps in browser
            let webGoogleMapsURL = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)&travelmode=driving")

            if let webGoogleMapsURL = webGoogleMapsURL {
                UIApplication.shared.open(webGoogleMapsURL)
                print("✅ Opened Google Maps in browser")
            }
        }
    }

    // MARK: - Weather Timer Management (REMOVED - Manual refresh only)

    private func stopWeatherTimer() {
        timer?.invalidate()
        timer = nil
        print("🛑 WeatherWidget: Timer stopped")
    }

    private func refreshWeatherIfNeeded() {
        guard isVisible else { return }

        // Only fetch if we haven't fetched in the last hour (prevents excessive API calls on rapid view changes)
        if let lastFetch = lastWeatherFetch,
           Date().timeIntervalSince(lastFetch) < 3600 {
            print("⏭️ WeatherWidget: Skipping fetch - last fetched \(Int(Date().timeIntervalSince(lastFetch)))s ago")
            return
        }

        // Fetch weather manually when user opens home page
        if let location = locationService.currentLocation {
            Task {
                await weatherService.fetchWeather(for: location)
                lastWeatherFetch = Date()
            }
        }
    }
}

// MARK: - Navigation ETA Row Component

struct NavigationETARow: View {
    let icon: String
    let eta: String?
    let isLocationSet: Bool
    let isLoading: Bool
    let colorScheme: ColorScheme
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    .frame(width: 20)

                // Content based on state
                if !isLocationSet {
                    // Location not set - show "Set Location" with plus icon
                    Text("Set Location")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(
                            colorScheme == .dark ?
                                Color.white :
                                Color.black
                        )

                    Spacer()

                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(
                            colorScheme == .dark ?
                                Color.white :
                                Color.black
                        )
                } else if isLoading {
                    // Location set but loading
                    ProgressView()
                        .scaleEffect(0.7)

                    Spacer()
                } else if let eta = eta {
                    // Location set and ETA available
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text(eta)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.9))
                    }

                    Spacer()
                } else {
                    // Location set but ETA failed/unavailable
                    Text("—")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                    Spacer()
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    HapticManager.shared.selection()
                    onLongPress()
                }
        )
    }
}

#Preview {
    WeatherWidget()
}