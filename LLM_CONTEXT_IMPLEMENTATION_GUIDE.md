# LLM Context & Memory Management - Implementation Guide

## Quick Start: Where to Focus

This document provides **exact code locations** and **specific implementation steps** for addressing each issue.

---

## 1. TOKEN COUNTING (High Priority, 2-3 hours)

### What It Does
Counts tokens before sending to API to prevent silent truncation.

### Current Gap
```swift
// OpenAIService.swift:1868 - answerQuestion()
// ❌ PROBLEM: No token counting before API call

var messages: [[String: String]] = [
    ["role": "system", "content": systemPrompt]
]

// Add ALL previous messages without checking token count
for message in conversationHistory {
    messages.append([...])  // Could be 5000+ tokens!
}
```

### Implementation Steps

#### Step 1: Create Token Counter Utility
**File**: Create new `TokenCountingService.swift`

```swift
class TokenCountingService {
    // Rough estimation: 1 token ≈ 4 characters for English
    // More accurate: use actual token counting from OpenAI
    
    static func estimateTokens(_ text: String) -> Int {
        // Simple estimation (good enough for now)
        return (text.count + 3) / 4
    }
    
    // For more accuracy, implement proper tokenization
    // Option 1: Use 'swift-tokenizer' SPM package
    // Option 2: Pre-calculate on known data
    // Option 3: Use OpenAI's token counting API
}
```

#### Step 2: Add Pre-Flight Check
**File**: `OpenAIService.swift:1880` (in answerQuestion)

```swift
func answerQuestion(...) async throws -> String {
    // After buildContextForQuestion()
    let context = buildContextForQuestion(...)
    
    // ✅ ADD THIS:
    let systemPromptTokens = TokenCountingService.estimateTokens(systemPrompt)
    let contextTokens = TokenCountingService.estimateTokens(context)
    let queryTokens = TokenCountingService.estimateTokens(query)
    
    let totalInputTokens = systemPromptTokens + contextTokens + queryTokens
    let reservedForResponse = 500
    let maxInputTokens = 4096 - reservedForResponse
    
    if totalInputTokens > maxInputTokens {
        print("⚠️ Context exceeds limit: \(totalInputTokens) tokens")
        // Handle gracefully - see implementation below
    }
    
    // Continue with API call...
}
```

#### Step 3: Implement Fallback Strategy
When context is too large:

```swift
// Option 1: Filter to last N messages
if totalInputTokens > maxInputTokens {
    // Use only last 20-30 messages instead of all
    let recentMessages = conversationHistory.suffix(20)
    messages = buildMessagesArray(recentMessages)
}

// Option 2: Summarize old messages
if totalInputTokens > maxInputTokens {
    let summary = await summarizeOldMessages()
    // Replace old messages with summary
}

// Option 3: Warn user and proceed anyway (least preferred)
if totalInputTokens > maxInputTokens {
    print("⚠️ WARNING: Context will be truncated by API")
}
```

### Testing
```swift
// Add to unit tests
func testTokenCounting() {
    let text = "Hello world"  // ~3 tokens
    XCTAssertEqual(TokenCountingService.estimateTokens(text), 3)
}

// Test with actual conversation
let conversation = // ... 100 messages
let tokens = TokenCountingService.estimateTokens(conversation)
XCTAssert(tokens < 4096)
```

### Success Criteria
- [ ] Token counting function exists
- [ ] Estimate logs before API call
- [ ] No silent truncations occur
- [ ] Tests pass with various lengths

---

## 2. CONTEXT FILTERING (High Priority, 4 hours)

### What It Does
Keep only relevant messages, prioritize recent ones.

### Current Gap
```swift
// OpenAIService.swift:2008
// ❌ PROBLEM: All messages treated equally

for message in conversationHistory {
    messages.append([
        "role": message.isUser ? "user" : "assistant",
        "content": message.text
    ])
}
// Wastes tokens on old, irrelevant messages
```

### Implementation Steps

#### Step 1: Score Message Relevance
**File**: Create new `MessageRelevanceScorer.swift`

