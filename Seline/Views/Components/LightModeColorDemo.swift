import SwiftUI

struct LightModeColorDemo: View {
    var body: some View {
        ZStack {
            // Main background (light white)
            Color(white: 0.97)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Text("Option 1: Soft Pastels - Light Mode Demo")
                        .font(FontManager.geist(size: 18, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.top, 16)

                    // Color swatches
                    VStack(spacing: 16) {
                        // New background color
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Card Background")
                                .font(FontManager.geist(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 12)

                            Color(red: 0.98, green: 0.97, blue: 0.95)
                                .frame(height: 60)
                                .cornerRadius(8)
                                .padding(.horizontal, 12)

                            Text("RGB: (0.98, 0.97, 0.95) - Warm off-white")
                                .font(FontManager.geist(size: 10, weight: .regular))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 12)
                        }

                        // Old background color
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Old Card Background (for comparison)")
                                .font(FontManager.geist(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 12)

                            Color.black.opacity(0.05)
                                .frame(height: 60)
                                .cornerRadius(8)
                                .padding(.horizontal, 12)
                                .border(Color.gray.opacity(0.3))

                            Text("RGB: Black at 5% opacity - Too subtle")
                                .font(FontManager.geist(size: 10, weight: .regular))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 12)
                        }
                    }

                    Divider()
                        .padding(.horizontal, 12)

                    // Widget preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Widget Preview")
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)

                        HStack(spacing: 12) {
                            // Spending card
                            VStack(alignment: .leading, spacing: 8) {
                                Text("$2,450.50")
                                    .font(FontManager.geist(size: 20, weight: .bold))
                                    .foregroundColor(Color(white: 0.15))

                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right")
                                        .font(FontManager.geist(size: 10, weight: .semibold))
                                    Text("12% more than last month")
                                        .font(FontManager.geist(size: 10, weight: .regular))
                                }
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))

                                // Category breakdown
                                HStack(spacing: 8) {
                                    Text("🍔")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Food")
                                            .font(FontManager.geist(size: 10, weight: .medium))
                                            .foregroundColor(Color(white: 0.15))
                                        Text("$680.00")
                                            .font(FontManager.geist(size: 9, weight: .regular))
                                            .foregroundColor(Color(white: 0.15).opacity(0.7))
                                    }
                                    Spacer()
                                    Text("28%")
                                        .font(FontManager.geist(size: 10, weight: .semibold))
                                        .foregroundColor(Color(white: 0.15).opacity(0.7))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                                .cornerRadius(6)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(white: 0.99))
                            .cornerRadius(12)

                            // Navigation circles
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "house.fill")
                                            .font(FontManager.geist(size: 14, weight: .semibold))
                                            .foregroundColor(Color(white: 0.15))
                                        Text("12m")
                                            .font(FontManager.geist(size: 9, weight: .semibold))
                                            .foregroundColor(Color(white: 0.15).opacity(0.8))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                                    .cornerRadius(8)

                                    VStack(spacing: 4) {
                                        Image(systemName: "briefcase.fill")
                                            .font(FontManager.geist(size: 14, weight: .semibold))
                                            .foregroundColor(Color(white: 0.15))
                                        Text("28m")
                                            .font(FontManager.geist(size: 9, weight: .semibold))
                                            .foregroundColor(Color(white: 0.15).opacity(0.8))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                                    .cornerRadius(8)
                                }

                                HStack(spacing: 8) {
                                    VStack(spacing: 4) {
                                        Image(systemName: "fork.knife")
                                            .font(FontManager.geist(size: 14, weight: .semibold))
                                            .foregroundColor(Color(white: 0.15))
                                        Text("5m")
                                            .font(FontManager.geist(size: 9, weight: .semibold))
                                            .foregroundColor(Color(white: 0.15).opacity(0.8))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                                    .cornerRadius(8)

                                    VStack(spacing: 4) {
                                        Image(systemName: "dumbbell.fill")
                                            .font(FontManager.geist(size: 14, weight: .semibold))
                                            .foregroundColor(Color(white: 0.15))
                                        Text("--")
                                            .font(FontManager.geist(size: 9, weight: .semibold))
                                            .foregroundColor(Color(white: 0.15).opacity(0.5))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(white: 0.99))
                            .cornerRadius(12)
                        }
                        .frame(height: 130)
                        .padding(.horizontal, 12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why This Works Better")
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(.black)

                        VStack(alignment: .leading, spacing: 6) {
                            Label("Better contrast with white background", systemImage: "checkmark.circle.fill")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))

                            Label("Warm tone feels cohesive & inviting", systemImage: "checkmark.circle.fill")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))

                            Label("Text remains highly readable", systemImage: "checkmark.circle.fill")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))

                            Label("Works well in both light & dark modes", systemImage: "checkmark.circle.fill")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))
                        }
                        .padding(12)
                        .background(Color(red: 0.98, green: 0.97, blue: 0.95))
                        .cornerRadius(8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    LightModeColorDemo()
}
