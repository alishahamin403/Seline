import SwiftUI
import GoogleSignInSwift

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top spacing - approximately 1/3 of screen
                Spacer()
                    .frame(height: geometry.size.height * 0.25)

                // Logo and Welcome Section
                VStack(spacing: 40) {
                    // Logo positioned above welcome text
                    Image("SelineLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 140, height: 140)

                    // Welcome Section
                    VStack(spacing: 12) {
                        Text("Welcome back!")
                            .font(.geistExtraLarge)
                            .foregroundColor(colorScheme == .dark ?
                                Color(red: 0.95, green: 0.95, blue: 0.96) : // slate-100
                                Color(red: 0.07, green: 0.09, blue: 0.11)   // slate-900
                            )
                            .multilineTextAlignment(.center)

                        Text("Sign in to continue")
                            .font(.geistTitle3)
                            .foregroundColor(colorScheme == .dark ?
                                Color(red: 0.64, green: 0.68, blue: 0.73) : // slate-400
                                Color(red: 0.37, green: 0.42, blue: 0.48)   // slate-600
                            )
                            .multilineTextAlignment(.center)
                    }
                }

                // Flexible spacing between welcome and button
                Spacer()

                // Authentication Section
                VStack(spacing: 24) {
                    if authManager.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(height: 52)
                            .tint(colorScheme == .dark ?
                                Color(red: 0.64, green: 0.68, blue: 0.73) : // slate-400
                                Color(red: 0.37, green: 0.42, blue: 0.48)   // slate-600
                            )
                    } else {
                        // Custom Google Sign-In Button using slate colors
                        Button(action: {
                            Task {
                                await authManager.signInWithGoogle()
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.geistTitle2)
                                    .foregroundColor(colorScheme == .dark ?
                                        Color(red: 0.07, green: 0.09, blue: 0.11) : // slate-900
                                        Color(red: 0.98, green: 0.98, blue: 0.99)   // slate-50
                                    )

                                Text("Continue with Google")
                                    .font(.geistButton)
                                    .foregroundColor(colorScheme == .dark ?
                                        Color(red: 0.07, green: 0.09, blue: 0.11) : // slate-900
                                        Color(red: 0.98, green: 0.98, blue: 0.99)   // slate-50
                                    )
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                colorScheme == .dark ?
                                    Color(red: 0.64, green: 0.68, blue: 0.73) : // slate-400
                                    Color(red: 0.27, green: 0.32, blue: 0.38)   // slate-700
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(
                                color: colorScheme == .dark ?
                                    Color.black.opacity(0.25) :
                                    Color.black.opacity(0.15),
                                radius: 4, x: 0, y: 2
                            )
                        }
                        .padding(.horizontal, 40)
                    }

                    if let errorMessage = authManager.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.geistBody)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.top, 8)
                    }
                }

                // Bottom spacing
                Spacer()
                    .frame(height: geometry.size.height * 0.15)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            colorScheme == .dark ?
                Color.black : // Pure black to match logo background
                Color.white   // Pure white to match home screen
        )
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationManager.shared)
}