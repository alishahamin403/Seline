# Seline

<div align="center">
  <img src="https://img.shields.io/badge/Platform-iOS-lightgrey.svg" alt="Platform: iOS">
  <img src="https://img.shields.io/badge/Swift-5.9-orange.svg" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/SwiftUI-blue.svg" alt="SwiftUI">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT">
</div>

**Seline** is a comprehensive productivity iOS app that unifies your daily essentials — emails, events, notes, maps, and weather — into one beautifully designed interface. Built with SwiftUI and powered by AI, Seline helps you stay organized and productive throughout your day.

---

## ✨ Features

### 📧 Smart Email Management
- **Gmail Integration**: Seamlessly connect your Gmail account with OAuth2 authentication
- **AI-Powered Summaries**: Get intelligent 4-point summaries of your emails using GPT-4o-mini
- **Smart Categorization**: Emails automatically organized by sender with custom icons for popular services
- **Category Filters**: Filter emails by Primary, Social, Promotions, and Updates
- **Mark as Read/Unread**: Quick actions to manage your inbox
- **Unread Email Notifications**: Stay on top of important messages

### 📅 Events & Tasks
- **Weekly Task Management**: Organize tasks by day of the week with a rolling view
- **Event Scheduling**: Create events with specific dates and times
- **Smart Reminders**: Set custom notification times (5min, 30min, 1hr, or custom)
- **Recurring Events**: Support for daily, weekly, monthly, and yearly recurring tasks
- **Task Completion**: Easy checkmark system to track completed tasks
- **Event Details**: View comprehensive event information with edit and delete options

### 📝 Notes with AI Features
- **Rich Text Editing**: Full-featured note editor with formatting support
- **AI Text Enhancement**: Clean up messy text, convert to bullet points, or use custom prompts
- **Receipt Scanning**: Take photos of receipts and extract key information using GPT-4o Vision
- **Folder Organization**: Organize notes into custom folders
- **Pin Important Notes**: Keep critical notes at the top
- **Image Attachments**: Add multiple images to your notes
- **Trash & Recovery**: Deleted notes go to trash with 30-day retention
- **Auto-Save**: Notes automatically save as you type

### 🗺️ Location Services
- **Google Maps Integration**: Search and explore places with detailed information
- **Saved Places**: Save your favorite locations with custom categories
- **Place Details**: View photos, ratings, opening hours, and contact information
- **Directions**: Get directions to any saved location
- **Location Search**: Find nearby restaurants, cafes, shops, and more
- **Custom Categories**: AI-powered categorization of saved places

### 🌤️ Weather Widget
- **Current Weather**: Real-time weather for your location
- **7-Day Forecast**: Plan ahead with weekly weather predictions
- **Detailed Metrics**: Temperature, humidity, wind speed, and more
- **Location-Based**: Automatically updates based on your saved location

### 📰 News Carousel
- **Curated News**: Stay informed with top headlines
- **Multiple Sources**: News from various trusted publishers
- **Image Preview**: Visual news cards for quick browsing
- **Quick Read**: Tap to read full articles

### 🎨 Design & UX
- **Dark Mode Support**: Beautiful dark and light themes
- **Haptic Feedback**: Tactile responses for better user experience
- **Smooth Animations**: Polished transitions and interactions
- **Tab Navigation**: Easy switching between Email, Events, Notes, and Maps
- **Search Everything**: Universal search across all your content
- **Home Dashboard**: Quick overview of emails, events, and pinned notes

---

## 🛠️ Tech Stack

### Frontend
- **SwiftUI**: Modern declarative UI framework
- **UIKit Integration**: For advanced features like image picking

### Backend & Services
- **Supabase**: Backend-as-a-Service for database and authentication
  - PostgreSQL database for tasks, notes, folders, and locations
  - Row Level Security (RLS) for data protection
  - Real-time subscriptions
- **OpenAI API**:
  - GPT-4o-mini for email summaries and text editing
  - GPT-4o Vision for receipt scanning
- **Google APIs**:
  - Gmail API for email access
  - Google Maps API for location services
  - Places API for place details
