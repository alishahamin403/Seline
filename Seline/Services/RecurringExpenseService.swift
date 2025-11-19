import Foundation
import Supabase

class RecurringExpenseService {
    static let shared = RecurringExpenseService()

    private let client = SupabaseManager.shared.client

    // MARK: - Create

    /// Save a new recurring expense to the database
    func createRecurringExpense(_ expense: RecurringExpense) async throws -> RecurringExpense {
        guard let userId = try await SupabaseManager.shared.getCurrentUserId() else {
            throw NSError(domain: "RecurringExpenseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        var mutableExpense = expense
        mutableExpense.userId = userId

        let response = try await client
            .database
            .from("recurring_expenses")
            .insert(mutableExpense)
            .select()
            .single()
            .execute()

        let data = response.data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RecurringExpense.self, from: data)

        print("✅ Created recurring expense: \(decoded.title)")

        // Auto-generate instances
        let instances = RecurringExpenseManager.shared.generateInstances(for: decoded)
        try await createInstances(instances)

        // Schedule reminders
        RecurringExpenseManager.shared.scheduleReminder(for: decoded)

        return decoded
    }

    // MARK: - Read

    /// Fetch all active recurring expenses for the current user
    func fetchActiveRecurringExpenses() async throws -> [RecurringExpense] {
        guard let userId = try await SupabaseManager.shared.getCurrentUserId() else {
            return []
        }

        let response = try await client
            .database
            .from("recurring_expenses")
            .select()
            .eq("user_id", value: userId)
            .eq("is_active", value: true)
            .order("created_at", ascending: false)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expenses = try decoder.decode([RecurringExpense].self, from: response.data)

        return expenses
    }

    /// Fetch all recurring expenses (including inactive)
    func fetchAllRecurringExpenses() async throws -> [RecurringExpense] {
        guard let userId = try await SupabaseManager.shared.getCurrentUserId() else {
            return []
        }

        let response = try await client
            .database
            .from("recurring_expenses")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expenses = try decoder.decode([RecurringExpense].self, from: response.data)

        return expenses
    }

    /// Fetch a single recurring expense by ID
    func fetchRecurringExpense(id: UUID) async throws -> RecurringExpense {
        let response = try await client
            .database
            .from("recurring_expenses")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expense = try decoder.decode(RecurringExpense.self, from: response.data)

        return expense
    }

    // MARK: - Update

    /// Update an existing recurring expense
    func updateRecurringExpense(_ expense: RecurringExpense) async throws -> RecurringExpense {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(expense)

        let response = try await client
            .database
            .from("recurring_expenses")
            .update(data)
            .eq("id", value: expense.id.uuidString)
            .select()
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let updated = try decoder.decode(RecurringExpense.self, from: response.data)

        print("✅ Updated recurring expense: \(updated.title)")

        return updated
    }

    /// Toggle active status of a recurring expense
    func toggleRecurringExpenseActive(id: UUID, isActive: Bool) async throws {
        try await client
            .database
            .from("recurring_expenses")
            .update(["is_active": isActive])
            .eq("id", value: id.uuidString)
            .execute()

        print("✅ Toggled recurring expense active status")

        // Cancel or reschedule reminders
        if !isActive {
            RecurringExpenseManager.shared.cancelReminder(for: id)
        }
    }

    // MARK: - Delete

    /// Delete a recurring expense and its instances
    func deleteRecurringExpense(id: UUID) async throws {
        // Delete instances first (cascade)
        try await client
            .database
            .from("recurring_instances")
            .delete()
            .eq("recurring_expense_id", value: id.uuidString)
            .execute()

        // Delete expense
        try await client
            .database
            .from("recurring_expenses")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()

        // Cancel reminders
        RecurringExpenseManager.shared.cancelReminder(for: id)

        print("✅ Deleted recurring expense and its instances")
    }

    // MARK: - Instances

    /// Create instances for a recurring expense
    private func createInstances(_ instances: [RecurringInstance]) async throws {
        for instance in instances {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(instance)

            _ = try await client
                .database
                .from("recurring_instances")
                .insert(data)
                .execute()
        }

        print("✅ Created \(instances.count) instances")
    }

    /// Fetch instances for a recurring expense
    func fetchInstances(for recurringExpenseId: UUID) async throws -> [RecurringInstance] {
        let response = try await client
            .database
            .from("recurring_instances")
            .select()
            .eq("recurring_expense_id", value: recurringExpenseId.uuidString)
            .order("occurrence_date", ascending: true)
            .execute()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let instances = try decoder.decode([RecurringInstance].self, from: response.data)

        return instances
    }

    /// Update instance status
    func updateInstanceStatus(id: UUID, status: InstanceStatus) async throws {
        try await client
            .database
            .from("recurring_instances")
            .update(["status": status.rawValue])
            .eq("id", value: id.uuidString)
            .execute()

        print("✅ Updated instance status to \(status.displayName)")
    }

    /// Link instance to a note
    func linkInstanceToNote(instanceId: UUID, noteId: UUID) async throws {
        try await client
            .database
            .from("recurring_instances")
            .update(["note_id": noteId.uuidString])
            .eq("id", value: instanceId.uuidString)
            .execute()

        print("✅ Linked instance to note")
    }
}
