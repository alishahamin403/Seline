# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Seline** is a production-ready iOS email client app built with SwiftUI that provides AI-powered email organization and search capabilities. The app connects to Gmail API and uses Google OAuth for authentication, featuring smart categorization of emails (Important, Promotional) and advanced search functionality.

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
- **Scopes**: Gmail readonly, User profile

### Required OAuth Scopes
```swift
private let scopes = [
    "https://www.googleapis.com/auth/gmail.readonly",
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

## Test-Driven Development (TDD) - MANDATORY

### 🚨 CRITICAL: Test-First Development Policy

**BEFORE implementing ANY new feature, component, or significant change, Claude MUST follow this TDD workflow:**

#### 1. Write Tests FIRST (Red Phase)
```swift
// Example: Before implementing EmailValidator service
class EmailValidatorTests: XCTestCase {
    func testValidEmailAddress() {
        let validator = EmailValidator()
        XCTAssertTrue(validator.isValid("user@example.com"))
    }
    
    func testInvalidEmailAddress() {
        let validator = EmailValidator()
        XCTAssertFalse(validator.isValid("invalid-email"))
    }
}
```

#### 2. Run Tests to Confirm Failure (Red)
```bash
# Tests should FAIL initially - this confirms they're working
xcodebuild test -project Seline.xcodeproj -scheme Seline -destination 'platform=iOS Simulator'
```

#### 3. Implement Minimum Code (Green Phase)
- Write the simplest code that makes tests pass
- No over-engineering, no extra features

#### 4. Refactor While Tests Pass (Refactor Phase)
- Improve code quality while maintaining test passes
- Add documentation and optimize performance

### Testing Framework & Commands

#### Test Structure
```
SelineTests/
├── Unit/                           # Unit tests for individual components
│   ├── Services/
│   │   ├── AuthenticationServiceTests.swift
│   │   ├── GmailServiceTests.swift
│   │   └── CalendarServiceTests.swift
│   ├── Models/
│   │   ├── EmailTests.swift
│   │   └── CalendarEventTests.swift
│   └── Utils/
│       ├── DesignSystemTests.swift
│       └── EmailFormattersTests.swift
├── Integration/                    # Integration tests
│   ├── OAuthFlowTests.swift
│   ├── EmailSyncTests.swift
│   └── CoreDataIntegrationTests.swift
└── UI/                            # UI and interaction tests
    ├── ContentViewTests.swift
    ├── OnboardingFlowTests.swift
    └── CalendarViewTests.swift
```

#### Test Commands
```bash
# Run all tests
xcodebuild test -project Seline.xcodeproj -scheme Seline -destination 'platform=iOS Simulator,name=iPhone 16'

# Run specific test class
xcodebuild test -project Seline.xcodeproj -scheme Seline -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:SelineTests/EmailServiceTests

# Run tests with coverage report
xcodebuild test -project Seline.xcodeproj -scheme Seline -destination 'platform=iOS Simulator,name=iPhone 16' -enableCodeCoverage YES
```

### Mandatory Testing Requirements

#### For New Services/Components:
1. **Unit Tests**: Test individual methods and edge cases
2. **Mock Dependencies**: Use protocol-based dependency injection for testability
3. **Error Handling Tests**: Test all error conditions and recovery paths
4. **Performance Tests**: For critical paths (email loading, search, sync)

#### For New UI Components:
1. **ViewInspector Tests**: Test SwiftUI view structure and state
2. **Interaction Tests**: Test user interactions and state changes
3. **Accessibility Tests**: Verify VoiceOver and accessibility features
4. **Snapshot Tests**: Visual regression testing for critical views

#### For API Integration:
1. **Network Mocking**: Mock HTTP responses for consistent testing
2. **Error Scenarios**: Test network failures, timeouts, invalid responses
3. **Authentication Tests**: Test OAuth flow, token refresh, logout scenarios
4. **Rate Limiting Tests**: Test API quota and retry logic

### Test Quality Standards

#### Code Coverage Requirements:
- **New Features**: Minimum 90% code coverage
- **Critical Services**: 95% coverage (AuthenticationService, GmailService, CoreDataManager)
- **UI Components**: 80% coverage (focus on business logic, not SwiftUI internals)

#### Test Characteristics:
- **Fast**: Unit tests should run in <50ms each
- **Isolated**: No dependencies on external services, file system, or network
- **Repeatable**: Same results every time, no flaky tests
- **Self-Documenting**: Test names clearly describe what they verify

### TDD Workflow for Claude Code

**When Claude receives a request to add a new feature:**

1. **📋 Create Test Plan**: 
   - Identify what needs to be tested
   - Define test cases covering happy path, edge cases, and error conditions

2. **❌ Write Failing Tests**:
   - Create test files following naming convention: `[ComponentName]Tests.swift`
   - Write comprehensive test cases that FAIL initially
   - Run tests to confirm they fail

3. **✅ Implement Feature**:
   - Write minimal code to make tests pass
   - Follow existing architecture patterns
   - Ensure all tests pass

4. **🔄 Refactor & Improve**:
   - Optimize code while tests remain green
   - Add documentation and improve readability
   - Verify no regressions in existing functionality

5. **📊 Verify Coverage**:
   - Run coverage report to ensure target coverage is met
   - Add additional tests for uncovered scenarios

### Testing Tools & Libraries

#### Available Testing Frameworks:
```swift
import XCTest               // Built-in testing framework
@testable import Seline     // Access internal implementation
```

#### Recommended Testing Patterns:
```swift
// Service testing with dependency injection
protocol EmailServiceProtocol {
    func fetchEmails() async throws -> [Email]
}

class MockEmailService: EmailServiceProtocol {
    var shouldThrowError = false
    var mockEmails: [Email] = []
    
    func fetchEmails() async throws -> [Email] {
        if shouldThrowError {
            throw EmailError.networkError
        }
        return mockEmails
    }
}

// UI testing with ViewInspector
import ViewInspector
extension ContentView: Inspectable { }

class ContentViewTests: XCTestCase {
    func testInitialState() throws {
        let view = ContentView()
        let text = try view.inspect().find(text: "Seline")
        XCTAssertEqual(try text.string(), "Seline")
    }
}
```

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