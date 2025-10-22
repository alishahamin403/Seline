import SwiftUI

struct TableCreationDialog: View {
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme

    @State private var rows: Int = 3
    @State private var columns: Int = 3
    @State private var hasHeader: Bool = true

    var onCreate: (NoteTable) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "tablecells")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(
                                    colorScheme == .dark ?
                                        Color(red: 0.40, green: 0.65, blue: 0.80) :
                                        Color(red: 0.20, green: 0.34, blue: 0.40)
                                )

                            Text("Create Table")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Text("Organize your information in a structured format")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Configuration Section
                        VStack(alignment: .leading, spacing: 20) {
                            // Rows Picker
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "arrow.up.and.down")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                    Text("Rows")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                }

                                HStack(spacing: 12) {
                                    Button(action: {
                                        if rows > 1 {
                                            HapticManager.shared.buttonTap()
                                            rows -= 1
                                        }
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(
                                                rows > 1 ?
                                                    (colorScheme == .dark ?
                                                        Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                        Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                                    Color.gray.opacity(0.3)
                                            )
                                    }
                                    .disabled(rows <= 1)

                                    Text("\(rows)")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(minWidth: 60)

                                    Button(action: {
                                        if rows < 20 {
                                            HapticManager.shared.buttonTap()
                                            rows += 1
                                        }
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(
                                                rows < 20 ?
                                                    (colorScheme == .dark ?
                                                        Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                        Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                                    Color.gray.opacity(0.3)
                                            )
                                    }
                                    .disabled(rows >= 20)

                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )

                            // Columns Picker
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "arrow.left.and.right")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                    Text("Columns")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                }

                                HStack(spacing: 12) {
                                    Button(action: {
                                        if columns > 1 {
                                            HapticManager.shared.buttonTap()
                                            columns -= 1
                                        }
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(
                                                columns > 1 ?
                                                    (colorScheme == .dark ?
                                                        Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                        Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                                    Color.gray.opacity(0.3)
                                            )
                                    }
                                    .disabled(columns <= 1)

                                    Text("\(columns)")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(minWidth: 60)

                                    Button(action: {
                                        if columns < 10 {
                                            HapticManager.shared.buttonTap()
                                            columns += 1
                                        }
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(
                                                columns < 10 ?
                                                    (colorScheme == .dark ?
                                                        Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                        Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                                    Color.gray.opacity(0.3)
                                            )
                                    }
                                    .disabled(columns >= 10)

                                    Spacer()
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )

                            // Header Row Toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Header Row")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)

                                    Text("First row will be styled as header")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                }

                                Spacer()

                                Toggle("", isOn: $hasHeader)
                                    .labelsHidden()
                                    .tint(
                                        colorScheme == .dark ?
                                            Color(red: 0.40, green: 0.65, blue: 0.80) :
                                            Color(red: 0.20, green: 0.34, blue: 0.40)
                                    )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )
                        }
                        .padding(.horizontal, 20)

                        // Preview
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Preview")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.horizontal, 20)

                            TablePreview(rows: rows, columns: columns, hasHeader: hasHeader, colorScheme: colorScheme)
                                .padding(.horizontal, 20)
                        }

                        // Action Buttons
                        HStack(spacing: 12) {
                            Button(action: {
                                HapticManager.shared.navigation()
                                isPresented = false
                            }) {
                                Text("Cancel")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    )
                            }

                            Button(action: {
                                HapticManager.shared.save()
                                let table = NoteTable(rows: rows, columns: columns, headerRow: hasHeader)
                                onCreate(table)
                                isPresented = false
                            }) {
                                Text("Create Table")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(
                                                colorScheme == .dark ?
                                                    Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                    Color(red: 0.20, green: 0.34, blue: 0.40)
                                            )
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Table Preview

struct TablePreview: View {
    let rows: Int
    let columns: Int
    let hasHeader: Bool
    let colorScheme: ColorScheme

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { column in
                            cellView(row: row, column: column)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2), lineWidth: 1)
            )
        }
        .frame(maxHeight: 200)
    }

    @ViewBuilder
    private func cellView(row: Int, column: Int) -> some View {
        let isHeader = row == 0 && hasHeader

        Text(isHeader ? "Header \(column + 1)" : "Cell")
            .font(.system(size: 12, weight: isHeader ? .semibold : .regular))
            .foregroundColor(
                isHeader ?
                    (colorScheme == .dark ? Color.white : Color.black) :
                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            )
            .frame(width: 80, height: 40)
            .background(
                isHeader ?
                    (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) :
                    Color.clear
            )
            .overlay(
                Rectangle()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2), lineWidth: 0.5)
            )
    }
}

#Preview {
    TableCreationDialog(isPresented: .constant(true)) { table in
        print("Created table: \(table.rows)x\(table.columns)")
    }
}