- **Open-Meteo API**: Weather data

### Key Libraries & Frameworks
- **OAuth2**: Google account authentication
- **Combine**: Reactive programming
- **URLSession**: Network requests
- **UserDefaults**: Local storage
- **NotificationCenter**: Push notifications

---

## 🚀 Getting Started

### Prerequisites
- macOS with Xcode 15.0+
- iOS 17.0+ (deployment target)
- Active Apple Developer account (for device testing)

### Required API Keys
You'll need to obtain API keys from the following services:

1. **OpenAI API Key**: [Get it here](https://platform.openai.com/api-keys)
2. **Google Cloud Platform**:
   - Gmail API credentials
   - Google Maps API key
   - Places API enabled
3. **Supabase Project**: [Create one here](https://supabase.com)

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/alishahamin403/Seline.git
   cd Seline
   ```

2. **Configure API Keys**

   Create your config file from the template:
   ```bash
   cp Seline/Config.swift.template Seline/Config.swift
   ```

   Edit `Seline/Config.swift` and add your OpenAI API key:
   ```swift
   struct Config {
       static let openAIAPIKey = "your-openai-api-key-here"
   }
   ```

3. **Configure Supabase**

   Create `Seline/Services/SupabaseConfig.swift`:
   ```swift
   import Foundation

   struct SupabaseConfig {
       static let supabaseURL = "your-supabase-project-url"
       static let supabaseAnonKey = "your-supabase-anon-key"
   }
   ```

4. **Configure Google Services**

   Update Google API credentials in the respective service files as needed.

5. **Open in Xcode**
   ```bash
   open Seline.xcodeproj
   ```

6. **Build and Run**
   - Select your target device or simulator
   - Press `Cmd + R` to build and run

---

## 📱 App Structure

```
Seline/
├── Models/              # Data models for Email, Events, Notes, Locations, Weather
├── Services/            # Business logic and API integrations
│   ├── AuthenticationManager.swift
│   ├── EmailService.swift
│   ├── GmailAPIClient.swift
│   ├── OpenAIService.swift
│   ├── SupabaseManager.swift
│   ├── WeatherService.swift
│   ├── LocationService.swift
│   ├── GoogleMapsService.swift
│   ├── NewsService.swift
│   ├── NotificationService.swift
│   ├── HapticManager.swift
│   └── NavigationService.swift
├── Views/               # SwiftUI views
│   ├── MainAppView.swift
│   ├── EmailView.swift
│   ├── EventsView.swift
│   ├── NotesView.swift
│   ├── MapsViewNew.swift
│   ├── SettingsView.swift
│   └── Components/      # Reusable UI components
├── Utils/               # Utility classes and extensions
│   ├── ThemeManager.swift
│   └── ImageCacheManager.swift
└── Assets.xcassets/     # Images and colors
```

---

## 🔐 Privacy & Security

- **Local Data**: API keys stored locally and never committed to version control
- **Row Level Security**: Supabase RLS ensures users only access their own data
- **OAuth2**: Secure Google account authentication
- **No Data Sharing**: Your data stays private and is never shared with third parties
- **Secure Storage**: Sensitive tokens stored securely on device

---

## 🎯 Roadmap

- [ ] iCloud sync for notes
- [ ] Apple Calendar integration
- [ ] Email composition and sending
- [ ] Widgets for home screen
- [ ] iPad support
- [ ] Apple Watch companion app
- [ ] Siri shortcuts integration
- [ ] Dark mode customization
- [ ] Export notes as PDF
- [ ] Email attachment support

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the project
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **OpenAI** for GPT-4 API
- **Supabase** for backend infrastructure
- **Google** for Gmail and Maps APIs
- **Open-Meteo** for weather data

---

## 📧 Contact

Ali Shah Amin - [@alishahamin403](https://github.com/alishahamin403)

Project Link: [https://github.com/alishahamin403/Seline](https://github.com/alishahamin403/Seline)

---

<div align="center">
  Made with ❤️ and SwiftUI
</div>
