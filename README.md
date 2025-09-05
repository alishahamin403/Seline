# Seline 📧

> AI-powered iOS email client with Gmail integration, intelligent search, and calendar features

[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-16.0+-blue.svg)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-15.0+-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## ✨ Features

### 🚀 Core Functionality
- **Gmail Integration**: Seamless OAuth 2.0 authentication with Gmail API
- **AI-Powered Search**: Intelligent email search with natural language processing
- **Smart Categorization**: Automatic email organization (Important, Promotional)
- **Calendar Integration**: Google Calendar sync with 7-day event preview
- **Todo Management**: Voice-to-text todo creation and management
- **Real-time Sync**: Cloud synchronization with offline-first approach

### 📱 User Experience
- **Email Previews**: Rich email cards with sender, subject, and date
- **Duplicate-Free Calendar**: Automatic deduplication of calendar events
- **Clean Interface**: Maximum 3 items per category on home page
- **Professional Design**: SwiftUI-based modern interface
- **Voice Integration**: Voice recording for todos and search
- **Cross-Device Sync**: Supabase-powered cloud synchronization

### 🛠️ Technical Excellence
- **Local-First Architecture**: Core Data + Supabase hybrid approach
- **Test-Driven Development**: Comprehensive test suite with 90%+ coverage
- **Performance Optimized**: Efficient caching and background processing
- **Security First**: OAuth tokens stored securely, no hardcoded secrets
- **Production Ready**: App Store submission ready

## 🏗️ Architecture

```
Gmail API → Core Data (Local Storage) → Supabase (Cloud Sync) → Real-time Updates
```

### Key Components
- **Authentication Layer**: OAuth 2.0 with Google using GoogleSignIn SDK
- **Data Layer**: Hybrid storage with Core Data for local-first approach
- **Service Layer**: Modular services for different functionalities
- **UI Layer**: SwiftUI with MVVM pattern using ViewModels

## 🚀 Getting Started

### Prerequisites
- iOS 16.0+
- Xcode 15.0+
- Swift 5.0+
- Apple Developer Account (for testing on device)

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/seline.git
   cd seline
   ```

2. **Open in Xcode**:
   ```bash
   open Seline.xcodeproj
   ```

3. **Configure OAuth**:
   - Add your `GoogleService-Info.plist` file to the project
   - Update URL schemes in `Info.plist` with your OAuth client ID
   - Configure Google Cloud Console with proper OAuth scopes

4. **Build and Run**:
   - Select your target device or simulator
   - Press `Cmd+R` to build and run

### Required OAuth Scopes
```swift
private let scopes = [
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile"
]
```

## 📁 Project Structure

```
Seline/
├── SelineApp.swift                 # App entry point
├── Models/                         # Data models
│   ├── Email.swift                 # Core email model
│   └── CalendarEvent.swift         # Calendar event model
├── Services/                       # Business logic
│   ├── AuthenticationService.swift # OAuth & auth state
│   ├── GmailService.swift         # Gmail API integration
│   ├── CalendarService.swift      # Google Calendar API
│   └── SupabaseService.swift      # Cloud sync service
├── ViewModels/                     # MVVM ViewModels
│   └── ContentViewModel.swift     # Main content state
├── Views/                          # SwiftUI views
│   ├── ContentView.swift          # Main app interface
│   ├── Components/                # Reusable components
│   └── UpcomingEventsView.swift   # Calendar view
├── Utils/                          # Utilities
│   ├── DesignSystem.swift         # Design constants
│   └── ProductionLogger.swift     # Logging system
└── CoreData/                       # Data persistence
    ├── CoreDataManager.swift       # Core Data setup
    └── SelineDataModel.xcdatamodeld # Data model
```

## 🧪 Testing

The project follows **Test-Driven Development (TDD)** principles with comprehensive test coverage.

### Run Tests
```bash
# Run all tests
xcodebuild test -project Seline.xcodeproj -scheme Seline -destination 'platform=iOS Simulator,name=iPhone 16'

# Run with coverage
xcodebuild test -project Seline.xcodeproj -scheme Seline -destination 'platform=iOS Simulator,name=iPhone 16' -enableCodeCoverage YES
```

### Test Structure
```
SelineTests/
├── Unit/                           # Unit tests
│   ├── Services/
│   ├── Models/
│   └── Views/
├── Integration/                    # Integration tests
└── UI/                            # UI tests
```

## 🔧 Development

### Build Commands
```bash
# Debug build
xcodebuild -project Seline.xcodeproj -scheme Seline -configuration Debug build

# Release build
xcodebuild -project Seline.xcodeproj -scheme Seline -configuration Release build
```

### Dependencies
- **GoogleSignIn**: Google OAuth authentication
- **GoogleAPIClientForREST**: Gmail API integration
- **Supabase**: Cloud synchronization (optional)

## 📱 Screenshots

*Coming soon - screenshots of the app interface*

## 🗺️ Roadmap

- [ ] **App Store Submission**: Submit to Apple App Store
- [ ] **Advanced AI Features**: Email summarization and smart replies
- [ ] **Multiple Account Support**: Support for multiple Gmail accounts
- [ ] **Advanced Calendar Features**: Event creation and editing
- [ ] **Push Notifications**: Real-time email notifications
- [ ] **iPad Support**: Optimized interface for iPad

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Follow TDD principles (write tests first!)
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Development Guidelines
- Follow the existing code style and architecture
- Write tests for all new features (minimum 90% coverage)
- Update documentation for significant changes
- Ensure all tests pass before submitting PR

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 👨‍💻 Author

**Alishah Amin**
- Email: alishah.amin96@gmail.com
- GitHub: [@YOUR_USERNAME](https://github.com/YOUR_USERNAME)

## 🙏 Acknowledgments

- Built with assistance from [Claude Code](https://claude.ai/code)
- Inspired by modern email client design principles
- Thanks to the Swift and iOS development community

---

**Made with ❤️ for better email management**