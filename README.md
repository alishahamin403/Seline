# Seline

Seline is an iOS personal intelligence app that brings together notes, journal entries, receipts, email, calendar, locations, people, and AI chat in one place. The app is built around a fast dashboard, grounded retrieval over your personal data, and location-aware context.

## What The App Includes

- Home dashboard with daily focus, spending, and live location context
- Email and calendar views with inbox, sent, focus summaries, and planning flows
- AI chat grounded in your own notes, visits, receipts, emails, people, and events
- Notes, folders, attachments, recurring expenses, and journal workflows
- Maps, saved places, people, and timeline views tied to real visit history
- Widgets, reminders, and notifications for high-signal daily context

## Stack

- SwiftUI app target in `Seline/`
- WidgetKit extension in `SelineWidget/`
- Supabase for auth, storage, sync, and database-backed app state
- Google Sign-In plus Gmail and Contacts integrations
- CoreLocation, MapKit, and EventKit for live location and calendar features
- Gemini-backed retrieval and answer generation over app data

## Repository Layout

- `Seline/`: main iOS app source
- `SelineWidget/`: widget extension source
- `supabase/`: SQL migrations and edge function code
- `docs/`: current design handoff and audit notes worth keeping
- `scripts/`: small repo utilities

## Local Setup

1. Open `Seline.xcodeproj` in Xcode.
2. Provide local config and secrets for your environment.
   Local config is intentionally not treated as portable repo state.
3. Configure Google Sign-In, Supabase, and any API keys required by your local environment.
4. Apply the SQL migrations in `supabase/migrations/`.
5. Deploy the embeddings proxy in `supabase/functions/embeddings-proxy/` if your environment needs backend AI retrieval.

## Backend Notes

- Database migrations live in `supabase/migrations/`
- The embeddings edge function lives in `supabase/functions/embeddings-proxy/index.ts`
- Local app configuration commonly depends on `Seline/Config.swift` and `Seline/Info-Local.plist`

## Kept Docs

The repo was cleaned up to remove historical one-off implementation notes from the root. The docs that remain are the ones that still help with active design and auditing work:

- `docs/inbox-sent-calendar-figma-handoff.md`
- `docs/location-people-figma-handoff.md`
- `docs/location-people-swiftui-mapping.md`
- `docs/performance-audit.md`

## Notes

- iOS deployment target is currently 16.0
- This repo intentionally avoids checking in all local credentials and environment-specific values
