# Email Event Feature

This feature allows users to create events directly from emails, with the email content attached to the event for easy reference.

## Overview

When viewing an email in the app, users can now:
1. Click the "Add Event" button
2. Create an event with customizable date, time, and reminders
3. The email is automatically attached to the event
4. View the attached email details when viewing the event

## Implementation Details

### Database Changes

**New columns added to `tasks` table:**
- `email_id` (TEXT) - Gmail message ID
- `email_subject` (TEXT) - Email subject line
- `email_sender_name` (TEXT) - Sender's display name
- `email_sender_email` (TEXT) - Sender's email address
- `email_snippet` (TEXT) - Email preview text
- `email_timestamp` (TIMESTAMPTZ) - Email received timestamp
- `email_body` (TEXT) - Full email body content
- `email_is_important` (BOOLEAN) - Important flag

### Code Changes

#### 1. TaskItem Model Updates (`EventModels.swift`)
- Added email attachment fields to the `TaskItem` struct
- Added `hasEmailAttachment` computed property
- Updated Supabase sync methods to handle email fields

#### 2. UI Components Created/Updated

**EmailActionButtons.swift:**
- Added `onAddEvent` callback parameter
- Added "Add Event" button with primary styling
- Updated `ActionButtonWithText` to support primary button style

**AddEventFromEmailView.swift (NEW):**
- New view for creating events from emails
- Shows email preview card
- Customizable event details (title, date, time, reminder)
- Automatically attaches email data to created event

**EmailDetailView.swift:**
- Added "Add Event" button to action buttons
- Added sheet presentation for `AddEventFromEmailView`

**ViewEventView.swift:**
- Added attached email section
- Displays email subject, sender, snippet, and timestamp
- Beautiful card-style presentation matching app design

## How to Use

### For Users

1. **Create Event from Email:**
   - Open any email in the app
   - Tap the "Add Event" button
   - Customize the event details (title, date, time, reminder)
   - Tap "Create"

2. **View Attached Email:**
   - Open any event that has an email attached
   - Scroll down to see the "Attached Email" section
   - View email subject, sender, preview, and timestamp

### For Developers

#### Running the Database Migration

1. Go to your Supabase dashboard: https://supabase.com/dashboard
2. Navigate to: Project > SQL Editor
3. Open the file: `supabase_migration_email_attachments.sql`
4. Copy the contents and paste into the SQL Editor
5. Click "Run" to execute the migration

#### Adding Email to an Event Programmatically

```swift
var task = TaskItem(title: "Meeting", weekday: .monday)
task.emailId = email.id
task.emailSubject = email.subject
task.emailSenderName = email.sender.name
task.emailSenderEmail = email.sender.email
task.emailSnippet = email.snippet
task.emailTimestamp = email.timestamp
task.emailBody = email.body
task.emailIsImportant = email.isImportant

taskManager.editTask(task)
```

#### Checking if an Event has an Email Attachment

```swift
if task.hasEmailAttachment {
    print("This event has an email attached!")
    print("Subject: \(task.emailSubject ?? "N/A")")
    print("From: \(task.emailSenderName ?? "N/A")")
}
```

## Design Philosophy

This feature follows the app's minimalist design principles:
- Clean, uncluttered interface
- Consistent color scheme (light/dark mode support)
- Smooth animations and transitions
- Intuitive user flow

## Future Enhancements

Potential improvements for this feature:
1. **Direct Email Opening**: Tap the attached email card to open the full email
2. **Email Threading**: Link multiple events to the same email thread
3. **Smart Suggestions**: Suggest event details based on email content (using AI)
4. **Email Filters**: Filter events by whether they have email attachments
5. **Email Search**: Search events by attached email content
6. **Reply from Event**: Quick reply to the attached email directly from the event view

## Testing

Before deploying, test the following scenarios:

1. ✅ Create event from email with date and time
2. ✅ Create event from email without time
3. ✅ Create event with reminder
4. ✅ View event with attached email
5. ✅ Edit event with attached email (email should persist)
6. ✅ Delete event with attached email
7. ✅ Sync to Supabase (create, update, delete)
8. ✅ Load events with emails from Supabase
9. ✅ Dark mode appearance
10. ✅ Light mode appearance

## Files Modified/Created

### Modified:
- `Seline/Models/EventModels.swift`
- `Seline/Views/Components/EmailActionButtons.swift`
- `Seline/Views/Components/EmailDetailView.swift`
- `Seline/Views/Components/ViewEventView.swift`

### Created:
- `Seline/Views/Components/AddEventFromEmailView.swift`
- `supabase_migration_email_attachments.sql`
- `EMAIL_EVENT_FEATURE.md` (this file)

## Support

If you encounter any issues:
1. Check the Xcode console for error messages
2. Verify the database migration ran successfully
3. Ensure you're using the latest version of the app
4. Contact the development team with detailed error information
