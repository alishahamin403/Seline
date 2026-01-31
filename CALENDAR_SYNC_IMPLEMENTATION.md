# Calendar Sync Implementation - User Selectable Calendars

## Overview

Implemented a complete calendar sync system that allows users to:
1. ✅ Select specific iPhone calendars to sync (iCloud, Gmail, Exchange, Local, etc.)
2. ✅ Save calendar events to Supabase database
3. ✅ Mark calendar events as complete
4. ✅ Include calendar event data in LLM embeddings and context

## What Was Changed

### 1. Database Schema (`supabase/migrations/20260131000000_add_calendar_sync_fields.sql`)

Added new columns to the `tasks` table:
- `calendar_event_id` - EventKit event identifier from iPhone
- `calendar_identifier` - Calendar identifier (EKCalendar.calendarIdentifier)
- `calendar_title` - Name of the calendar (e.g., "Work", "Personal", "Gmail")
- `calendar_source_type` - Source type (Local, CalDAV, Exchange, Subscribed, Birthdays)
- `is_from_calendar` - Boolean flag indicating if synced from iPhone calendar

**Important:** Run this migration using the Supabase MCP tools before testing!

### 2. Data Models

#### New Models (`Seline/Models/CalendarSyncModels.swift`)
- `CalendarMetadata` - Represents an iPhone calendar with metadata
- `CalendarSourceType` - Enum for calendar source types (iCloud, Gmail, Exchange, etc.)
- `CalendarSyncPreferences` - Stores user's selected calendars in UserDefaults

#### Updated Models
- `TaskItem` (`EventModels.swift`) - Added 4 new calendar-related fields:
  - `calendarEventId`
  - `calendarIdentifier`
  - `calendarTitle`
  - `calendarSourceType`

### 3. Calendar Sync Service (`CalendarSyncService.swift`)

**New Features:**
- `fetchAvailableCalendars()` - Retrieves all iPhone calendars with metadata
- `getSelectedCalendars()` - Gets user's selected calendars from preferences
- Calendar filtering now uses user selections instead of email matching

**Updated Features:**
- `fetchCalendarEventsFromCurrentMonthOnwards()` - Now filters by selected calendars
- `convertEKEventToTaskItem()` - Includes calendar metadata in TaskItem
- Events are now saved to Supabase (removed read-only restriction)

### 4. Calendar Selection UI (`CalendarSelectionView.swift`)

**New SwiftUI View:**
- Shows all available iPhone calendars grouped by source type (iCloud, Gmail, Exchange, Local)
- Displays calendar color indicators
- Shows calendar source information
- Allows multi-select with checkboxes
- "Select All" / "Deselect All" buttons
- Saves preferences to UserDefaults
- Triggers calendar resync on save

**Integrated into Settings:**
- Added "Select Calendars to Sync" button in `SettingsView.swift`
- Opens calendar selection sheet

### 5. Supabase Integration (`EventModels.swift`)

**Updated Functions:**
- `saveTaskToSupabase()` - Removed guard that prevented calendar events from saving
- `updateTaskInSupabase()` - Removed guard that prevented calendar events from updating
- `convertTaskToSupabaseFormat()` - Added calendar fields to Supabase payload
- `parseTaskFromSupabase()` - Added calendar fields parsing from Supabase

**Result:** Calendar events are now fully persisted in Supabase with all metadata

### 6. Embeddings & LLM Context (`VectorSearchService.swift`)

**Updated Task Embeddings:**
- Content now includes: `"Source: iPhone Calendar (Calendar Name) - Source Type"`
- Metadata includes all calendar fields:
  - `calendar_event_id`
  - `calendar_identifier`
  - `calendar_title`
  - `calendar_source_type`
- Completion state is already tracked (`is_completed`, `completed_date`, `completed_dates`)

**Result:** LLM can now see:
- Which calendar an event came from
- Whether calendar events are completed
- Calendar source type (iCloud, Gmail, etc.)

## How It Works

### User Flow

1. **Select Calendars**
   - User opens Settings → "Select Calendars to Sync"
   - Views all available calendars grouped by source
   - Selects/deselects calendars to sync
   - Saves selection

2. **Automatic Sync**
   - Calendar events from selected calendars are synced
   - Events are saved to Supabase with full metadata
   - Events appear in timeline alongside regular tasks

3. **Mark Complete**
   - User can mark calendar events as complete
   - Completion state is saved to Supabase
   - Completion status appears in LLM context

4. **LLM Access**
   - Calendar events are embedded with full metadata
   - LLM can answer questions about calendar events
   - LLM knows which events are completed
   - LLM can distinguish between different calendar sources

### Technical Details

**Calendar Types Supported:**
- **iCloud (CalDAV)** - Personal iCloud calendars
- **Gmail (CalDAV)** - Google Calendar
- **Exchange** - Microsoft Exchange/Office 365
- **Local** - Device-only calendars
- **Subscribed** - Read-only subscribed calendars
- **Birthdays** - System birthdays calendar

**Backward Compatibility:**
- Old email-based filtering still works if no calendars selected
- Existing calendar events are preserved
- Migration is automatic on first use

**Data Sync:**
- Events synced from 3 months in the past to 3 months in the future
- Recurring events tracked with per-date completion
- Deduplication based on `calendar_event_id` + timestamp

## Testing Checklist

Before using, ensure:

1. ✅ Database migration is applied
2. ✅ Calendar permissions are granted
3. ✅ User selects at least one calendar in Settings
4. ✅ Calendar events appear in timeline
5. ✅ Can mark calendar events complete
6. ✅ Completion state persists after app restart
7. ✅ LLM can answer questions about calendar events

## Example Queries After Implementation

The LLM can now answer:
- "What meetings do I have from my work calendar this week?"
- "Show me completed events from my Gmail calendar"
- "What's on my iCloud calendar for tomorrow?"
- "Have I completed my workout from the fitness calendar?"
- "What events are synced from my work Exchange calendar?"

## Files Modified

### New Files
- `supabase/migrations/20260131000000_add_calendar_sync_fields.sql`
- `Seline/Models/CalendarSyncModels.swift`
- `Seline/Views/CalendarSelectionView.swift`

### Modified Files
- `Seline/Models/EventModels.swift`
- `Seline/Services/CalendarSyncService.swift`
- `Seline/Services/VectorSearchService.swift`
- `Seline/Views/SettingsView.swift`

## Notes

- **Migration Required:** The database migration MUST be applied before using this feature
- **Permissions:** Calendar permissions are requested on first access
- **Performance:** Embeddings are only regenerated when calendar content changes
- **Privacy:** Calendar data is encrypted before saving to Supabase
- **Sync Window:** Events from 3 months past to 3 months future are synced

## Next Steps

1. Apply the database migration
2. Test calendar selection UI
3. Verify calendar events sync correctly
4. Test completion tracking
5. Verify LLM can access calendar data in context
