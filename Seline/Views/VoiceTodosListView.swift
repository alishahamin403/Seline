//
//  VoiceTodosListView.swift
//  Seline
//
//  Created by Claude on 2025-08-30.
//

import SwiftUI
import Foundation

struct VoiceTodosListView: View {
    @StateObject private var todoManager = TodoManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editingTodo: TodoItem?
    @State private var showingAddTodo = false
    @State private var selectedFilter: TodoFilter = .active
    
    enum TodoFilter: String, CaseIterable {
        case active = "Active"
        case completed = "Completed"
        case all = "All"
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with filters
                headerSection
                
                // Content
                ScrollView {
                    LazyVStack(spacing: 20) {
                        ForEach(groupedTodos.keys.sorted(), id: \.self) { dateKey in
                            if let todos = groupedTodos[dateKey], !todos.isEmpty {
                                TodoDateSection(
                                    dateKey: dateKey,
                                    todos: todos,
                                    onToggleComplete: { todo in
                                        Task {
                                            await todoManager.toggleCompletion(todo)
                                        }
                                    },
                                    onDelete: { todo in
                                        Task {
                                            await todoManager.deleteTodo(todo)
                                        }
                                    },
                                    onEdit: { todo in
                                        editingTodo = todo
                                    }
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                
                if groupedTodos.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarHidden(true)
            .background(DesignSystem.Colors.background)
            .overlay(
                // Custom navigation bar
                VStack {
                    customNavigationBar
                    Spacer()
                }
            )
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
            AddTodoView { newTodo in
                Task {
                    await todoManager.addTodo(newTodo)
                }
                showingAddTodo = false
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Title
            Text("Voice Todos")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 80)
            
            // Filter tabs
            HStack(spacing: 0) {
                ForEach(TodoFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        selectedFilter = filter
                    }) {
                        VStack(spacing: 8) {
                            Text(filter.rawValue)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(selectedFilter == filter ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                            
                            Rectangle()
                                .fill(selectedFilter == filter ? DesignSystem.Colors.accent : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, 20)
            .background(DesignSystem.Colors.surface)
        }
    }
    
    // MARK: - Custom Navigation Bar
    
    private var customNavigationBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: { showingAddTodo = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background(
            DesignSystem.Colors.background
                .opacity(0.95)
                .blur(radius: 10)
        )
    }
    
    // MARK: - Computed Properties
    
    private var groupedTodos: [String: [TodoItem]] {
        let filteredTodos: [TodoItem]
        
        switch selectedFilter {
        case .active:
            filteredTodos = todoManager.todos.filter { !$0.isCompleted }
        case .completed:
            filteredTodos = todoManager.todos.filter { $0.isCompleted }
        case .all:
            filteredTodos = todoManager.todos
        }
        
        return Dictionary(grouping: filteredTodos) { todo in
            if selectedFilter == .completed && todo.isCompleted {
                // Group completed todos by completion date (we'll use creation date as proxy)
                return formatDateKey(todo.createdDate, prefix: "Completed")
            } else {
                return formatDateKey(todo.dueDate)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDateKey(_ date: Date, prefix: String = "") -> String {
        let calendar = Calendar.current
        let now = Date()
        
        var dateString: String
        
        if calendar.isDateInToday(date) {
            dateString = "Today"
        } else if calendar.isDateInTomorrow(date) {
            dateString = "Tomorrow"
        } else if calendar.isDate(date, equalTo: now.addingTimeInterval(-86400), toGranularity: .day) {
            dateString = "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            dateString = formatter.string(from: date)
        } else if date < now && selectedFilter == .active {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            dateString = "\(formatter.string(from: date)) (Overdue)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            dateString = formatter.string(from: date)
        }
        
        return prefix.isEmpty ? dateString : "\(prefix) \(dateString)"
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(DesignSystem.Colors.primaryGradient)
                    .frame(width: 80, height: 80)
                
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark ? 
                            UIColor.black : UIColor.white
                        })
                    )
            }
            
            VStack(spacing: 12) {
                Text(emptyStateTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(emptyStateMessage)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            
            if selectedFilter == .active {
                Button(action: { showingAddTodo = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Add Todo")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignSystem.Colors.accent)
                    )
                }
            }
        }
        .padding(.horizontal, 40)
    }
    
    private var emptyStateIcon: String {
        switch selectedFilter {
        case .active:
            return "checklist"
        case .completed:
            return "checkmark.circle"
        case .all:
            return "list.bullet"
        }
    }
    
    private var emptyStateTitle: String {
        switch selectedFilter {
        case .active:
            return "No Active Todos"
        case .completed:
            return "No Completed Todos"
        case .all:
            return "No Todos Yet"
        }
    }
    
    private var emptyStateMessage: String {
        switch selectedFilter {
        case .active:
            return "Create your first todo using the voice button or tap the + button above."
        case .completed:
            return "Completed todos will appear here once you finish your tasks."
        case .all:
            return "Start organizing your tasks with voice todos. Tap + to begin."
        }
    }
}

// MARK: - Todo Date Section

struct TodoDateSection: View {
    let dateKey: String
    let todos: [TodoItem]
    let onToggleComplete: (TodoItem) -> Void
    let onDelete: (TodoItem) -> Void
    let onEdit: (TodoItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Date header
            HStack {
                Text(dateKey)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Text("\(todos.count) \(todos.count == 1 ? "item" : "items")")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            // Todo cards
            LazyVStack(spacing: 12) {
                ForEach(todos) { todo in
                    ModernTodoCard(
                        todo: todo,
                        onToggleComplete: { onToggleComplete(todo) },
                        onDelete: { onDelete(todo) },
                        onEdit: { onEdit(todo) }
                    )
                }
            }
        }
    }
}

// MARK: - Modern Todo Card

struct ModernTodoCard: View {
    let todo: TodoItem
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Completion button
            Button(action: onToggleComplete) {
                ZStack {
                    Circle()
                        .stroke(
                            todo.isCompleted ? DesignSystem.Colors.success : DesignSystem.Colors.border,
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                    
                    if todo.isCompleted {
                        Circle()
                            .fill(DesignSystem.Colors.success)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Title and priority
                HStack(spacing: 8) {
                    if todo.priority != .medium {
                        Circle()
                            .fill(priorityColor(todo.priority))
                            .frame(width: 8, height: 8)
                    }
                    
                    Text(todo.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(
                            todo.isCompleted ? 
                            DesignSystem.Colors.textSecondary : 
                            DesignSystem.Colors.textPrimary
                        )
                        .strikethrough(todo.isCompleted)
                        .lineLimit(2)
                    
                    Spacer()
                }
                
                // Description
                if !todo.description.isEmpty && todo.description != todo.title {
                    Text(todo.description)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                        .opacity(todo.isCompleted ? 0.6 : 1.0)
                }
                
                // Due date and status
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(dueDateColor(todo))
                        
                        Text(todo.formattedDueDate)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(dueDateColor(todo))
                    }
                    
                    if todo.priority == .high {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(DesignSystem.Colors.danger)
                            
                            Text("High Priority")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.danger)
                        }
                    }
                    
                    Spacer()
                }
            }
            
            // Actions
            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity) {
            // Long press action
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
    
    private func priorityColor(_ priority: TodoItem.Priority) -> Color {
        switch priority {
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return DesignSystem.Colors.danger
        }
    }
    
    private func dueDateColor(_ todo: TodoItem) -> Color {
        if todo.isCompleted {
            return DesignSystem.Colors.textTertiary
        } else if todo.isOverdue {
            return DesignSystem.Colors.danger
        } else if todo.isDueToday {
            return .orange
        } else {
            return DesignSystem.Colors.textSecondary
        }
    }
}

// MARK: - Previews

struct VoiceTodosListView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceTodosListView()
    }
}