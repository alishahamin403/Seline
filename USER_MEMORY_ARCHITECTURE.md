# User Memory System Architecture

## Overview

The User Memory System allows the LLM to remember contextual information about the user across conversations. This solves the problem where users have to re-explain things like "JVM/James = haircuts" every time.

## Architecture

### Database Layer
- **Table**: `user_memory`
- **Types**: entity_relationship, merchant_category, preference, fact, pattern
- **Confidence**: 0.0-1.0 (higher = user explicitly stated)
- **Source**: explicit, inferred, conversation

### Service Layer
- **UserMemoryService**: Manages memory CRUD operations
- **VectorContextBuilder**: Includes memory in LLM context
- **SelineChat**: Extracts memories from conversations

### Flow

1. **Context Building**: Memory is included in every LLM context
2. **Response Processing**: After LLM responds, extract new memories from conversation
3. **Memory Storage**: Store extracted memories with confidence scores

## Memory Types

1. **Entity Relationships**: "JVM" → "haircuts", "James" → "haircuts"
2. **Merchant Categories**: "Starbucks" → "coffee", "JVM" → "haircuts"
3. **Preferences**: "prefers detailed responses", "dislikes emojis"
4. **Facts**: "works 9-5", "commutes by car"
5. **Patterns**: "gym visits usually 1 hour", "dinner usually $50"

## Implementation Steps

1. ✅ Create database migration
2. ✅ Create UserMemoryService
3. ⏳ Integrate into VectorContextBuilder
4. ⏳ Add memory extraction from conversations
5. ⏳ Update system prompt to instruct LLM about memory

## Example Usage

User: "Look at the receipts there should be something with JVM or James named and that was for a haircut"

System extracts:
- entity_relationship: "JVM" → "haircuts" (confidence: 0.9, source: explicit)
- entity_relationship: "James" → "haircuts" (confidence: 0.9, source: explicit)
- merchant_category: "JVM" → "haircuts" (confidence: 0.9, source: explicit)

Next query: "When was my last haircut?"
- LLM sees memory: "JVM → haircuts"
- LLM searches receipts for "JVM" and finds haircut receipts
- No need for user to re-explain!
