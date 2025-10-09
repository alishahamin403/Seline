# Seline Setup Guide

This guide will help you set up the Seline app for local development.

## Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ (deployment target)
- Active Apple Developer account (for device testing)

## Step 1: API Keys Configuration

### 1.1 Create Config.swift

Copy the template file and add your API keys:

```bash
cp Seline/Config.swift.template Seline/Config.swift
```

Edit `Seline/Config.swift` and replace the placeholder values:

```swift
struct Config {
    // OpenAI API Key - Get from: https://platform.openai.com/api-keys
    static let openAIAPIKey = "your-actual-openai-api-key"

    // Google APIs - Get from: https://console.cloud.google.com/
    static let googleMapsAPIKey = "your-google-maps-api-key"
    static let googleReversedClientID = "com.googleusercontent.apps.YOUR-CLIENT-ID"

    // OpenWeatherMap API Key - Get from: https://openweathermap.org/api
    static let openWeatherMapAPIKey = "your-openweathermap-api-key"
}
```

### 1.2 Update Info.plist with Your Google Reversed Client ID

⚠️ **IMPORTANT**: You need to update `Seline/Info.plist` with your actual Google Reversed Client ID for OAuth to work.

1. Open `Seline/Info.plist`
2. Find the line with `YOUR_REVERSED_CLIENT_ID_HERE`
3. Replace it with your actual reversed client ID from your `GoogleService-Info.plist`

```xml
<key>CFBundleURLSchemes</key>
<array>
    <string>com.googleusercontent.apps.YOUR-ACTUAL-CLIENT-ID</string>
</array>
```

**Note**: A local copy `Seline/Info-Local.plist` has been created for your convenience with the actual values. You can use this as reference.

### 1.3 Create Supabase Config

Create `Seline/Services/SupabaseConfig.swift`:

```swift
import Foundation

struct SupabaseConfig {
    static let supabaseURL = "https://your-project.supabase.co"
    static let supabaseAnonKey = "your-supabase-anon-key"
}
```

## Step 2: Obtain API Keys

### OpenAI API Key
1. Go to [OpenAI Platform](https://platform.openai.com/api-keys)
2. Sign up or log in
3. Create a new API key
4. Copy the key to `Config.swift`

### Google Cloud APIs

#### Google Maps API
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable these APIs:
   - Places API (New)
   - Maps SDK for iOS
4. Create credentials → API Key
5. Copy to `Config.swift`

#### Google OAuth Client ID
1. In Google Cloud Console → Credentials
2. Create OAuth 2.0 Client ID
3. Select "iOS" as application type
4. Add your bundle identifier: `com.seline.app`
5. Download `GoogleService-Info.plist`
6. Copy the `REVERSED_CLIENT_ID` value
7. Update `Seline/Info.plist` and `Config.swift`

### OpenWeatherMap API
1. Go to [OpenWeatherMap](https://openweathermap.org/api)
2. Sign up for free account
3. Generate API key
4. Copy to `Config.swift`

### Supabase
1. Go to [Supabase](https://supabase.com)
2. Create a new project
3. Get your project URL and anon key from Settings → API
4. Create `SupabaseConfig.swift` with these values

## Step 3: Build and Run

1. Open `Seline.xcodeproj` in Xcode
2. Select your target device or simulator
3. Press `Cmd + R` to build and run

## Security Notes

⚠️ **Never commit the following files to git:**
- `Seline/Config.swift` (your actual API keys)
- `Seline/Services/SupabaseConfig.swift` (your Supabase credentials)
- `Seline/Info-Local.plist` (contains actual Google client ID)

These files are already in `.gitignore` and will not be committed.

## Troubleshooting

### "Config.swift not found"
Make sure you created `Config.swift` from the template:
```bash
cp Seline/Config.swift.template Seline/Config.swift
```

### Google Sign-In not working
1. Verify your `REVERSED_CLIENT_ID` in `Info.plist` matches your `GoogleService-Info.plist`
2. Make sure you've enabled Gmail API in Google Cloud Console
3. Check that your bundle identifier matches in Google Cloud Console

### Supabase connection issues
1. Verify your Supabase URL and anon key in `SupabaseConfig.swift`
2. Check that Row Level Security policies are set up correctly in your Supabase project

## Need Help?

If you encounter any issues, please check:
1. All API keys are correctly copied without extra spaces
2. Google OAuth redirect URI is configured correctly
3. All required APIs are enabled in Google Cloud Console
4. Supabase project is running and accessible
