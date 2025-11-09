# Seline LLM Chat Implementation - Complete Documentation Index

This directory contains comprehensive documentation about the Seline app's LLM chat implementation, architecture, and data models.

## Quick Navigation

### Start Here
- **[SELINE_LLM_QUICK_REFERENCE.md](./SELINE_LLM_QUICK_REFERENCE.md)** - Fast lookup guide for developers
  - File locations and responsibilities
  - Data sources summary
  - Configuration reference
  - Common patterns and debugging tips

### In-Depth Documentation
- **[SELINE_LLM_ARCHITECTURE.md](./SELINE_LLM_ARCHITECTURE.md)** - Complete architecture overview
  - Detailed data models with schema
  - Full message flow and data transmission
  - API call formatting and streaming
  - Response parsing and display
  - Data persistence architecture
  - Complete data flow diagram

### Technical Analysis
- **[LLM_CHAT_IMPLEMENTATION.md](./LLM_CHAT_IMPLEMENTATION.md)** - Original detailed analysis
  - OpenAI API implementation
  - Message formatting
  - Context building
  - System prompts
  - Response handling

---

## What is Seline?

Seline is an iOS personal assistant app that integrates conversational AI with multiple data sources:
- Calendar events and tasks
- Notes and folders
- Saved locations (restaurants, places)
- Email inbox
- Weather data
- User preferences

Users can ask natural language questions about their data and the LLM provides intelligent, context-aware answers.

---

## Architecture Overview

```
User Input → SearchService → QueryRouter → Classification
    ↓
    ├─ Question → OpenAIService → buildContextForQuestion()
    │                 ↓
    │            Format & stream OpenAI request
    │                 ↓
    │            Parse SSE chunks in real-time
    │                 ↓
    │            Update UI with streaming response
    │                 ↓
    │            Save to local + cloud storage
    │
    └─ Action → ConversationActionHandler → Multi-turn workflow
```

---

## Key Components

### Core Services
- **OpenAIService** - LLM API client, streaming, context building
- **SearchService** - Entry point, conversation state, history management
- **QueryRouter** - Query classification (question vs action)
- **ConversationActionHandler** - Multi-turn workflows

### UI Components
- **ConversationSearchView** - Chat interface
- **ConversationMessageView** - Message rendering with markdown support

### Data Models
- **ConversationMessage** - Stores messages with intent, timing, and related data
- **QueryIntent** - Categorizes queries (calendar, notes, locations, general)
- **RelatedDataItem** - Links messages to app data

### Data Sources
- **TaskManager** - Calendar events grouped by weekday
- **NotesManager** - Notes with full content, folders, images
- **LocationsManager** - Saved places with geographic metadata
- **EmailService** - Top 10 most recent emails with full body text
- **WeatherService** - Current weather and 6-day forecast
- **UserPreferences** - Navigation locations (home, work, etc)

---

## LLM Configuration

| Parameter | Value |
|-----------|-------|
| Model | gpt-4o-mini |
| Temperature | 0.7 |
| Max Tokens | 500 |
| Base URL | https://api.openai.com/v1/chat/completions |
| Streaming | Enabled (SSE format) |
| Rate Limit | 2 seconds minimum between requests |
| Embedding Model | text-embedding-3-small |

---

## Data Transmission

### What Gets Included in Each Request

1. **System Prompt** - Role definition and formatting instructions
2. **App Context** - Formatted summary of user's data:
   - Current date/time
   - Weather (if available)
   - Navigation destinations
   - All saved locations with metadata
   - Events/tasks (filtered by date)
   - All notes (full content)
   - Top 10 emails (full body text)
3. **Conversation History** - All previous messages in chronological order
4. **Current Query** - User's latest message

### Request Format

```json
{
  "model": "gpt-4o-mini",
  "messages": [
    { "role": "system", "content": "System prompt + app context" },
    { "role": "user", "content": "Previous user message" },
    { "role": "assistant", "content": "Previous assistant response" },
    { "role": "user", "content": "Current user query" }
  ],
  "temperature": 0.7,
  "max_tokens": 500,
  "stream": true
}
```

---

## Query Types Supported

### Single-Domain Queries
- **Calendar**: "What's on my calendar today?"
- **Notes**: "What notes do I have about..."
- **Locations**: "What restaurants have I saved in Toronto?"
- **Email**: "What was in that recent email?"
- **Weather**: "What's the weather like?"

### Multi-Domain Queries
- "I have a meeting tomorrow - what restaurants are near it?"
- "Show me places I've rated highly near my office"
- Intelligently combines multiple data sources

### Features
- Date range detection (today, tomorrow, this week, next week, etc)
- Geographic filtering (country, province, city, category)
- Keyword search across notes, emails, locations
- User ratings and personal notes included
- Full email body text for context

---

## Streaming Implementation

### Server-Sent Events (SSE)

The LLM response streams in real-time chunks:

