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
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(groupedTodos.keys.sorted(), id: \.self) { dateKey in
                        if let todos = groupedTodos[dateKey], !todos.isEmpty {
                            Section {
                                LazyVStack(spacing: 8) {
                                    ForEach(todos) { todo in
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
                            } header: {
                                HStack {
                                    Text(dateKey)
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                    
                                    Spacer()
                                    
                                    Text("\(todos.count) todo\(todos.count == 1 ? "" : "s")")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(DesignSystem.Colors.surface)
                            }
                            .padding(.bottom, 16)
                        }
                    }
                    
                    if groupedTodos.isEmpty {
                        emptyStateView
                            .padding(.top, 100)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(DesignSystem.Colors.background)
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
                    Text("Voice Todos")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddTodo = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
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
            AddTodoView { newTodo in
                Task {
                    await todoManager.addTodo(newTodo)
                }
                showingAddTodo = false
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var groupedTodos: [String: [TodoItem]] {
        let upcomingTodos = todoManager.todos.filter { !$0.isCompleted }
        
        return Dictionary(grouping: upcomingTodos) { todo in
            formatDateKey(todo.dueDate)
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDateKey(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name (e.g., "Wednesday")
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: now.addingTimeInterval(-86400), toGranularity: .day) {
            return "Yesterday (Overdue)"
        } else if date < now {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d (Overdue)"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Views
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checklist")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Voice Todos")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Tap the + button above to create your first todo, or use voice recording from the main screen")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Previews

struct VoiceTodosListView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceTodosListView()
    }
}