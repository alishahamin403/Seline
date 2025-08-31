//
//  AnimationSystem.swift
//  Seline
//
//  Created by Alishah Amin on 2025-01-27.
//

import SwiftUI

struct AnimationSystem {
    
    // MARK: - Animation Curves
    struct Curves {
        static let spring = Animation.spring(response: 0.6, dampingFraction: 0.8)
        static let easeInOut = Animation.easeInOut(duration: 0.3)
        static let easeOut = Animation.easeOut(duration: 0.25)
        static let easeIn = Animation.easeIn(duration: 0.2)
        static let smooth = Animation.smooth(duration: 0.4)
        static let bouncy = Animation.bouncy(duration: 0.6)
        static let snappy = Animation.snappy(duration: 0.3)
    }
    
    // MARK: - Transition Effects
    struct Transitions {
        static let slideFromRight = AnyTransition.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
        
        static let slideFromLeft = AnyTransition.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
        
        static let slideFromBottom = AnyTransition.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)
        )
        
        static let scaleAndFade = AnyTransition.scale.combined(with: .opacity)
        
        static let cardFlip = AnyTransition.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 1.1).combined(with: .opacity)
        )
        
        static let modalPresent = AnyTransition.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.95)),
            removal: .move(edge: .bottom).combined(with: .scale(scale: 0.95))
        )
    }
    
    // MARK: - Loading Animations
    struct Loading {
        static func pulsingDot(delay: Double = 0) -> some View {
            Circle()
                .fill(DesignSystem.Colors.accent)
                .frame(width: 8, height: 8)
                .scaleEffect(1.0)
                .animation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(delay),
                    value: UUID()
                )
        }
        
        static func shimmerEffect() -> some View {
            LinearGradient(
                colors: [
                    DesignSystem.Colors.border.opacity(0.3),
                    DesignSystem.Colors.border.opacity(0.7),
                    DesignSystem.Colors.border.opacity(0.3)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .mask(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(70))
                    .offset(x: -200)
                    .animation(
                        Animation.linear(duration: 1.5).repeatForever(autoreverses: false),
                        value: UUID()
                    )
            )
        }
    }
    
    // MARK: - Micro-interactions
    struct MicroInteractions {
        static func buttonPress() -> Animation {
            Animation.easeInOut(duration: 0.1)
        }
        
        static func buttonRelease() -> Animation {
            Animation.spring(response: 0.3, dampingFraction: 0.6)
        }
        
        static func cardHover() -> Animation {
            Animation.easeOut(duration: 0.2)
        }
        
        static func iconBounce() -> Animation {
            Animation.bouncy(duration: 0.4)
        }
        
        static func shimmer() -> Animation {
            Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
        }
    }
}

// MARK: - View Extensions for Animations

extension View {
    func animatedSlideIn(from edge: Edge = .trailing, delay: Double = 0) -> some View {
        self
            .transition(
                .asymmetric(
                    insertion: .move(edge: edge).combined(with: .opacity),
                    removal: .move(edge: edge).combined(with: .opacity)
                )
            )
            .animation(AnimationSystem.Curves.spring.delay(delay), value: UUID())
    }
    
    func animatedScaleIn(delay: Double = 0) -> some View {
        self
            .transition(AnimationSystem.Transitions.scaleAndFade)
            .animation(AnimationSystem.Curves.bouncy.delay(delay), value: UUID())
    }
    
    func pressAnimation() -> some View {
        self.scaleEffect(1.0)
            .animation(AnimationSystem.MicroInteractions.buttonPress(), value: UUID())
    }
    
    func hoverAnimation(isHovered: Bool) -> some View {
        self
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(
                color: isHovered ? DesignSystem.Shadow.medium : DesignSystem.Shadow.light,
                radius: isHovered ? 8 : 4,
                x: 0,
                y: isHovered ? 4 : 2
            )
            .animation(AnimationSystem.MicroInteractions.cardHover(), value: isHovered)
    }
    
    func loadingShimmer() -> some View {
        self.overlay(
            AnimationSystem.Loading.shimmerEffect()
                .blendMode(.overlay)
        )
    }
}

// MARK: - Enhanced Button Styles

struct AnimatedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(
                configuration.isPressed ? 
                AnimationSystem.MicroInteractions.buttonPress() :
                AnimationSystem.MicroInteractions.buttonRelease(),
                value: configuration.isPressed
            )
    }
}

struct FloatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .shadow(
                color: DesignSystem.Shadow.medium,
                radius: configuration.isPressed ? 4 : 8,
                x: 0,
                y: configuration.isPressed ? 2 : 4
            )
            .animation(AnimationSystem.MicroInteractions.buttonPress(), value: configuration.isPressed)
    }
}