```
data: {"choices":[{"delta":{"content":"Hello"}}]}
data: {"choices":[{"delta":{"content":" world"}}]}
data: [DONE]
```

### Processing
1. Parse SSE format (lines with "data: " prefix)
2. Extract JSON and get `choices[0].delta.content`
3. Accumulate into buffer
4. Send chunks on word boundaries
5. Detect [DONE] marker for completion
6. Save complete message to history

### UI Updates
- Real-time streaming displayed to user
- Auto-scroll to latest message
- Loading indicator ("Thinking...") while streaming
- Markdown detection and rendering

---

## Data Persistence

### Local Storage
- **UserDefaults** - Device-only storage
- **Timing** - Auto-save during streaming
- **Scope** - Conversation history

### Cloud Storage
- **Supabase** - Cloud database
- **Timing** - On conversation close
- **Data** - Full message history with timestamps
- **Model** - SavedConversation table

---

## Advanced Features

### Intelligent Filtering
- Date range detection from temporal keywords
- Keyword extraction for searching
- Geographic location extraction and filtering
- Category-based organization

### Semantic Search
- Embeddings using text-embedding-3-small model
- Cached for performance
- Cosine similarity matching
- Optional enhancement for context relevance

### Multi-Turn Actions
- Conversational workflows for creating/updating data
- Asks clarifying questions
- Extracts information incrementally
- Confirms changes before saving

### Conversation State
- Tracks topics discussed
- Identifies follow-up questions
- Avoids redundant information
- Provides suggested LLM approach

---

## File Structure

```
Seline/
├── Services/
│   ├── OpenAIService.swift              # LLM core
│   ├── SearchService.swift              # Entry point
│   ├── QueryRouter.swift                # Query classification
│   ├── ConversationActionHandler.swift  # Multi-turn flows
│   ├── TaskManager.swift                # Events
│   ├── NotesManager.swift               # Notes
│   ├── LocationsManager.swift           # Locations
│   ├── EmailService.swift               # Email
│   └── WeatherService.swift             # Weather
│
├── Views/
│   └── ConversationSearchView.swift     # Chat UI
│
├── Models/
│   ├── ConversationModels.swift         # Message models
│   ├── EventModels.swift                # Event/task models
│   ├── NoteModels.swift                 # Note models
│   ├── LocationModels.swift             # Location models
│   └── EmailModels.swift                # Email models
│
└── Documentation/
    ├── SELINE_LLM_ARCHITECTURE.md       # Full architecture
    ├── SELINE_LLM_QUICK_REFERENCE.md    # Quick lookup
    └── LLM_CHAT_IMPLEMENTATION.md       # Technical details
```

---

## Getting Started for Developers

### Understanding the Flow
1. Read **SELINE_LLM_QUICK_REFERENCE.md** for an overview
2. Review the message flow diagram
3. Check the file responsibilities table
4. Look at specific service files mentioned

### Adding New Functionality
1. Check current query types handled
2. Determine if new data source needed
3. Add data source to context builder if needed
4. Update system prompt if new intent
5. Test with sample conversations

### Debugging Issues
1. Check conversation history in SearchService
2. Review context output from buildContextForQuestion()
3. Verify API response parsing in OpenAIService
4. Check SSE streaming in makeOpenAIStreamingRequest()
5. Review QueryRouter classification

### Performance Optimization
- Rate limiting prevents API abuse (2s minimum)
- Max tokens keeps responses focused (500)
- Streaming provides real-time feedback
- Embedding cache reduces API calls
- Date filtering reduces context size

---

## Key Insights

### Unique Aspects
1. **Full Context Access** - LLM gets complete note content, full email bodies, not just snippets
2. **Smart Routing** - Classifies queries intelligently, routes to appropriate handler
3. **Rich Metadata** - Locations include user ratings, geographic info, custom notes
4. **Multi-Turn** - Full conversation history included in every request
5. **Streaming** - Real-time response updates with SSE parsing
6. **State Awareness** - Tracks conversation topics and avoids redundancy

### Best Practices
- Full conversation history enables context-aware responses
- Date filtering reduces token usage
- Markdown formatting improves readability
- Streaming provides responsive UX
- Dual storage (local + cloud) provides redundancy
- Rate limiting controls costs

---

## References

### External Documentation
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference/chat/create)
- [GPT-4o-mini Model Card](https://platform.openai.com/docs/models)
- [Server-Sent Events (SSE)](https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events)

### Internal Files
- Config.swift - API key configuration
- All service classes - Implementation details
- Model files - Data structure definitions

---

## Document Versions

- **SELINE_LLM_ARCHITECTURE.md** - 19KB, created Nov 8 2025
- **SELINE_LLM_QUICK_REFERENCE.md** - 11KB, created Nov 8 2025
- **LLM_CHAT_IMPLEMENTATION.md** - 12KB, existing analysis
- **README_LLM_DOCUMENTATION.md** - This file

---

Last Updated: November 8, 2025
Status: Complete codebase exploration
Next: Implementation planning