```swift
struct MessageRelevanceScore {
    let messageId: UUID
    let score: Double  // 0.0 to 1.0
    let reason: String
}

class MessageRelevanceScorer {
    func scoreMessage(
        _ message: ConversationMessage,
        againstQuery: String,
        position: Int,
        totalMessages: Int
    ) -> MessageRelevanceScore {
        var score: Double = 0.5  // Base score
        var reasons: [String] = []
        
        // Factor 1: Recency (recent messages more important)
        let recencyRatio = Double(position) / Double(totalMessages)
        score += recencyRatio * 0.3  // Up to +0.3
        reasons.append("Recency: \(Int(recencyRatio * 100))%")
        
        // Factor 2: Semantic similarity to query
        if message.text.lowercased().contains(query.lowercased()) {
            score += 0.2
            reasons.append("Direct mention in query")
        }
        
        // Factor 3: Intent matching
        if let messageIntent = message.intent,
           detectQueryIntent(query) == messageIntent {
            score += 0.15
            reasons.append("Intent match")
        }
        
        // Factor 4: Message length (longer = more info)
        if message.text.count > 100 {
            score += 0.1
            reasons.append("Detailed message")
        }
        
        // Clamp score to 0-1 range
        score = min(1.0, max(0.0, score))
        
        return MessageRelevanceScore(
            messageId: message.id,
            score: score,
            reason: reasons.joined(separator: " | ")
        )
    }
    
    private func detectQueryIntent(_ query: String) -> QueryIntent? {
        // Reuse existing QueryRouter logic
        // or simplified inline detection
        let lower = query.lowercased()
        if lower.contains("event") || lower.contains("meeting") {
            return .calendar
        } else if lower.contains("note") {
            return .notes
        }
        return nil
    }
}
```

#### Step 2: Filter Messages Before API Call
**File**: `OpenAIService.swift` (new method in buildContextForQuestion)

```swift
private func selectRelevantMessages(
    from history: [ConversationMessage],
    query: String,
    maxTokens: Int
) -> [ConversationMessage] {
    let scorer = MessageRelevanceScorer()
    
    // Score all messages
    var scoredMessages: [(message: ConversationMessage, score: Double)] = []
    for (index, message) in history.enumerated() {
        let score = scorer.scoreMessage(
            message,
            againstQuery: query,
            position: index,
            totalMessages: history.count
        )
        scoredMessages.append((message, score.score))
    }
    
    // Sort by relevance score (highest first)
    scoredMessages.sort { $0.score > $1.score }
    
    // Select top messages that fit in token budget
    var selected: [ConversationMessage] = []
    var tokenCount = 0
    let estimatedTokensPerMessage = 50  // Average
    let availableTokens = maxTokens - 500  // Reserve for response
    
    for (message, _) in scoredMessages {
        if tokenCount + estimatedTokensPerMessage <= availableTokens {
            selected.append(message)
            tokenCount += estimatedTokensPerMessage
        } else {
            break
        }
    }
    
    // Restore chronological order for conversation flow
    return selected.sorted { $0.timestamp < $1.timestamp }
}
```

#### Step 3: Use Filtered Messages in answerQuestion
```swift
func answerQuestion(...) async throws -> String {
    let context = buildContextForQuestion(...)
    
    // ✅ ADD THIS:
    let relevantMessages = selectRelevantMessages(
        from: conversationHistory,
        query: query,
        maxTokens: 3500
    )
    
    var messages: [[String: String]] = [
        ["role": "system", "content": systemPrompt]
    ]
    
    // Use filtered messages instead of all
    for message in relevantMessages {
        messages.append([
            "role": message.isUser ? "user" : "assistant",
            "content": message.text
        ])
    }
    
    // Continue...
}
```

### Testing
```swift
func testMessageFiltering() {
    let scorer = MessageRelevanceScorer()
    
    // Test recency boost
    let oldMessage = ConversationMessage(isUser: true, text: "Old")
    let newMessage = ConversationMessage(isUser: true, text: "New")
    
    let oldScore = scorer.scoreMessage(oldMessage, againstQuery: "test", position: 0, totalMessages: 10)
    let newScore = scorer.scoreMessage(newMessage, againstQuery: "test", position: 9, totalMessages: 10)
    
    XCTAssert(newScore.score > oldScore.score)  // Recent should score higher
}
```

