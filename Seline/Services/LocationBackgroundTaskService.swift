import Foundation
import CoreLocation
import BackgroundTasks
import WidgetKit

/// LocationBackgroundTaskService handles background location checks
/// to ensure location sessions start/end promptly even when the app is killed.
///
/// iOS geofencing can be delayed by 10-20 minutes for battery efficiency.
/// This service provides additional background checks to improve responsiveness.
@MainActor
class LocationBackgroundTaskService {
    static let shared = LocationBackgroundTaskService()
    
    // Background task identifiers
    static let locationRefreshTaskId = "com.seline.locationRefresh"
    static let locationProcessingTaskId = "com.seline.locationProcessing"
    
    private let sharedLocationManager = SharedLocationManager.shared
    private let geofenceManager = GeofenceManager.shared
    private let locationsManager = LocationsManager.shared
    
    private init() {}
    
    // MARK: - Background Task Registration
    
    /// Register background tasks with BGTaskScheduler
    /// Call this from SelineApp.init()
    func registerBackgroundTasks() {
        // App Refresh task - lightweight, runs every 15+ minutes
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.locationRefreshTaskId,
            using: nil
        ) { task in
            Task {
                await self.handleLocationRefreshTask(task)
            }
        }
        
        // Processing task - more reliable, runs when device is idle/charging
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.locationProcessingTaskId,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            
            Task {
                await self.handleLocationProcessingTask(processingTask)
            }
        }
        
        print("📍 Background location tasks registered")
    }
    
    // MARK: - Task Scheduling
    
    /// Schedule the next background location refresh task
    func scheduleLocationRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.locationRefreshTaskId)
        // Schedule in 15 minutes (minimum for app refresh)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 Location refresh scheduled for 15 minutes from now")
        } catch {
            print("⚠️ Failed to schedule location refresh: \(error)")
        }
    }
    
    /// Schedule the next background location processing task
    func scheduleLocationProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.locationProcessingTaskId)
        // Schedule in 5 minutes
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        request.requiresNetworkConnectivity = false // Location check doesn't need network
        request.requiresExternalPower = false // Can run on battery
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("📅 Location processing scheduled for 5 minutes from now")
        } catch {
            print("⚠️ Failed to schedule location processing: \(error)")
        }
    }
    
    // MARK: - Task Handlers
    
    /// Handle background app refresh task for location
    private func handleLocationRefreshTask(_ task: BGTask) async {
        print("\n📍 ===== BACKGROUND LOCATION REFRESH STARTED =====")
        
        // Schedule next refresh immediately
        scheduleLocationRefresh()
        
        // Perform location check
        let success = await performBackgroundLocationCheck()
        
        task.setTaskCompleted(success: success)
        print("📍 ===== BACKGROUND LOCATION REFRESH COMPLETE =====\n")
    }
    
    /// Handle background processing task for location
    private func handleLocationProcessingTask(_ task: BGProcessingTask) async {
        print("\n📍 ===== BACKGROUND LOCATION PROCESSING STARTED =====")
        
        // Set up expiration handler
        task.expirationHandler = {
            print("⚠️ Background location processing expired")
            task.setTaskCompleted(success: false)
        }
        
        // Schedule next processing
        scheduleLocationProcessing()
        
        // Perform thorough location check
        let success = await performBackgroundLocationCheck()
        
        task.setTaskCompleted(success: success)
        print("📍 ===== BACKGROUND LOCATION PROCESSING COMPLETE =====\n")
    }
    
    // MARK: - Location Check Logic
    
    /// Perform a background location check
    /// Returns true if check was successful
    private func performBackgroundLocationCheck() async -> Bool {
        // Ensure geofences are set up
        let savedPlaces = locationsManager.savedPlaces
        guard !savedPlaces.isEmpty else {
            print("📍 No saved places, skipping location check")
            return true
        }
        
        // Request current location
        guard let currentLocation = await sharedLocationManager.waitForLocation(timeout: 15.0) else {
            print("❌ Could not get location in background")
            return false
        }
        
        print("📍 Got background location: (\(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude))")
        print("   Accuracy: ±\(String(format: "%.0f", currentLocation.horizontalAccuracy))m")
        
        // Check if user is inside any saved location
        for place in savedPlaces {
            let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let distance = currentLocation.distance(from: placeLocation)
            let radius = GeofenceRadiusManager.shared.getRadius(for: place)
            
            let isInside = distance <= radius
            let hasActiveVisit = geofenceManager.getActiveVisit(for: place.id) != nil
            
            if isInside && !hasActiveVisit {
                // User is inside but no active visit - start one!
                print("🚨 DETECTED: User inside \(place.displayName) but NO active visit!")
                print("   Distance: \(String(format: "%.0f", distance))m, Radius: \(String(format: "%.0f", radius))m")
                
                await startVisitFromBackground(for: place.id, placeName: place.displayName)
                
                // Refresh widgets immediately
                WidgetCenter.shared.reloadAllTimelines()
                
                // Only start one visit at a time
                break
                
            } else if !isInside && hasActiveVisit {
                // User is outside but has active visit - end it!
                print("🚨 DETECTED: User outside \(place.displayName) but HAS active visit!")
                print("   Distance: \(String(format: "%.0f", distance))m, Radius: \(String(format: "%.0f", radius))m")
                
                await endVisitFromBackground(for: place.id, placeName: place.displayName)
                
                // Refresh widgets immediately
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        
        return true
    }
    
    /// Start a visit when detected in background
    private func startVisitFromBackground(for placeId: UUID, placeName: String) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID for visit tracking")
            return
        }
        
        // Double check no existing visit (race condition prevention)
        if geofenceManager.getActiveVisit(for: placeId) != nil {
            print("ℹ️ Visit already exists, skipping")
            return
        }
        
        // Create new visit
        let sessionId = UUID()
        let visit = LocationVisitRecord.create(
            userId: userId,
            savedPlaceId: placeId,
            entryTime: Date(),
            sessionId: sessionId,
            confidenceScore: 0.85, // Slightly lower confidence for background detection
            mergeReason: "background_detection"
        )
        
        // Add to active visits
        geofenceManager.updateActiveVisit(visit, for: placeId)
        
        // Create session
        LocationSessionManager.shared.createSession(for: placeId, userId: userId)
        
        // Save to Supabase
        await geofenceManager.saveVisitToSupabase(visit)
        
        // CRITICAL: Use unified cache invalidation to keep all views in sync
        LocationVisitAnalytics.shared.invalidateAllVisitCaches()
        
        print("✅ Started visit from background for: \(placeName)")
        
        // Post notification (also posted by invalidateAllVisitCaches, but keep for explicit trigger)
        NotificationCenter.default.post(name: NSNotification.Name("GeofenceVisitCreated"), object: nil)
        
        // Start validation timer
        if !LocationBackgroundValidationService.shared.isValidationRunning() {
            LocationBackgroundValidationService.shared.startValidationTimer(
                geofenceManager: geofenceManager,
                locationManager: sharedLocationManager,
                savedPlaces: LocationsManager.shared.savedPlaces
            )
        }
    }
    
    /// End a visit when detected in background
    private func endVisitFromBackground(for placeId: UUID, placeName: String) async {
        guard var visit = geofenceManager.getActiveVisit(for: placeId) else {
            print("⚠️ No active visit found to end")
            return
        }
        
        // Record exit
        visit.recordExit(exitTime: Date())
        
        // Remove from active visits
        geofenceManager.removeActiveVisit(for: placeId)
        
        // Cache for merge detection
        MergeDetectionService.shared.cacheClosedVisit(visit)
        
        // Handle midnight split if needed
        let visitsToSave = visit.splitAtMidnightIfNeeded()
        
        if visitsToSave.count > 1 {
            print("🌙 Midnight split needed - saving \(visitsToSave.count) records")
            await geofenceManager.deleteVisitFromSupabase(visit)
            for splitVisit in visitsToSave {
                await geofenceManager.saveVisitToSupabase(splitVisit)
            }
        } else {
            // AUTO-DELETE: Delete visits under 2 minutes instead of updating them
            if let durationMinutes = visit.durationMinutes, durationMinutes < 2 {
                print("🗑️ Auto-deleting short visit from background: \(visit.id.uuidString) (duration: \(durationMinutes) min < 2 min)")
                await geofenceManager.deleteVisitFromSupabase(visit)
            } else {
                // Update in Supabase
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                
                let updateData: [String: PostgREST.AnyJSON] = [
                    "exit_time": .string(formatter.string(from: visit.exitTime!)),
                    "duration_minutes": .double(Double(visit.durationMinutes ?? 0)),
                    "updated_at": .string(formatter.string(from: Date()))
                ]
                
                do {
                    let client = await SupabaseManager.shared.getPostgrestClient()
                    try await client
                        .from("location_visits")
                        .update(updateData)
                        .eq("id", value: visit.id.uuidString)
                        .execute()
                    
                    print("✅ Ended visit from background for: \(placeName)")
                } catch {
                    print("❌ Error updating visit: \(error)")
                }
            }
        }
        
        // CRITICAL: Use unified cache invalidation to keep all views in sync
        LocationVisitAnalytics.shared.invalidateAllVisitCaches()
        
        // Close session
        LocationSessionManager.shared.closeSession(visit.sessionId ?? UUID())
    }
}

// MARK: - Import for PostgREST
import PostgREST
