import Foundation
import CoreLocation

// MARK: - SOLUTION 5: Dwell Time Validation Service
//
// This service prevents false positives from brief passes or traffic stops
// by requiring users to be present in a location for 2-3 minutes before recording a visit.
//
// How it works:
// 1. When user enters a geofence, create a "pending entry" instead of immediate visit
// 2. Start a validation timer (2-3 minutes)
// 3. Continuously check if user is still within the geofence
// 4. If user leaves before timer expires, cancel the pending entry
// 5. If timer expires and user is still inside, create the visit

@MainActor
class DwellTimeValidator: ObservableObject {
    static let shared = DwellTimeValidator()

    // MARK: - Configuration

    /// Required dwell time in seconds (default: 30 seconds)
    /// User must be continuously present for this duration before visit is recorded
    /// REDUCED from 180s (3min) to 30s for faster geofence triggering while still preventing false positives
    private let requiredDwellTimeSeconds: TimeInterval = 30 // 30 seconds

    /// Validation check interval (how often to check if user is still inside)
    /// REDUCED from 30s to 10s for more responsive validation
    private let validationIntervalSeconds: TimeInterval = 10 // Check every 10 seconds

    // MARK: - Models

    struct PendingEntry {
        let placeId: UUID
        let placeName: String
        let entryTime: Date
        let initialLocation: CLLocation
        let geofenceRadius: CLLocationDistance
        var validationTimer: Timer?

        var elapsedSeconds: TimeInterval {
            return Date().timeIntervalSince(entryTime)
        }

        var remainingSeconds: TimeInterval {
            return max(0, DwellTimeValidator.shared.requiredDwellTimeSeconds - elapsedSeconds)
        }
    }

    // MARK: - State

    /// Pending entries awaiting dwell time validation
    @Published private(set) var pendingEntries: [UUID: PendingEntry] = [:]

    /// Validation timers for continuous location checks
    private var validationTimers: [UUID: Timer] = [:]

    private init() {}

    // MARK: - Public API

    /// Register a pending entry when user enters a geofence
    /// Returns: true if pending entry created, false if immediate visit should be created
    func registerPendingEntry(
        placeId: UUID,
        placeName: String,
        currentLocation: CLLocation,
        geofenceRadius: CLLocationDistance,
        locationManager: SharedLocationManager,
        onValidated: @escaping (UUID) -> Void
    ) {
        // Cancel any existing pending entry for this place
        cancelPendingEntry(for: placeId)

        print("\n⏳ ===== DWELL TIME VALIDATION STARTED =====")
        print("⏳ Location: \(placeName)")
        print("⏳ Required dwell time: \(Int(requiredDwellTimeSeconds)) seconds")
        print("⏳ User must remain inside for \(Int(requiredDwellTimeSeconds / 60)) minutes")
        print("⏳ ==========================================\n")

        let pendingEntry = PendingEntry(
            placeId: placeId,
            placeName: placeName,
            entryTime: Date(),
            initialLocation: currentLocation,
            geofenceRadius: geofenceRadius
        )

        pendingEntries[placeId] = pendingEntry

        // Start validation timer - checks every 30 seconds
        startValidationTimer(
            for: placeId,
            locationManager: locationManager,
            onValidated: onValidated
        )

        // Start final confirmation timer - fires after dwell time expires
        startDwellTimer(
            for: placeId,
            locationManager: locationManager,
            onValidated: onValidated
        )
    }

    /// Cancel a pending entry (user left before dwell time expired)
    func cancelPendingEntry(for placeId: UUID) {
        guard let entry = pendingEntries[placeId] else { return }

        print("\n❌ DWELL TIME VALIDATION CANCELLED")
        print("   Location: \(entry.placeName)")
        print("   Duration: \(String(format: "%.0f", entry.elapsedSeconds))s / \(Int(requiredDwellTimeSeconds))s")
        print("   Reason: User left before dwell time expired\n")

        // Cancel timers
        validationTimers[placeId]?.invalidate()
        validationTimers.removeValue(forKey: placeId)

        // Remove pending entry
        pendingEntries.removeValue(forKey: placeId)
    }

    /// Cancel all pending entries
    func cancelAllPendingEntries() {
        for placeId in pendingEntries.keys {
            cancelPendingEntry(for: placeId)
        }
    }

    /// Check if there's a pending entry for a place
    func hasPendingEntry(for placeId: UUID) -> Bool {
        return pendingEntries[placeId] != nil
    }

    /// Get pending entry info for a place
    func getPendingEntry(for placeId: UUID) -> PendingEntry? {
        return pendingEntries[placeId]
    }

    // MARK: - Private Methods