### Success Criteria
- [ ] Message relevance scorer implemented
- [ ] Filters prioritize recent messages
- [ ] Only sends ~30-40 most relevant messages
- [ ] Token usage drops 20-30%
- [ ] Response quality maintained or improved

---

## 3. MESSAGE LIMIT (High Priority, 1 hour)

### What It Does
Prevent conversations from growing unbounded.

### Current Gap
```swift
// SearchService.swift:19
@Published var conversationHistory: [ConversationMessage] = []
// ❌ PROBLEM: No size limit - can grow to thousands
```

### Implementation Steps

#### Step 1: Add Limit Configuration
**File**: `SearchService.swift` (at class level)

```swift
class SearchService: ObservableObject {
    // Add this constant
    private let maxMessagesPerConversation = 50
    private let archiveThreshold = 45  // Start archiving when reach 45
    
    // ... rest of class
}
```

#### Step 2: Enforce Limit
**File**: `SearchService.swift` → `addConversationMessage()`

```swift
func addConversationMessage(_ userMessage: String) async {
    // ... existing code to add message ...
    
    conversationHistory.append(userMessage)
    
    // ✅ ADD THIS - Archive old messages if limit exceeded
    if conversationHistory.count > archiveThreshold {
        await archiveOldMessages()
    }
    
    // ... rest of method
}

private func archiveOldMessages() async {
    let messagesToArchive = conversationHistory.prefix(
        conversationHistory.count - maxMessagesPerConversation
    )
    
    for message in messagesToArchive {
        // Option 1: Save to archive with summary
        // Option 2: Delete (less preferable)
        // Option 3: Just keep in cloud, remove from memory
        
        // For now, simple approach:
        conversationHistory.removeFirst()
    }
    
    saveConversationLocally()
}
```

#### Step 3: (Optional) Show User Notice
```swift
private func shouldShowArchiveNotice() -> Bool {
    return conversationHistory.count == archiveThreshold
}

// In UI, show: "Conversation is getting long. Older messages archived."
```

### Success Criteria
- [ ] Conversations capped at 50 active messages
- [ ] Older messages archived
- [ ] No performance degradation
- [ ] Users can still see full history if needed

---

## 4. STORAGE MONITORING (Medium Priority, 30 minutes)

### What It Does
Warn before UserDefaults storage exceeds limits.

### Current Gap
```swift
// SearchService.swift:995
private func saveConversationLocally() {
    let defaults = UserDefaults.standard
    do {
        let encoded = try JSONEncoder().encode(conversationHistory)
        defaults.set(encoded, forKey: "lastConversation")  
        // ❌ PROBLEM: No size checking
    } catch {
        print("❌ Error saving conversation locally: \(error)")
    }
}
```

### Implementation Steps

#### Step 1: Add Size Checking
**File**: `SearchService.swift`

```swift
private func saveConversationLocally() {
    let defaults = UserDefaults.standard
    do {
        let encoded = try JSONEncoder().encode(conversationHistory)
        defaults.set(encoded, forKey: "lastConversation")
        
        // ✅ ADD THIS:
        let sizeInBytes = encoded.count
        let sizeInMB = Double(sizeInBytes) / (1024 * 1024)
        
        print("📊 Conversation saved: \(String(format: "%.2f", sizeInMB)) MB")
        
        // Warn if getting large
        if sizeInMB > 2.0 {
            print("⚠️ WARNING: Conversation size \(String(format: "%.2f", sizeInMB)) MB")
        }
        
        if sizeInMB > 3.5 {
            print("🚨 CRITICAL: Conversation size \(String(format: "%.2f", sizeInMB)) MB - Cleanup recommended")
            // Could trigger UI warning here
        }
        
    } catch {
        print("❌ Error saving conversation locally: \(error)")
    }
}
```

#### Step 2: Add Cleanup Method
```swift
func clearOldConversations() {
    let defaults = UserDefaults.standard
    
    // Clear archived conversations, keep only current
    // Or clear conversations older than 30 days
    
    print("✓ Cleared old conversations")
}
```

### Success Criteria
- [ ] Storage size logged per save
- [ ] Warning at 2 MB
- [ ] Critical alert at 3.5 MB
- [ ] Cleanup function available

