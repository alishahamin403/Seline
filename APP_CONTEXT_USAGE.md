# App Context Service - Simple AI Context Injection

## What It Does

`AppContextService` gives your LLM (OpenAI) access to ALL user app data so it can:
- Understand relationships between events, notes, emails, and locations
- Reference specific items across different parts of the app
- Make intelligent suggestions based on existing data
- Answer questions with full context

## How to Use

### 1. Get Full App Context (for prompts)

```swift
// Must be called from main thread (both methods are @MainActor)
let context = AppContextService.shared.getFullAppContext()

// Use in any prompt:
let prompt = """
You have access to the user's app data:
\(context)

User is asking: "what meetings do I have next week?"
Answer based on the data above.
"""
```

### 2. Get Context for Specific Query

```swift
// Called from main thread
let context = AppContextService.shared.getRelevantContext(for: "Q4 planning")

// Returns only matching events/notes/emails/locations related to "Q4 planning"
// More efficient than full context for targeted queries
```

**Note**: Both methods are `@MainActor` because they access TaskManager and EmailService which are main-thread only. Call them from your UI code or wrap in `Task { @MainActor in ... }` if calling from background.

### 3. Integration Examples

#### In SearchService (async context)
```swift
// When processing a user query, add context:
let query = "create meeting about Q4 planning"
let appContext = await AppContextService.shared.getRelevantContext(for: query)

let enrichedPrompt = """
User query: \(query)

Related items in their app:
\(appContext)

What should the system do?
"""
```

#### In ActionQueryHandler (UI context)
```swift
// When parsing actions, understand the full context:
let eventData = EventCreationData(
    title: "Q4 Planning Meeting",
    date: "2024-11-15"
    // ... etc
)

// Get context to make better suggestions:
let context = AppContextService.shared.getFullAppContext()
// Use this to suggest linking to related notes, emails, etc.
```

#### In Conversation Mode (async context)
```swift
// In OpenAIService.answerQuestion():
let appContext = await AppContextService.shared.getFullAppContext()

let systemPrompt = """
You are a helpful assistant. The user has provided their app data below.
Reference specific items when answering their questions.

User's App Data:
\(appContext)
"""
```

## Data Format

### Full Context Structure

```
**Events & Tasks:**
- [○ TODO] Team Standup
  📅 Nov 15, 2024, 9:00 AM
  📝 Discuss Q4 results
- [✓ DONE] Budget Review
  📅 Nov 14, 2024, 2:00 PM

**Notes:**
- Q4 Planning
  💾 Nov 10, 2024
  Preview: Budget allocation for Q4... (truncated)
- Meeting Notes
  💾 Nov 9, 2024

**Recent Emails:**
- CFO Budget Report
  From: John Smith
  📅 Nov 14, 2024, 3:45 PM
  Summary: Q4 budget breakdown...

**Saved Places:**
- Coffee Shop
  📍 123 Main St, Downtown
  ⭐ 8/10
  Category: Cafes
```

## Why This is Simple & Effective

1. **No Database Schema Changes** - Uses existing managers
2. **No Complex Systems** - Just format and inject data
3. **LLM Handles Relationships** - The model naturally understands connections
4. **Efficient** - Only loads data when needed
5. **Flexible** - Works with any prompt or LLM call

## Key Functions

### `getFullAppContext() -> String`
- Returns ALL events, notes, emails, and locations
- Use when you need complete context
- Good for conversations and questions

### `getRelevantContext(for query: String) -> String`
- Returns only items matching query keywords
- More efficient for targeted actions
- Good for parsing user commands

## Example: Creating Event with Context

```swift
// User: "Create Q4 planning meeting and remind me about the budget items"

// System gets relevant context (from async/main actor context):
let context = await AppContextService.shared.getRelevantContext(for: "Q4 planning budget")

// Returns:
// - Q4 Planning note (with budget details)
// - Budget Review event (already scheduled)
// - CFO Budget Report email

// LLM can now:
// ✓ Create event
// ✓ Link to existing Q4 Planning note
// ✓ Suggest adding budget details from email
// ✓ Schedule follow-up if needed
```

## Example: Answering Questions with Context

```swift
// User: "What's my busiest day next week?"

let fullContext = await AppContextService.shared.getFullAppContext()

// LLM sees:
// - 3 meetings on Tuesday
// - 1 meeting on Wednesday
// - 5 meetings on Thursday

// LLM answers: "Thursday is your busiest day with 5 meetings..."
```

## That's It!

The service is intentionally simple. The power comes from:
1. **You** collecting all the data
2. **AppContextService** formatting it nicely
3. **The LLM** understanding and making connections

No complex relationship engines, no AI detection systems, just give the LLM all the info and let it be smart.
