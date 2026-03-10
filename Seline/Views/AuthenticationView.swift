import SwiftUI
struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    private let brandMarkSize: CGFloat = 164

    private var brandMarkColor: Color {
        Color.appTextPrimary(colorScheme).opacity(colorScheme == .dark ? 0.94 : 0.9)
    }

    private var signInButtonFill: Color {
        Color.appMonochromeAccentFill(colorScheme)
    }

    private var signInButtonBorder: Color {
        Color.appMonochromeAccentBorder(colorScheme)
    }

    private var signInButtonTextColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.86) : Color.appTextPrimary(colorScheme)
    }

    @ViewBuilder
    private var brandMarkMask: some View {
        let logo = Image("SelineLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: brandMarkSize, height: brandMarkSize)

        if colorScheme == .light {
            logo
                .compositingGroup()
                .colorInvert()
                .luminanceToAlpha()
                .mask(logo)
        } else {
            logo
                .luminanceToAlpha()
        }
    }

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

                    VStack(spacing: 32) {
                        Rectangle()
                            .fill(brandMarkColor)
                            .frame(width: brandMarkSize, height: brandMarkSize)
                            .mask(brandMarkMask)

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

                    VStack(spacing: 18) {
                        if authManager.isLoading {
                            HStack(spacing: 12) {
                                ShadcnSpinner(
                                    size: .medium,
                                    color: colorScheme == .dark ?
                                        Color(red: 0.64, green: 0.68, blue: 0.73) :
                                        Color(red: 0.37, green: 0.42, blue: 0.48)
                                )

                                Text("Signing in")
                                    .font(.geistButton)
                                    .foregroundColor(signInButtonTextColor)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                        } else {
                            Button(action: {
                                Task {
                                    await authManager.signInWithGoogle()
                                }
                            }) {
                                Text("Continue with Google")
                                    .font(.geistButton)
                                    .foregroundColor(signInButtonTextColor)
                                    .tracking(0.1)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(signInButtonFill)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(signInButtonBorder, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        if let errorMessage = authManager.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.geistBody)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .appAmbientCardStyle(
                        colorScheme: colorScheme,
                        variant: .bottomLeading,
                        cornerRadius: 30,
                        highlightStrength: 0.56
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