---

## 5. CONVERSATION SUMMARIZATION (Medium Priority, 8 hours)

### What It Does
Create summaries of old message groups to preserve context.

### Implementation Roadmap (for later)

```swift
// Pseudocode - implement in Phase 3

class ConversationSummarizer {
    // Detect conversation milestones
    func identifyMilestones(_ messages: [ConversationMessage]) -> [Int] {
        // Find natural break points (topic changes)
    }
    
    // Create summary for a group
    func summarizeMessages(_ messages: [ConversationMessage]) async -> String {
        // Use LLM to create summary of message group
        // "User asked about X, assistant suggested Y, user confirmed Z"
    }
    
    // Store summary with original messages
    struct MessageArchive {
        let summary: String
        let originalMessages: [ConversationMessage]
        let startIndex: Int
        let endIndex: Int
    }
}
```

---

## Integration Checklist

### Phase 1: Token Counting (Week 1)
- [ ] Create `TokenCountingService.swift`
- [ ] Add to `OpenAIService.answerQuestion()`
- [ ] Test with various conversation lengths
- [ ] Commit and merge

### Phase 2: Context Filtering (Week 2)
- [ ] Create `MessageRelevanceScorer.swift`
- [ ] Integrate into `buildContextForQuestion()`
- [ ] Test response quality
- [ ] Measure token savings
- [ ] Commit and merge

### Phase 3: Message Limit (Week 2)
- [ ] Add constants to `SearchService`
- [ ] Implement `archiveOldMessages()`
- [ ] Test with long conversations
- [ ] Commit and merge

### Phase 4: Storage Monitoring (Week 2)
- [ ] Add size tracking
- [ ] Add warnings/alerts
- [ ] Add cleanup function
- [ ] Commit and merge

### Phase 5+: Summarization (Weeks 3-4)
- [ ] Create `ConversationSummarizer`
- [ ] Integrate archiving
- [ ] Test reconstruction
- [ ] Commit and merge

---

## Testing Strategy

### Unit Tests
```swift
// TokenCountingService tests
// MessageRelevanceScorer tests
// Size checking tests
```

### Integration Tests
```swift
// Test with 50+ message conversation
// Test with 100+ message conversation
// Test API calls don't exceed limits
// Test filtering preserves context quality
```

### Manual Tests
1. Create 80-message conversation
2. Verify token counter logs correctly
3. Verify old messages archived
4. Verify responses still accurate
5. Verify storage size reasonable

---

## Performance Impact

### Expected Results After Implementation

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Avg tokens per request | 1500-3200 | 1000-1500 | 2x improvement |
| Safe conversation length | 50 msgs | 200+ msgs | 4x longer |
| Storage per 100 messages | 100 KB | 50 KB | 2x efficient |
| API response time | No change | No change | Same |
| Response quality | Good | Better | More context |

---

## Code Review Checklist

When implementing, verify:
- [ ] No breaking changes to existing API
- [ ] Error handling for edge cases
- [ ] Logging for debugging
- [ ] Performance tested
- [ ] Backward compatible

---

## Next Steps

1. **This week**: Implement Token Counting (Quick Win #1)
2. **Next week**: Implement Context Filtering (Quick Win #2)
3. **Following week**: Message Limit & Storage Monitoring (Quick Wins #3-4)
4. **Weeks 3-4**: Summarization & Full optimization
5. **Week 5**: User-facing improvements & final testing

---

## Resources & References

### Key Files
- `SearchService.swift` - Main orchestration (line 1368)
- `OpenAIService.swift` - API integration (line 2539)
- `ConversationContextService.swift` - Context tracking (line 250)

### OpenAI Token Counting
- Official docs: https://platform.openai.com/docs/guides/tokens
- Python library: `tiktoken` (can use API for iOS)
- Rough rule: 1 token ≈ 4 characters

### Related Issues
- Streaming support ✅ (already working)
- Markdown rendering ✅ (already working)
- Quick suggestions ✅ (already working)

---

**Created**: November 6, 2025
**Status**: Ready for Implementation
**Effort**: 12-16 hours total
**Expected Outcome**: Production-grade context management
