//
//  TodoManager.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import Foundation
import UserNotifications

@MainActor
class TodoManager: ObservableObject {
    static let shared = TodoManager()
    
    @Published var todos: [TodoItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let userDefaults = UserDefaults.standard
    private let todosKey = "SavedTodos"
    private let notificationManager = NotificationManager.shared
    
    private init() {
        loadTodos()
        setupNotificationHandling()
    }
    
    // MARK: - Data Persistence
    
    private func saveTodos() {
        do {
            let data = try JSONEncoder().encode(todos)
            userDefaults.set(data, forKey: todosKey)
            print("✅ TodoManager: Saved \(todos.count) todos")
        } catch {
            print("❌ TodoManager: Failed to save todos: \(error)")
            errorMessage = "Failed to save todos"
        }
    }
    
    private func loadTodos() {
        guard let data = userDefaults.data(forKey: todosKey) else {
            // Load sample data for development
            todos = TodoItem.sampleData
            return
        }
        
        do {
            todos = try JSONDecoder().decode([TodoItem].self, from: data)
            print("✅ TodoManager: Loaded \(todos.count) todos")
        } catch {
            print("❌ TodoManager: Failed to load todos: \(error)")
            todos = []
        }
    }
    
    // MARK: - CRUD Operations
    
    func addTodo(_ todo: TodoItem) async {
        todos.append(todo)
        sortTodos()
        saveTodos()
        
        // Schedule notification if reminder date is set
        if let reminderDate = todo.reminderDate {
            await scheduleNotification(for: todo, at: reminderDate)
        }
        
        print("✅ TodoManager: Added todo: \(todo.title)")
    }
    
    func updateTodo(_ todo: TodoItem) async {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = todo
            sortTodos()
            saveTodos()
            
            // Update notification
            await cancelNotification(for: todo.id)
            if let reminderDate = todo.reminderDate, !todo.isCompleted {
                await scheduleNotification(for: todo, at: reminderDate)
            }
            
            print("✅ TodoManager: Updated todo: \(todo.title)")
        }
    }
    
    func deleteTodo(_ todo: TodoItem) async {
        todos.removeAll { $0.id == todo.id }
        saveTodos()
        
        // Cancel notification
        await cancelNotification(for: todo.id)
        
        print("✅ TodoManager: Deleted todo: \(todo.title)")
    }
    
    func toggleCompletion(_ todo: TodoItem) async {
        var updatedTodo = todo
        updatedTodo.isCompleted.toggle()
        await updateTodo(updatedTodo)
    }
    
    // MARK: - Voice Todo Creation
    
    func createTodoFromSpeech(_ speechText: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            print("🔍 TodoManager: Starting AI processing...")
            let processedData = try await AITodoProcessor.shared.processSpeechToTodo(speechText)
            print("🔍 TodoManager: AI processing completed, converting to TodoItem...")
            let todo = processedData.toTodoItem()
            print("🔍 TodoManager: TodoItem created: \(todo.title)")
            print("🔍 TodoManager: Adding todo to manager...")
            await addTodo(todo)
            print("✅ TodoManager: Todo added successfully")
        } catch {
            print("❌ TodoManager: Failed to create todo from speech: \(error)")
            errorMessage = "Failed to create todo: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Filtering and Sorting
    
    private func sortTodos() {
        todos.sort { todo1, todo2 in
            // Incomplete todos first
            if todo1.isCompleted != todo2.isCompleted {
                return !todo1.isCompleted && todo2.isCompleted
            }
            
            // Then by due date
            return todo1.dueDate < todo2.dueDate
        }
    }
    
    var upcomingTodos: [TodoItem] {
        let calendar = Calendar.current
        let now = Date()
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
        
        return todos.filter { todo in
            !todo.isCompleted && todo.dueDate <= nextWeek
        }
        .sorted { $0.dueDate < $1.dueDate }
    }
    
    var todayTodos: [TodoItem] {
        todos.filter { $0.isDueToday && !$0.isCompleted }
    }
    
    var overdueTodos: [TodoItem] {
        todos.filter { $0.isOverdue }
    }
    
    var completedTodos: [TodoItem] {
        todos.filter { $0.isCompleted }
    }
    
    func fetchCompletedTodos(for date: Date) -> [TodoItem] {
        let calendar = Calendar.current
        return todos.filter {
            $0.isCompleted && calendar.isDate($0.dueDate, equalTo: date, toGranularity: .month)
        }
    }
    
    // MARK: - Statistics
    
    var totalTodos: Int { todos.count }
    var completedCount: Int { completedTodos.count }
    var pendingCount: Int { todos.count - completedCount }
    var overdueCount: Int { overdueTodos.count }
    
    var completionRate: Double {
        guard totalTodos > 0 else { return 0 }
        return Double(completedCount) / Double(totalTodos)
    }
    
    // MARK: - Notification Management
    
    private func setupNotificationHandling() {
        Task {
            await notificationManager.requestAuthorization()
        }
    }
    
    private func scheduleNotification(for todo: TodoItem, at date: Date) async {
        let content = UNMutableNotificationContent()
        content.title = "Todo Reminder"
        content.body = todo.title
        content.sound = .default
        content.badge = NSNumber(value: pendingCount)
        
        // Add custom data
        content.userInfo = [
            "todoId": todo.id,
            "type": "todoReminder"
        ]
        
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        
        let request = UNNotificationRequest(
            identifier: "todo_\(todo.id)",
            content: content,
            trigger: trigger
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ TodoManager: Scheduled notification for \(todo.title) at \(date)")
        } catch {
            print("❌ TodoManager: Failed to schedule notification: \(error)")
        }
    }
    
    private func cancelNotification(for todoId: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["todo_\(todoId)"])
        print("✅ TodoManager: Cancelled notification for todo \(todoId)")
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Remove completed todos older than 7 days
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        let todosToRemove = todos.filter { todo in
            todo.isCompleted && todo.createdDate < weekAgo
        }
        
        for todo in todosToRemove {
            Task {
                await deleteTodo(todo)
            }
        }
        
        if !todosToRemove.isEmpty {
            print("✅ TodoManager: Cleaned up \(todosToRemove.count) old completed todos")
        }
    }
}