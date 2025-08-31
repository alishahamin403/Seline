# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Seline** is a production-ready iOS email client app built with SwiftUI that provides AI-powered email organization and search capabilities. The app connects to Gmail API and uses Google OAuth for authentication, featuring smart categorization of emails (Important, Promotional, Calendar) and advanced search functionality.

## Build System & Commands

### Development Commands
```bash
# Build the project
xcodebuild -project Seline.xcodeproj -scheme Seline -configuration Debug build

# Build for release
xcodebuild -project Seline.xcodeproj -scheme Seline -configuration Release build

# Open in Xcode
open Seline.xcodeproj
```

### Dependencies
The project uses Swift Package Manager for dependencies:
- **GoogleSignIn**: Google OAuth authentication (`https://github.com/google/GoogleSignIn-iOS`)
- **GoogleAPIClientForREST**: Gmail API integration (`https://github.com/googleapis/google-api-objectivec-client-for-rest`)

Dependencies are managed through Xcode's Package Manager (already configured in project.pbxproj).

## Architecture Overview

### Core Architecture Pattern
**Local-First Hybrid Architecture**: Core Data (local storage) + Supabase (cloud sync)

```
Gmail API → Core Data (Local Storage) → Supabase (Cloud Sync) → Real-time Updates
```

### Key Architectural Components

1. **Authentication Layer**: OAuth 2.0 with Google using GoogleSignIn SDK
2. **Data Layer**: Hybrid storage with Core Data for local-first approach and Supabase for cloud sync
3. **Service Layer**: Modular services for different functionalities
4. **UI Layer**: SwiftUI with MVVM pattern using ViewModels

### Directory Structure

```
Seline/
├── SelineApp.swift                 # App entry point with Google OAuth setup
├── Models/                         # Data models
│   └── Email.swift                 # Core email model
├── Services/                       # Business logic and API services
│   ├── AuthenticationService.swift # Google OAuth & auth state management
│   ├── GmailService.swift         # Gmail API integration
│   ├── SupabaseService.swift      # Cloud sync service
│   ├── CalendarService.swift      # Calendar integration
│   └── AISearchService.swift      # AI-powered search
├── ViewModels/                     # MVVM ViewModels
│   └── ContentViewModel.swift     # Main content state management
├── Views/                          # SwiftUI views
│   ├── RootView.swift             # Root navigation controller
│   ├── OnboardingView.swift       # OAuth onboarding flow
│   ├── ContentView.swift          # Main app interface
│   ├── InboxView.swift            # Email list view
│   └── EmailDetailView.swift      # Individual email view
├── Utils/                          # Utilities and helpers
│   ├── DesignSystem.swift         # App design constants
│   ├── AnimationSystem.swift      # Animation utilities
│   └── ProductionLogger.swift     # Production logging
└── CoreData/                       # Core Data stack
    ├── CoreDataManager.swift       # Core Data setup
    └── SelineDataModel.xcdatamodeld # Data model
```

## Authentication & Security

### Google OAuth Configuration
- **GoogleService-Info.plist**: Contains OAuth client configuration
- **URL Schemes**: Configured in Info.plist for OAuth callbacks
- **Scopes**: Gmail readonly, Calendar readonly, User profile

### Required OAuth Scopes
```swift
private let scopes = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/calendar.readonly", 
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile"
]
```

## Data Management

### Core Data Models
- **EmailEntity**: Local email storage with search indexing
- **UserEntity**: User profile and authentication data

### Supabase Integration
- **Cloud Sync**: Background synchronization with conflict resolution
- **Real-time Updates**: Cross-device email updates via subscriptions
- **Security**: Row Level Security (RLS) policies for user data isolation

### Key Services

#### AuthenticationService (`Services/AuthenticationService.swift`)
- Singleton service managing Google OAuth flow
- Persistent authentication state with UserDefaults
- Thread-safe authentication state updates

#### GmailService (`Services/GmailService.swift`) 
- Gmail API integration with quota management
- Email fetching and processing
- Attachment handling

#### SupabaseService (`Services/SupabaseService.swift`)
- Cloud synchronization service
- Real-time subscriptions for cross-device sync
- PostgreSQL full-text search integration

## UI Architecture

### Navigation Flow
1. **RootView**: Determines authentication state and shows appropriate view
2. **OnboardingView**: Google OAuth sign-in flow
3. **ContentView**: Main app interface with bottom tab navigation
4. **Category Views**: InboxView, ImportantEmailsView, PromotionalEmailsView

### Design System
- **DesignSystem.swift**: Centralized colors, fonts, and spacing
- **AnimationSystem.swift**: Consistent animations and transitions
- **Haptic Feedback**: Integrated throughout user interactions

## Development Patterns

### State Management
- `@Published` properties in services for reactive UI updates
- `@EnvironmentObject` for dependency injection
- `@StateObject` for service lifecycle management

### Error Handling
- Production logging with `ProductionLogger`
- Graceful error states in UI
- Comprehensive error handling in all API calls

### Performance Optimization
- Background sync to prevent UI blocking
- Safe array access with bounds checking (`SafeArrayAccess.swift`)
- Memory management with proper cleanup

## Testing & Debugging

### Development Configuration
- **DevelopmentConfiguration.swift**: Development environment setup
- **DEBUG** build configuration for enhanced logging
- **SupabaseIntegrationTest.swift**: Comprehensive integration testing

### Production Considerations
- All debug UI elements removed for production builds
- Console logging optimized with ProductionLogger
- Privacy usage descriptions configured for App Store

## Key Implementation Notes

1. **Thread Safety**: All UI updates are dispatched to main thread using `@MainActor`
2. **OAuth Flow**: Configured for both development and production with proper URL schemes
3. **Data Sync**: Local-first approach ensures offline functionality with background cloud sync
4. **Security**: No hardcoded secrets, OAuth tokens stored securely
5. **Performance**: Optimized for smooth scrolling and responsive interactions
6. **Error Recovery**: Comprehensive error handling with user-friendly error states

## Production Status

The app is **production-ready** and prepared for App Store submission with:
- All compilation errors resolved
- Performance optimized
- Privacy policies configured
- Professional UI polish applied
- Comprehensive testing completed