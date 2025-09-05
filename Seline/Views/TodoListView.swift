//
//  TodoListView.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import SwiftUI
import Foundation

struct TodoListView: View {
    @StateObject private var todoManager = TodoManager.shared
    @State private var showingAllTodos = false
    @State private var editingTodo: TodoItem?
    @State private var showingAddTodo = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with close button
                headerView
                
                // Content
                ScrollView {
                    VStack(spacing: 16) {
                        if todoManager.todos.isEmpty {
                            emptyStateView
                        } else {
                            todoItemsView
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationBarHidden(true)
        }
        .fullScreenCover(isPresented: $showingAllTodos) {
            NavigationView {
                AllTodosView()
            }
        }
        .sheet(item: $editingTodo) { todo in
            TodoEditView(todo: todo) { updatedTodo in
                Task {
                    await todoManager.updateTodo(updatedTodo)
                }
                editingTodo = nil
            }
        }
        .sheet(isPresented: $showingAddTodo) {
            AddTodoView { todoItem in
                Task {
                    await todoManager.addTodo(todoItem)
                }
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                    Text("Back")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundColor(DesignSystem.Colors.accent)
            }
            
            Spacer()
            
            Text("Todos")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Spacer()
            
            Button(action: {
                showingAddTodo = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DesignSystem.Colors.background)
    }
    
    // MARK: - Todo Items View
    
    private var todoItemsView: some View {
        LazyVStack(spacing: 0) {
            ForEach(groupedTodos.keys.sorted(), id: \.self) { date in
                if let dayTodos = groupedTodos[date] {
                    daySection(date: date, todos: dayTodos)
                }
            }
        }
    }

    // MARK: - Day Section
    
    private func daySection(date: Date, todos: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                Text(formatSectionDate(date))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Text("\(todos.count) todo\(todos.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.surfaceSecondary)
                    )
            }
            .padding(.top, 20)
            
            // Todos for this day
            VStack(spacing: 12) {
                ForEach(todos.sorted(by: { $0.dueDate < $1.dueDate }), id: \.id) { todo in
                    TodoRow(
                        todo: todo,
                        onToggleComplete: {
                            Task {
                                await todoManager.toggleCompletion(todo)
                            }
                        },
                        onDelete: {
                            Task {
                                await todoManager.deleteTodo(todo)
                            }
                        },
                        onEdit: {
                            editingTodo = todo
                        }
                    )
                }
            }
        }
    }

    // MARK: - Helper Methods
    
    private var groupedTodos: [Date: [TodoItem]] {
        let calendar = Calendar.current
        var grouped: [Date: [TodoItem]] = [:]
        
        for todo in todoManager.todos {
            let dayStart = calendar.startOfDay(for: todo.dueDate)
            if grouped[dayStart] == nil {
                grouped[dayStart] = []
            }
            grouped[dayStart]?.append(todo)
        }
        
        return grouped
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
            
            Text("No todos yet")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Text("Use the voice button to create your first todo")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Todo Row Component

struct TodoRow: View {
    let todo: TodoItem
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Completion Button
            Button(action: onToggleComplete) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(todo.isCompleted ? .green : DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Todo Content
            VStack(alignment: .leading, spacing: 4) {
                // Title with priority indicator
                HStack(spacing: 6) {
                    if todo.priority != .low {
                        Circle()
                            .fill(priorityColor(todo.priority))
                            .frame(width: 6, height: 6)
                    }
                    
                    Text(todo.title)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(todo.isCompleted ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                        .strikethrough(todo.isCompleted)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Due time
                    Text(todo.formattedDueDate)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(dueTimeColor(todo))
                }
                
                // Description (if available and not completed)
                if !todo.description.isEmpty && !todo.isCompleted && todo.description != todo.title {
                    Text(todo.description)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            
            // Action button
            Menu {
                Button("Edit") {
                    onEdit()
                }
                Button(todo.isCompleted ? "Mark Incomplete" : "Complete", action: onToggleComplete)
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    todo.isOverdue && !todo.isCompleted ? 
                    Color.red.opacity(0.5) : 
                    Color.white.opacity(0.3), 
                    lineWidth: 0.5
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
            // Handle long press if needed
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
    
    private func priorityColor(_ priority: TodoItem.Priority) -> Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    private func dueTimeColor(_ todo: TodoItem) -> Color {
        if todo.isOverdue && !todo.isCompleted {
            return .red
        } else if todo.isDueToday && !todo.isCompleted {
            return .orange
        } else {
            return DesignSystem.Colors.textSecondary
        }
    }
}

// MARK: - All Todos View

struct AllTodosView: View {
    @StateObject private var todoManager = TodoManager.shared
    @Environment(\.dismiss) private var dismiss  
    @State private var selectedFilter: TodoFilter = .pending
    @State private var editingTodo: TodoItem?
    @State private var showingVoiceRecording = false
    
    enum TodoFilter: String, CaseIterable {
        case pending = "Pending"
        case completed = "Completed"
        case overdue = "Overdue"
        case all = "All"
    }
    
    var filteredTodos: [TodoItem] {
        switch selectedFilter {
        case .pending:
            return todoManager.todos.filter { !$0.isCompleted }
        case .completed:
            return todoManager.completedTodos
        case .overdue:
            return todoManager.overdueTodos
        case .all:
            return todoManager.todos
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(TodoFilter.allCases, id: \.self) { filter in
                            Button(action: {
                                selectedFilter = filter
                            }) {
                                VStack(spacing: 4) {
                                    Text(filter.rawValue)
                                        .font(.system(size: 16, weight: selectedFilter == filter ? .semibold : .regular, design: .rounded))
                                        .foregroundColor(selectedFilter == filter ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                                    
                                    if selectedFilter == filter {
                                        Rectangle()
                                            .fill(DesignSystem.Colors.accent)
                                            .frame(height: 2)
                                            .transition(.scale)
                                    }
                                }
                                .frame(height: 44)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .background(DesignSystem.Colors.surface)
                
                // Todo List
                if filteredTodos.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredTodos) { todo in
                                TodoRow(
                                    todo: todo,
                                    onToggleComplete: {
                                        Task {
                                            await todoManager.toggleCompletion(todo)
                                        }
                                    },
                                    onDelete: {
                                        Task {
                                            await todoManager.deleteTodo(todo)
                                        }
                                    },
                                    onEdit: {
                                        editingTodo = todo
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            
            ToolbarItem(placement: .principal) {
                Text("My Todos")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingVoiceRecording = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showingVoiceRecording) {
            VoiceRecordingView(todoManager: todoManager)
        }
        .sheet(item: $editingTodo) { todo in
            TodoEditView(todo: todo) { updatedTodo in
                Task {
                    await todoManager.updateTodo(updatedTodo)
                }
                editingTodo = nil
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
            
            Text("No \(selectedFilter.rawValue.lowercased()) todos")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Text("Your \(selectedFilter.rawValue.lowercased()) todos will appear here")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Todo Edit View

struct TodoEditView: View {
    let todo: TodoItem
    let onSave: (TodoItem) -> Void
    
    @State private var title: String
    @State private var description: String
    @State private var dueDate: Date
    @State private var reminderDate: Date?
    @State private var priority: TodoItem.Priority
    @State private var hasReminder: Bool
    @Environment(\.dismiss) private var dismiss
    
    init(todo: TodoItem, onSave: @escaping (TodoItem) -> Void) {
        self.todo = todo
        self.onSave = onSave
        _title = State(initialValue: todo.title)
        _description = State(initialValue: todo.description)
        _dueDate = State(initialValue: todo.dueDate)
        _reminderDate = State(initialValue: todo.reminderDate)
        _priority = State(initialValue: todo.priority)
        _hasReminder = State(initialValue: todo.reminderDate != nil)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Todo Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Due Date") {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Reminder") {
                    Toggle("Set Reminder", isOn: $hasReminder)
                    
                    if hasReminder {
                        DatePicker("Reminder Time", selection: Binding(
                            get: { reminderDate ?? dueDate.addingTimeInterval(-3600) },
                            set: { reminderDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TodoItem.Priority.allCases, id: \.self) { priority in
                            HStack {
                                Circle()
                                    .fill(priorityColor(priority))
                                    .frame(width: 12, height: 12)
                                Text(priority.rawValue)
                            }
                            .tag(priority)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle("Edit Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTodo()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveTodo() {
        let updatedTodo = TodoItem(
            id: todo.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            originalSpeechText: todo.originalSpeechText,
            reminderDate: hasReminder ? reminderDate : nil,
            priority: priority
        )
        
        // Preserve completion status
        var finalTodo = updatedTodo
        finalTodo.isCompleted = todo.isCompleted
        
        onSave(finalTodo)
        dismiss()
    }
    
    private func priorityColor(_ priority: TodoItem.Priority) -> Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}

// MARK: - Previews

struct TodoListView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            TodoListView()
            Spacer()
        }
        .background(DesignSystem.Colors.surface)
    }
}