    /// Start validation timer - checks if user is still inside every 30 seconds
    private func startValidationTimer(
        for placeId: UUID,
        locationManager: SharedLocationManager,
        onValidated: @escaping (UUID) -> Void
    ) {
        let timer = Timer.scheduledTimer(withTimeInterval: validationIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.validateStillInside(
                    placeId: placeId,
                    locationManager: locationManager,
                    onValidated: onValidated
                )
            }
        }

        validationTimers[placeId] = timer
    }

    /// Start dwell timer - fires after required dwell time expires
    private func startDwellTimer(
        for placeId: UUID,
        locationManager: SharedLocationManager,
        onValidated: @escaping (UUID) -> Void
    ) {
        Task {
            // Wait for dwell time to expire
            try? await Task.sleep(nanoseconds: UInt64(requiredDwellTimeSeconds * 1_000_000_000))

            // Final validation check
            await validateStillInside(
                placeId: placeId,
                locationManager: locationManager,
                onValidated: onValidated,
                isFinalCheck: true
            )
        }
    }

    /// Validate that user is still inside the geofence
    private func validateStillInside(
        placeId: UUID,
        locationManager: SharedLocationManager,
        onValidated: @escaping (UUID) -> Void,
        isFinalCheck: Bool = false
    ) async {
        guard let entry = pendingEntries[placeId] else { return }

        // Get current location
        guard let currentLocation = locationManager.currentLocation else {
            print("⚠️ Dwell validation: No current location available")
            return
        }

        // SPEED CHECK: If user is moving fast during validation, cancel
        // This prevents drive-by false positives even if dwell time hasn't expired
        let speed = currentLocation.speed // m/s
        let maxAllowedSpeed: Double = 5.5 // ~20 km/h

        if speed > 0 && speed > maxAllowedSpeed {
            print("⏭️ Dwell validation cancelled: User moving at \(String(format: "%.1f", speed * 3.6)) km/h (likely driving)")
            cancelPendingEntry(for: placeId)
            return
        }

        // Check if still within geofence
        let distance = currentLocation.distance(from: entry.initialLocation)

        if distance <= entry.geofenceRadius {
            if isFinalCheck {
                // Dwell time complete and still inside - create visit!
                print("\n✅ DWELL TIME VALIDATION PASSED")
                print("   Location: \(entry.placeName)")
                print("   Duration: \(String(format: "%.0f", entry.elapsedSeconds))s")
                print("   Distance from entry: \(String(format: "%.0f", distance))m")
                print("   Creating visit...\n")

                // Clean up
                validationTimers[placeId]?.invalidate()
                validationTimers.removeValue(forKey: placeId)
                pendingEntries.removeValue(forKey: placeId)

                // Notify GeofenceManager to create visit
                onValidated(placeId)
            } else {
                // Still inside, validation check passed
                print("⏳ Dwell validation check: Still inside \(entry.placeName) (\(String(format: "%.0f", entry.remainingSeconds))s remaining)")
            }
        } else {
            // User left the geofence - cancel pending entry
            print("⏭️ Dwell validation: User left \(entry.placeName) early (\(String(format: "%.0f", distance))m away)")
            cancelPendingEntry(for: placeId)
        }
    }

    // MARK: - Diagnostics

    /// Print status of all pending entries
    func printStatus() {
        if pendingEntries.isEmpty {
            print("📊 No pending dwell time validations")
            return
        }

        print("\n📊 ===== DWELL TIME VALIDATION STATUS =====")
        for (_, entry) in pendingEntries {
            print("📊 \(entry.placeName)")
            print("   Elapsed: \(String(format: "%.0f", entry.elapsedSeconds))s / \(Int(requiredDwellTimeSeconds))s")
            print("   Remaining: \(String(format: "%.0f", entry.remainingSeconds))s")
        }
        print("📊 ========================================\n")
    }

    /// Check if dwell time validation is enabled
    var isEnabled: Bool {
        return requiredDwellTimeSeconds > 0
    }

    /// Get required dwell time in minutes (for UI)
    var requiredDwellTimeMinutes: Int {
        return Int(requiredDwellTimeSeconds / 60)
    }

    // MARK: - PERFORMANCE FIX: Skip Dwell Validation for Trusted Locations

    /// Categories that should skip dwell time validation (instant entry)
    /// These are frequent, trusted locations where false positives are unlikely
    private let skipDwellCategories: Set<String> = [
        "Home", "Residence", "Apartment", "House",
        "Work", "Office", "Workplace", "Corporate Office"
    ]

    /// Check if a location should skip dwell time validation
    /// Returns true for frequently visited, trusted locations (Home, Work)
    func shouldSkipDwellValidation(for category: String) -> Bool {
        // Check if category matches any skip categories (case-insensitive)
        let lowerCategory = category.lowercased()
        for skipCategory in skipDwellCategories {
            if lowerCategory.contains(skipCategory.lowercased()) {
                return true
            }
        }
        return false
    }
}
