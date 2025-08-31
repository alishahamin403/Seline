//
//  AddTodoView.swift
//  Seline
//
//  Created by Claude on 2025-08-30.
//

import SwiftUI
import Foundation

struct AddTodoView: View {
    let onSave: (TodoItem) -> Void
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var dueDate: Date = Date().addingTimeInterval(3600) // Default to 1 hour from now
    @State private var reminderDate: Date?
    @State private var priority: TodoItem.Priority = .medium
    @State private var hasReminder: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Todo Details") {
                    TextField("Title", text: $title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .lineLimit(3...6)
                }
                
                Section("Due Date & Time") {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                }
                
                Section("Reminder") {
                    Toggle("Set Reminder", isOn: $hasReminder)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    
                    if hasReminder {
                        DatePicker("Reminder Time", selection: Binding(
                            get: { reminderDate ?? dueDate.addingTimeInterval(-3600) },
                            set: { reminderDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                        .font(.system(size: 14, weight: .regular, design: .rounded))
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
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                            }
                            .tag(priority)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .navigationTitle("Add New Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTodo()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.accent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveTodo() {
        let newTodo = TodoItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            originalSpeechText: "", // Not from voice recording
            reminderDate: hasReminder ? reminderDate : nil,
            priority: priority
        )
        
        onSave(newTodo)
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

struct AddTodoView_Previews: PreviewProvider {
    static var previews: some View {
        AddTodoView { _ in
            // Preview action
        }
    }
}