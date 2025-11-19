import Foundation
import PostgREST

class RecurringExpenseService {
    static let shared = RecurringExpenseService()

    private let supabaseManager = SupabaseManager.shared

    // MARK: - Create

    /// Save a new recurring expense to the database
    func createRecurringExpense(_ expense: RecurringExpense) async throws -> RecurringExpense {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            throw NSError(domain: "RecurringExpenseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        var mutableExpense = expense
        mutableExpense.userId = userId.uuidString

        print("✅ Creating recurring expense: \(mutableExpense.title)")

        // Auto-generate instances
        let instances = RecurringExpenseManager.shared.generateInstances(for: mutableExpense)
        print("📅 Generated \(instances.count) instances")

        // Schedule reminders
        RecurringExpenseManager.shared.scheduleReminder(for: mutableExpense)

        // TODO: Save to Supabase when endpoint is available
        // For now, return the expense object
        return mutableExpense
    }

    // MARK: - Read

    /// Fetch all active recurring expenses for the current user
    func fetchActiveRecurringExpenses() async throws -> [RecurringExpense] {
        guard let _ = supabaseManager.getCurrentUser()?.id else {
            return []
        }

        // TODO: Fetch from Supabase database
        // For now, return empty array
        print("📊 Fetching active recurring expenses from Supabase...")
        return []
    }

    /// Fetch all recurring expenses (including inactive)
    func fetchAllRecurringExpenses() async throws -> [RecurringExpense] {
        guard let _ = supabaseManager.getCurrentUser()?.id else {
            return []
        }

        // TODO: Fetch from Supabase database
        // For now, return empty array
        print("📊 Fetching all recurring expenses from Supabase...")
        return []
    }

    /// Fetch a single recurring expense by ID
    func fetchRecurringExpense(id: UUID) async throws -> RecurringExpense {
        // TODO: Fetch from Supabase database
        throw NSError(domain: "RecurringExpenseService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not yet implemented"])
    }

    // MARK: - Update

    /// Update an existing recurring expense
    func updateRecurringExpense(_ expense: RecurringExpense) async throws -> RecurringExpense {
        print("✅ Updated recurring expense: \(expense.title)")

        // TODO: Update in Supabase database
        return expense
    }

    /// Toggle active status of a recurring expense
    func toggleRecurringExpenseActive(id: UUID, isActive: Bool) async throws {
        print("✅ Toggled recurring expense active status")

        // Cancel or reschedule reminders
        if !isActive {
            RecurringExpenseManager.shared.cancelReminder(for: id)
        }

        // TODO: Update in Supabase database
    }

    // MARK: - Delete

    /// Delete a recurring expense and its instances
    func deleteRecurringExpense(id: UUID) async throws {
        print("✅ Deleted recurring expense and its instances")

        // Cancel reminders
        RecurringExpenseManager.shared.cancelReminder(for: id)

        // TODO: Delete from Supabase database (with cascade to instances)
    }

    // MARK: - Instances

    /// Fetch instances for a recurring expense
    func fetchInstances(for recurringExpenseId: UUID) async throws -> [RecurringInstance] {
        // TODO: Fetch from Supabase database
        print("📅 Fetching instances for recurring expense...")
        return []
    }

    /// Update instance status
    func updateInstanceStatus(id: UUID, status: InstanceStatus) async throws {
        print("✅ Updated instance status to \(status.displayName)")

        // TODO: Update in Supabase database
    }

    /// Link instance to a note
    func linkInstanceToNote(instanceId: UUID, noteId: UUID) async throws {
        print("✅ Linked instance to note")

        // TODO: Update in Supabase database
    }
}
