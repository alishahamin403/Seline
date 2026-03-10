//
//  VisitStateManager.swift
//  Seline
//
//  Created on 2026-01-28.
//  Centralized state manager for visit data across all views
//

import Foundation
import SwiftUI

@MainActor
class VisitStateManager: ObservableObject {
    static let shared = VisitStateManager()

    private struct VisitDeletionSnapshot {
        let todaysVisits: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)]
        let selectedDayVisits: [LocationVisitRecord]
        let monthVisitCounts: [Date: Int]
        let selectedDayVisitContexts: [UUID: ProcessedVisitDisplayContext]
    }

    // MARK: - Published State

    // Today's visits for home page widget
    @Published var todaysVisits: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)] = []

    // Selected day visits for calendar detail view
    @Published var selectedDayVisits: [LocationVisitRecord] = []

    // Month visit counts for calendar grid
    @Published var monthVisitCounts: [Date: Int] = [:]

    // Current selections
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var currentMonth: Date = Calendar.current.startOfDay(for: Date())

    // Loading states
    @Published var isLoadingToday: Bool = false
    @Published var isLoadingDay: Bool = false
    @Published var isLoadingMonth: Bool = false

    private var selectedDayVisitContexts: [UUID: ProcessedVisitDisplayContext] = [:]
    private var latestSelectedDayRequest: Date?
    private var latestMonthRequest: Date?

    // MARK: - Initialization

    private init() {
        setupNotificationListeners()
    }

    // MARK: - Notification Listeners

    private func setupNotificationListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisitUpdate),
            name: NSNotification.Name("VisitUpdated"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisitDeleted),
            name: NSNotification.Name("VisitDeleted"),
            object: nil
        )
    }

    @objc private func handleVisitUpdate() {
        Task {
            await refreshAllViews()
        }
    }

    @objc private func handleVisitDeleted() {
        Task {
            await refreshAllViews()
        }
    }

    // MARK: - Fetch Methods

    func fetchTodaysVisits() async {
        isLoadingToday = true
        defer { isLoadingToday = false }

        print("📊 [VisitStateManager] Fetching today's visits...")

        // Use the existing getTodaysVisitsWithDuration method
        let visits = await LocationVisitAnalytics.shared.getTodaysVisitsWithDuration()

        todaysVisits = visits
        print("📊 [VisitStateManager] Fetched \(visits.count) locations for today")
    }

    func fetchVisitsForDay(_ date: Date) async {
        isLoadingDay = true
        defer { isLoadingDay = false }

        print("📊 [VisitStateManager] Fetching visits for \(date)...")
        let calendar = Calendar.current
        let requestedDay = calendar.startOfDay(for: date)
        latestSelectedDayRequest = requestedDay

        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ [VisitStateManager] No user ID found")
            if latestSelectedDayRequest == requestedDay {
                selectedDayVisits = []
                selectedDayVisitContexts = [:]
            }
            return
        }

        let startOfDay = requestedDay
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            print("❌ [VisitStateManager] Failed to calculate end of day")
            if latestSelectedDayRequest == requestedDay {
                selectedDayVisits = []
                selectedDayVisitContexts = [:]
            }
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: startOfDay.ISO8601Format())
                .lt("entry_time", value: endOfDay.ISO8601Format())
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let rawVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            let displayContexts = LocationVisitAnalytics.shared.buildDisplayContexts(for: rawVisits)
            guard latestSelectedDayRequest == requestedDay else { return }
            selectedDayVisits = displayContexts.map(\.displayedVisit)
            selectedDayVisitContexts = Dictionary(uniqueKeysWithValues: displayContexts.map { ($0.displayedVisit.id, $0) })

            print("📊 [VisitStateManager] Fetched \(displayContexts.count) visits for selected day")
        } catch {
            print("❌ [VisitStateManager] Error fetching visits for day: \(error)")
            guard latestSelectedDayRequest == requestedDay else { return }
            selectedDayVisits = []
            selectedDayVisitContexts = [:]
        }
    }

    func fetchVisitsForMonth(_ month: Date) async {
        isLoadingMonth = true
        defer { isLoadingMonth = false }

        print("📊 [VisitStateManager] Fetching visits for month \(month)...")
        let calendar = Calendar.current
        let requestedMonth = calendar.startOfDay(for: month)
        latestMonthRequest = requestedMonth

        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ [VisitStateManager] No user ID found")
            if latestMonthRequest == requestedMonth {
                currentMonth = requestedMonth
                monthVisitCounts = [:]
            }
            return
        }

        guard let monthInterval = calendar.dateInterval(of: .month, for: requestedMonth) else {
            print("❌ [VisitStateManager] Failed to calculate month boundaries")
            if latestMonthRequest == requestedMonth {
                currentMonth = requestedMonth
                monthVisitCounts = [:]
            }
            return
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("entry_time", value: monthInterval.start.ISO8601Format())
                .lte("entry_time", value: monthInterval.end.ISO8601Format())
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
            let processedVisits = LocationVisitAnalytics.shared.processVisitsForDisplay(visits)

            // Group by day
            var visitsByDay: [Date: Int] = [:]
            for visit in processedVisits {
                let normalizedDate = calendar.startOfDay(for: visit.entryTime)
                visitsByDay[normalizedDate, default: 0] += 1
            }

            guard latestMonthRequest == requestedMonth else { return }
            currentMonth = requestedMonth
            monthVisitCounts = visitsByDay

            print("📊 [VisitStateManager] Fetched \(visitsByDay.count) days with visits for month")
        } catch {
            print("❌ [VisitStateManager] Error fetching visits for month: \(error)")
            guard latestMonthRequest == requestedMonth else { return }
            currentMonth = requestedMonth
            monthVisitCounts = [:]
        }
    }

    func canEditVisit(id: UUID) -> Bool {
        guard let context = selectedDayVisitContexts[id] else { return true }
        return !context.isDerivedSplit
    }

    func updateVisit(id: UUID, entryTime: Date, exitTime: Date?) async -> Bool {
        guard let context = selectedDayVisitContexts[id] else {
            print("❌ [VisitStateManager] Missing visit context for edit \(id.uuidString)")
            return false
        }

        let success = await LocationVisitAnalytics.shared.updateVisitTiming(
            displayedVisit: context.displayedVisit,
            sourceVisits: context.sourceVisits,
            entryTime: entryTime,
            exitTime: exitTime
        )

        if success {
            await refreshAllViews()
        }

        return success
    }

    // MARK: - Delete Method

    func deleteVisit(id: UUID) async -> Bool {
        print("🗑️ [VisitStateManager] Deleting visit \(id.uuidString)...")

        guard let deletedVisit = selectedDayVisits.first(where: { $0.id == id }) else {
            // Fallback when selected-day cache does not contain the visit:
            // still fire remote deletion in background and return immediately.
            Task {
                let success = await LocationVisitAnalytics.shared.deleteVisit(id: id.uuidString)
                if success {
                    await MainActor.run {
                        LocationVisitAnalytics.shared.invalidateAllVisitCaches()
                        NotificationCenter.default.post(name: NSNotification.Name("VisitDeleted"), object: nil)
                    }
                    await refreshAllViews()
                }
            }
            return true
        }

        let sourceVisitIds = selectedDayVisitContexts[id]?.sourceVisits.map(\.id) ?? [id]

        let snapshot = VisitDeletionSnapshot(
            todaysVisits: todaysVisits,
            selectedDayVisits: selectedDayVisits,
            monthVisitCounts: monthVisitCounts,
            selectedDayVisitContexts: selectedDayVisitContexts
        )

        applyOptimisticVisitDeletion(deletedVisit)

        Task {
            let success = await LocationVisitAnalytics.shared.deleteVisits(ids: sourceVisitIds)

            if success {
                await MainActor.run {
                    print("✅ [VisitStateManager] Visit deleted remotely, syncing refreshed data...")
                    LocationVisitAnalytics.shared.invalidateAllVisitCaches()
                    NotificationCenter.default.post(name: NSNotification.Name("VisitDeleted"), object: nil)
                }
                await refreshAllViews()
            } else {
                await MainActor.run {
                    print("❌ [VisitStateManager] Failed remote delete, restoring local state")
                    todaysVisits = snapshot.todaysVisits
                    selectedDayVisits = snapshot.selectedDayVisits
                    monthVisitCounts = snapshot.monthVisitCounts
                    selectedDayVisitContexts = snapshot.selectedDayVisitContexts
                }
            }
        }

        return true
    }

    private func applyOptimisticVisitDeletion(_ visit: LocationVisitRecord) {
        selectedDayVisits.removeAll { $0.id == visit.id }
        selectedDayVisitContexts.removeValue(forKey: visit.id)

        let calendar = Calendar.current
        let visitDay = calendar.startOfDay(for: visit.entryTime)
        if let count = monthVisitCounts[visitDay] {
            let newCount = max(0, count - 1)
            if newCount == 0 {
                monthVisitCounts.removeValue(forKey: visitDay)
            } else {
                monthVisitCounts[visitDay] = newCount
            }
        }

        if calendar.isDateInToday(visit.entryTime) {
            let visitDuration = max(
                visit.durationMinutes
                    ?? Int((visit.exitTime ?? Date()).timeIntervalSince(visit.entryTime) / 60),
                1
            )

            if let index = todaysVisits.firstIndex(where: { $0.id == visit.savedPlaceId }) {
                var item = todaysVisits[index]
                item.totalDurationMinutes = max(0, item.totalDurationMinutes - visitDuration)

                if item.totalDurationMinutes == 0 && !item.isActive {
                    todaysVisits.remove(at: index)
                } else {
                    todaysVisits[index] = item
                }
            }
        }
    }

    // MARK: - Refresh Methods

    func refreshAllViews() async {
        print("🔄 [VisitStateManager] Refreshing all views...")

        // Fetch all data in parallel
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.fetchTodaysVisits()
            }

            group.addTask {
                await self.fetchVisitsForDay(self.selectedDate)
            }

            group.addTask {
                await self.fetchVisitsForMonth(self.currentMonth)
            }
        }

        print("✅ [VisitStateManager] All views refreshed")
    }

    func refreshToday() async {
        await fetchTodaysVisits()
    }

    func refreshDay(_ date: Date) async {
        await fetchVisitsForDay(date)
    }

    func refreshMonth(_ month: Date) async {
        await fetchVisitsForMonth(month)
    }
}
