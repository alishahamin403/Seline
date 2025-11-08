# Quick Reference: Action/Event Creation Methods

## Critical Properties to Control

| Property | File | Type | Purpose |
|----------|------|------|---------|
| `pendingEventCreation` | SearchService.swift | `@Published` | Holds event data waiting for confirmation |
| `pendingNoteCreation` | SearchService.swift | `@Published` | Holds note data waiting for confirmation |
| `pendingNoteUpdate` | SearchService.swift | `@Published` | Holds note update data waiting for confirmation |
| `currentInteractiveAction` | SearchService.swift | `@Published` | Current action being built in conversation |
| `actionPrompt` | SearchService.swift | `@Published` | Next prompt to show user |
| `isWaitingForActionResponse` | SearchService.swift | `@Published` | Flag: waiting for user input |
| `pendingMultiActions` | SearchService.swift | `@Published` | Queue of actions to execute |

## Critical Methods to Control

| Method | File | Can Be | Effect |
|--------|------|--------|--------|
| `startConversationalAction()` | SearchService.swift | Commented/Stubbed | Prevents action initiation |
| `continueConversationalAction()` | SearchService.swift | Commented/Stubbed | Prevents action continuation |
| `executeConversationalAction()` | SearchService.swift | Commented/Stubbed | Prevents action execution |
| `confirmEventCreation()` | SearchService.swift | Commented/Stubbed | Prevents event saving |
| `confirmNoteCreation()` | SearchService.swift | Commented/Stubbed | Prevents note saving |
| `confirmNoteUpdate()` | SearchService.swift | Commented/Stubbed | Prevents note update |
| `startAction()` | ConversationActionHandler.swift | Commented/Stubbed | Prevents action initialization |
| `getNextPrompt()` | ConversationActionHandler.swift | Commented/Stubbed | Prevents prompt generation |

## "Want to add more?" Prompt Chain

```
InteractiveNoteBuilder.swift
├── getNextStep(for:) [line 13-41]
│   └── case .askAddMore(currentContent:) [line 36]
│       └── Returns NoteBuilderStep enum case
│
├── getPromptMessage(for:) [line 246]
│   └── Returns "Want to add anything else to this note?"
│
└── processResponse(_:to:action:) [line 206-215]
    └── Checks if user said "yes" to add more
        └── Sets action.extractionState.isShowingSuggestions = true
            Or action.extractionState.isComplete = true
```

## Action Flow Diagram

```
User Query
   ↓
SearchService.performSearch()
   ↓
QueryRouter.classifyQuery() → Returns QueryType.action(ActionType)
   ↓
SearchService.startConversationalAction() ← KEY ENTRY POINT
   ↓
ConversationActionHandler.startAction()
   ↓
InteractiveEventBuilder/InteractiveNoteBuilder.getNextStep()
   ↓
ConversationActionHandler.getNextPrompt()
   ↓
Display prompt to user
   ↓
User responds
   ↓
SearchService.continueConversationalAction()
   ↓
ConversationActionHandler.processUserResponse()
   ↓
Check isReadyToSave()
   ├─ NO → Get next prompt and repeat
   └─ YES → executeConversationalAction()
       ├─ Event: confirmEventCreation()
       ├─ Note: confirmNoteCreation()
       └─ Update: confirmNoteUpdate()
```

## UI Components Displaying Actions

| File | Component | Property Used | Method Called |
|------|-----------|----------------|----------------|
| ConversationSearchView.swift | Pending event view | `pendingEventCreation` | `confirmEventCreation()` |
| ConversationSearchView.swift | Pending note view | `pendingNoteCreation` | `confirmNoteCreation()` |
| ConversationSearchView.swift | Pending update view | `pendingNoteUpdate` | `confirmNoteUpdate()` |
| ConversationSearchView.swift | Action prompts | `actionPrompt` | `continueConversationalAction()` |
| MainAppView.swift | onChange handlers | `pendingEventCreation` | Various |
| MainAppView.swift | onChange handlers | `pendingNoteCreation` | Various |

## Key Enum Values

**ActionType Cases:**
```swift
.createEvent      // Triggers event creation flow
.updateEvent      // Triggers event update flow
.deleteEvent      // Triggers event deletion flow
.createNote       // Triggers note creation flow
.updateNote       // Triggers note update flow
.deleteNote       // Triggers note deletion flow
```

**ExtractionState Flags:**
```swift
isExtracting              // Currently extracting info
isAskingClarifications    // Waiting for clarifications
isShowingSuggestions      // Showing optional suggestions (events)
isConfirming              // Waiting for user confirmation
isComplete                // Ready to save
```

**NoteBuilderStep Cases:**
```swift
.askForTitle              // Ask for note title
.askForContent(...)       // Ask for note content
.askWhichNoteToUpdate     // Ask which note to update
.askWhatToAdd             // Ask what to add to note
.askAddMore(...)          // ← "Want to add more?" prompt
.offerSuggestions(...)    // Show enhancement suggestions
```

## Most Important Files to Watch

1. **SearchService.swift** - Lines 170-280 (Confirmation methods)
2. **SearchService.swift** - Lines 765-929 (Action conversation flow)
3. **ConversationActionHandler.swift** - Lines 55-68 (getNextPrompt entry point)
4. **InteractiveNoteBuilder.swift** - Lines 13-41 (Note building logic)
5. **InteractiveNoteBuilder.swift** - Lines 206-215 ("Want to add more?" handling)

## Disable Strategy (Recommended Order)

1. Stub `SearchService.startConversationalAction()` to do nothing
2. Stub `SearchService.executeConversationalAction()` to do nothing
3. Modify `QueryRouter` to never return `.action()` type
4. Comment out UI components for pending actions in ConversationSearchView
5. Remove `.onChange` handlers in MainAppView
