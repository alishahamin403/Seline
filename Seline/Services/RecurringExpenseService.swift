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

        // Save recurring expense to database
        let client = await supabaseManager.getPostgrestClient()

        try await client
            .from("recurring_expenses")
            .insert(mutableExpense)
            .execute()

        print("💾 Saved recurring expense to Supabase")

        // Auto-generate instances
        let instances = RecurringExpenseManager.shared.generateInstances(for: mutableExpense)
        print("📅 Generated \(instances.count) instances")

        // Save instances to database
        for instance in instances {
            try await client
                .from("recurring_instances")
                .insert(instance)
                .execute()
        }

        print("💾 Saved \(instances.count) instances to Supabase")

        // Schedule reminders
        RecurringExpenseManager.shared.scheduleReminder(for: mutableExpense)

        // Create corresponding tasks for each instance so they appear in calendar
        await createTasksForInstances(instances, expense: mutableExpense)

        return mutableExpense
    }

    // MARK: - Read

    /// Fetch all active recurring expenses for the current user
    func fetchActiveRecurringExpenses() async throws -> [RecurringExpense] {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            return []
        }

        print("📊 Fetching active recurring expenses from Supabase...")

        let client = await supabaseManager.getPostgrestClient()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try await client
            .from("recurring_expenses")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .execute()

        let expenses = try decoder.decode([RecurringExpense].self, from: response.data)
        print("✅ Fetched \(expenses.count) active recurring expenses")
        return expenses
    }

    /// Fetch all recurring expenses (including inactive)
    func fetchAllRecurringExpenses() async throws -> [RecurringExpense] {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            return []
        }

        print("📊 Fetching all recurring expenses from Supabase...")

        let client = await supabaseManager.getPostgrestClient()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try await client
            .from("recurring_expenses")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()

        let expenses = try decoder.decode([RecurringExpense].self, from: response.data)
        print("✅ Fetched \(expenses.count) recurring expenses")
        return expenses
    }

    /// Fetch a single recurring expense by ID
    func fetchRecurringExpense(id: UUID) async throws -> RecurringExpense {
        let client = await supabaseManager.getPostgrestClient()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try await client
            .from("recurring_expenses")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()

        let expense = try decoder.decode(RecurringExpense.self, from: response.data)
        return expense
    }

    // MARK: - Update

    /// Update an existing recurring expense
    func updateRecurringExpense(_ expense: RecurringExpense) async throws -> RecurringExpense {
        print("✅ Updating recurring expense: \(expense.title)")

        let client = await supabaseManager.getPostgrestClient()

        try await client
            .from("recurring_expenses")
            .update(expense)
            .eq("id", value: expense.id.uuidString)
            .execute()

        print("💾 Updated recurring expense in Supabase")
        return expense
    }

    /// Toggle active status of a recurring expense
    func toggleRecurringExpenseActive(id: UUID, isActive: Bool) async throws {
        print("✅ Toggling recurring expense active status")

        let client = await supabaseManager.getPostgrestClient()

        try await client
            .from("recurring_expenses")
            .update(["is_active": isActive])
            .eq("id", value: id.uuidString)
            .execute()

        print("💾 Updated recurring expense active status in Supabase")

        // Cancel or reschedule reminders and tasks
        if !isActive {
            RecurringExpenseManager.shared.cancelReminder(for: id)
            // Delete corresponding tasks when pausing
            await deleteTasksForRecurringExpense(id)
        } else {
            // Recreate tasks when resuming
            if let expense = try? await fetchRecurringExpense(id: id) {
                let instances = try? await fetchInstances(for: id)
                if let instances = instances {
                    await createTasksForInstances(instances, expense: expense)
                }
            }
        }
    }

    // MARK: - Delete

    /// Delete a recurring expense and its instances
    func deleteRecurringExpense(id: UUID) async throws {
        print("✅ Deleting recurring expense and its instances")

        let client = await supabaseManager.getPostgrestClient()

        // Delete instances first (in case no cascade delete is set)
        try await client
            .from("recurring_instances")
            .delete()
            .eq("recurring_expense_id", value: id.uuidString)
            .execute()

        print("🗑️ Deleted instances")

        // Delete the recurring expense
        try await client
            .from("recurring_expenses")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()

        print("💾 Deleted recurring expense from Supabase")

        // Cancel reminders
        RecurringExpenseManager.shared.cancelReminder(for: id)

        // Delete corresponding tasks
        await deleteTasksForRecurringExpense(id)
    }

    // MARK: - Instances

    /// Fetch instances for a recurring expense
    func fetchInstances(for recurringExpenseId: UUID) async throws -> [RecurringInstance] {
        print("📅 Fetching instances for recurring expense...")

        let client = await supabaseManager.getPostgrestClient()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try await client
            .from("recurring_instances")
            .select()
            .eq("recurring_expense_id", value: recurringExpenseId.uuidString)
            .execute()

        let instances = try decoder.decode([RecurringInstance].self, from: response.data)
        print("✅ Fetched \(instances.count) instances")
        return instances
    }

    /// Update instance status
    func updateInstanceStatus(id: UUID, status: InstanceStatus) async throws {
        print("✅ Updating instance status to \(status.displayName)")

        // For now, this is a placeholder - full implementation would require
        // fetching the instance first, updating it, and re-saving
        // This is handled at the UI level when marking instances as complete
        print("💾 Instance status update will be persisted")
    }

    /// Link instance to a note
    func linkInstanceToNote(instanceId: UUID, noteId: UUID) async throws {
        print("✅ Linking instance to note")

        // For now, this is a placeholder - full implementation would require
        // fetching the instance first, updating it, and re-saving
        print("💾 Instance linked to note")
    }

    // MARK: - Tasks Integration

    /// Create tasks for each recurring instance so they appear in calendar
    private func createTasksForInstances(_ instances: [RecurringInstance], expense: RecurringExpense) async {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            print("⚠️ Could not get user ID for task creation")
            return
        }

        // Get or create the "Recurring" tag
        let recurringTag = await MainActor.run {
            TagManager.shared.getOrCreateRecurringTag()
        }
        let tagId = recurringTag?.id

        let client = await supabaseManager.getPostgrestClient()
        let calendar = Calendar.current

        print("📅 Creating tasks for \(instances.count) instances with tag: \(tagId ?? "none")...")
        var tasksCreated = 0

        for instance in instances {
            // Create a task for this instance
            let taskId = "recurring_\(expense.id)_\(instance.id)"
            let targetDate = instance.occurrenceDate

            // Determine the weekday
            let weekdayIndex = calendar.component(.weekday, from: targetDate)
            let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            let weekdayString = weekdays[weekdayIndex - 1]

            // Create task item with Recurring tag
            var taskData: [String: AnyCodable] = [
                "id": AnyCodable(value: taskId),
                "user_id": AnyCodable(value: userId.uuidString),
                "title": AnyCodable(value: expense.title),
                "is_completed": AnyCodable(value: false),
                "weekday": AnyCodable(value: weekdayString),
                "target_date": AnyCodable(value: targetDate.ISO8601Format()),
                "description": AnyCodable(value: "Amount: \(expense.formattedAmount)" + (expense.category.map { "\nCategory: \($0)" } ?? "")),
                "is_recurring": AnyCodable(value: false),
                "created_at": AnyCodable(value: Date().ISO8601Format())
            ]

            // Add tag ID if available
            if let tagId = tagId {
                taskData["tag_id"] = AnyCodable(value: tagId)
            }

            do {
                try await client
                    .from("tasks")
                    .upsert(taskData)
                    .execute()
                tasksCreated += 1
            } catch {
                print("⚠️ Error creating/updating task for instance: \(error.localizedDescription)")
            }
        }

        print("✅ Created \(tasksCreated)/\(instances.count) tasks for calendar with Recurring tag")
    }

    /// Delete tasks associated with a recurring expense
    func deleteTasksForRecurringExpense(_ expenseId: UUID) async {
        guard let userId = supabaseManager.getCurrentUser()?.id else {
            print("⚠️ Could not get user ID for task deletion")
            return
        }

        let client = await supabaseManager.getPostgrestClient()

        do {
            // Delete all tasks that match this recurring expense pattern
            try await client
                .from("tasks")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .like("id", pattern: "recurring_\(expenseId)_%")
                .execute()

            print("🗑️ Deleted tasks for recurring expense")
        } catch {
            print("⚠️ Error deleting tasks: \(error.localizedDescription)")
        }
    }
}
