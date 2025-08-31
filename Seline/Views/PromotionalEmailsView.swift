//
//  PromotionalEmailsView.swift
//  Seline
//
//  DEPRECATED: This view has been removed from the app
//  This file can be safely deleted from the project
//

import SwiftUI

// Minimal stub to prevent compilation errors
// This view is no longer used in the app
struct PromotionalEmailsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("This view has been deprecated")
                .foregroundColor(.secondary)
            
            Button("Close") {
                dismiss()
            }
        }
        .navigationTitle("Deprecated")
    }
}

#Preview {
    PromotionalEmailsView()
}