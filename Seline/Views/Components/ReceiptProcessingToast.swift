import SwiftUI

// MARK: - Receipt Processing Toast

enum ReceiptProcessingState: Equatable {
    case idle
    case processing
    case success
    case error(String)
}

struct ReceiptProcessingToast: View {
    let state: ReceiptProcessingState
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if state != .idle {
            HStack(spacing: 12) {
                // Status icon
                Group {
                    switch state {
                    case .processing:
                        ProgressView()
                            .tint(colorScheme == .dark ? Color(white: 0.3) : .white)
                            .scaleEffect(0.8)
                    case .success:
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color(white: 0.3) : .white)
                    case .error:
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color(white: 0.3) : .white)
                    case .idle:
                        EmptyView()
                    }
                }
                
                // Status text
                Text(statusText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color(white: 0.3) : .white)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color(white: 0.7) : Color(white: 0.2))
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 20)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state)
        }
    }
    
    private var statusText: String {
        switch state {
        case .idle:
            return ""
        case .processing:
            return "Adding receipt..."
        case .success:
            return "Successfully added!"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    private var iconBackgroundColor: Color {
        switch state {
        case .processing:
            return colorScheme == .dark ? Color.blue.opacity(0.2) : Color.blue.opacity(0.15)
        case .success:
            return Color.green.opacity(0.2)
        case .error:
            return Color.red.opacity(0.2)
        case .idle:
            return .clear
        }
    }
    
    private var iconColor: Color {
        switch state {
        case .processing:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        case .idle:
            return .clear
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ReceiptProcessingToast(state: .processing)
        ReceiptProcessingToast(state: .success)
        ReceiptProcessingToast(state: .error("Failed to process"))
    }
    .padding()
}

