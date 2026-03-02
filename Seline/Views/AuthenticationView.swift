import SwiftUI
import GoogleSignInSwift

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppAmbientBackgroundLayer(
                    colorScheme: colorScheme,
                    variant: colorScheme == .dark ? .topLeading : .bottomTrailing
                )

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: geometry.size.height * 0.18)

                    VStack(spacing: 40) {
                        Image("SelineLogo")
                            .resizable()
                            .renderingMode(.original)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 136, height: 136)
                            .clipped()

                        VStack(spacing: 12) {
                            Text("Welcome back!")
                                .font(FontManager.geist(size: .extraLarge, weight: .regular))
                                .foregroundColor(Color.appTextPrimary(colorScheme))
                                .multilineTextAlignment(.center)

                            Text("Sign in to continue")
                                .font(.geistTitle3)
                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 28)
                    .appAmbientCardStyle(
                        colorScheme: colorScheme,
                        variant: .topTrailing,
                        cornerRadius: 32,
                        highlightStrength: 0.84
                    )
                    .padding(.horizontal, 20)

                    Spacer()

                    VStack(spacing: 24) {
                        if authManager.isLoading {
                            VStack {
                                ShadcnSpinner(
                                    size: .large,
                                    color: colorScheme == .dark ?
                                        Color(red: 0.64, green: 0.68, blue: 0.73) :
                                        Color(red: 0.37, green: 0.42, blue: 0.48)
                                )
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
                            .padding(.horizontal, 24)
                        } else {
                            Button(action: {
                                Task {
                                    await authManager.signInWithGoogle()
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.geistTitle2)
                                        .foregroundColor(colorScheme == .dark ? .black : .white)

                                    Text("Continue with Google")
                                        .font(.geistButton)
                                        .foregroundColor(colorScheme == .dark ? .black : .white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(colorScheme == .dark ? .white : .black)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .shadow(
                                    color: colorScheme == .dark ?
                                        Color.black.opacity(0.25) :
                                        Color.black.opacity(0.15),
                                    radius: 4,
                                    x: 0,
                                    y: 2
                                )
                            }
                            .padding(.horizontal, 24)
                        }

                        if let errorMessage = authManager.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.geistBody)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 24)
                    .appAmbientCardStyle(
                        colorScheme: colorScheme,
                        variant: .bottomLeading,
                        cornerRadius: 30,
                        highlightStrength: 0.62
                    )
                    .padding(.horizontal, 20)

                    Spacer()
                        .frame(height: geometry.size.height * 0.12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationManager.shared)
}
