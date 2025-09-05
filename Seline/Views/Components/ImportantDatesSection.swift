//
//  ImportantDatesSection.swift
//  Seline
//
//  Created by Claude on 2025-09-04.
//

import SwiftUI

struct ImportantDatesSection: View {
    let dates: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(DesignSystem.Colors.accent)
                Text("Important Dates")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            ForEach(dates.indices, id: \.self) { index in
                HStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 4, height: 4)
                    
                    Text(dates[index])
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Spacer()
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(DesignSystem.Colors.surface)
        )
    }
}

#Preview {
    ImportantDatesSection(dates: [
        "Meeting tomorrow at 3:00 PM",
        "Conference call on Friday",
        "Project deadline next week"
    ])
    .padding()
}