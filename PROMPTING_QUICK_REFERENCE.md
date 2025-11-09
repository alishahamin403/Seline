# Chain-of-Thought Prompting Quick Reference

## The 4-Step Process

Every LLM prompt now follows this structure:

```
STEP 1: ANALYZE
  └─ What is the user asking?
  └─ Are there ambiguous terms?
  └─ Do you have all needed info?

STEP 2: DISCOVER
  └─ Look through provided data
  └─ Don't rely on pre-made labels
  └─ Find all relevant items

STEP 3: REASON
  └─ Explain your thinking
  └─ State confidence level
  └─ Note any gaps

STEP 4: ANSWER
  └─ Provide natural language answer
  └─ Include specifics from data
  └─ Ask clarifications if needed
```

---

## Prompt Template for Questions

Use this template when querying data:

```markdown
You are a smart assistant. Your job is to answer questions about my personal data.

STEP 1: ANALYZE
Read the user's question and identify:
- What specifically are they asking?
- Is the intent clear or ambiguous?
- Do you need to ask for clarification?

STEP 2: DISCOVER
Look through the provided data:
- Search for all relevant items (don't limit yourself)
- Consider dates, keywords, context, and patterns
- Explain why certain items are relevant or not

STEP 3: REASON
Explain your findings:
- Which data items matched and why
- Any ambiguities or gaps you found
- Your confidence level (0.0-1.0)

STEP 4: ANSWER
Provide your final answer:
- Natural language response
- Specific details from the data
- Ask for clarification if needed

---

THEN provide JSON output:
{
  "thinking": "Brief explanation of what you discovered and why",
  "response": "Your answer to the user",
  "confidence": 0.85,
  "needs_clarification": false,
  "clarifying_questions": []
}

---

CRITICAL RULES:
1. Only use data that was provided to you
2. Show all relevant items, not just the top ones
3. Be honest about gaps or uncertainties
4. Explain your reasoning in the "thinking" field
5. If unsure, ask clarifying questions

User Query: [INSERT USER QUERY HERE]
```

---

## Prompt Template for Information Extraction

Use this when extracting data (creating events, notes, etc.):

```markdown
The user wants to [CREATE/UPDATE/DELETE] a [EVENT/NOTE].

Extract the details from their message.

STEP 1: READ
What is the user describing?
- What is the main content?
- What dates/times are mentioned?
- What context is provided?

STEP 2: DISCOVER
What details are explicit vs. implied?
- Explicit: User said it directly
- Implied: You can infer from context
- Missing: Information you don't have

STEP 3: REASON
Explain what you understand:
- Summarize the [event/note] in your own words
- List what you found and what's missing
- State any assumptions you made

STEP 4: EXTRACT
Provide structured data

---

EXAMPLE REASONING:
User said: "Schedule a meeting with John about Q4 budget on Friday at 2pm"
- Title: Meeting with John - Q4 Budget (combined context + participant)
- Date: Friday = November 14, 2025 (inferred from today's date)
- Time: 14:00 (2pm in 24-hour format)
- Description: Discuss Q4 budget with John (purpose + participant)

---

Conversation History:
[INSERT HISTORY]

Current Message: [INSERT USER MESSAGE]

Extract:
- title: [What should this be called?]
- date: [ISO8601 format: YYYY-MM-DD]
- startTime: [HH:mm format or null]
- description: [What is this about?]

Return JSON: {"title":"...","date":"...","startTime":"...","description":"..."}
```

---

## Key Differences from Old Approach

### Old Way (Pre-Structured)
```
"Give me the coffee app notes"

Backend:
1. Filter notes by "coffee app" keyword
2. Score relevance 0.95
3. Send scored JSON to LLM

LLM sees:
{
  "notes": [
    {"title": "Coffee App", "relevanceScore": 0.95}
  ]
}

LLM thinks: "High score = important. Use this."
Result: Biased by pre-made scoring
```

### New Way (Chain-of-Thought)
```
"Give me the coffee app notes"

Backend:
1. Include ALL notes in the data
2. Send conversation history + raw data

LLM sees:
"Here are all your notes:
- Coffee App - MVP Features
- Project Dashboard
- Team Meeting Notes
- Coffee App - Architecture"

LLM thinks:
"User asked for 'coffee app notes'. Let me look through:
- Coffee App - MVP Features: matches! ✓
- Project Dashboard: doesn't mention coffee app ✗
- Team Meeting Notes: doesn't mention coffee app ✗
- Coffee App - Architecture: matches! ✓

Found 2 matching notes. High confidence."

Result: LLM discovers relevance independently
```

---

## Writing Good Prompts

### ❌ BAD - Forces Structure
```
Extract event info and return this JSON:
{"title":"...", "date":"...", "time":"..."}
```

### ✅ GOOD - Guides Thinking
```
Read the user's message.
What event are they describing?
What details are mentioned?
Explain your understanding.
Then provide the JSON.
```

### ❌ BAD - Pre-Judges Data
```
Here is a note with relevanceScore: 0.95
Use this note to answer the question.
```

### ✅ GOOD - Lets LLM Discover
```
Here are all your notes.
The user asked: [question]
Which notes are relevant and why?
Then provide your answer.
```

---

## Common Patterns

### Pattern 1: Search with Context
```
User Query: "Show me emails from John this month"

System:
1. ANALYZE: Looking for emails from John in November
2. DISCOVER: Scan all emails for sender "John"
3. REASON: Found 3 emails from John
4. ANSWER: Here are John's emails from November...

Confidence: 0.95 (clear sender match + clear time period)
```

### Pattern 2: Clarification Needed
```
User Query: "Show me coffee"

System:
1. ANALYZE: Ambiguous - could mean locations, expenses, notes
2. DISCOVER: Found coffee shops, coffee purchases, coffee notes
3. REASON: Multiple interpretations possible
4. ANSWER: I need clarification...

needs_clarification: true
Questions: ["Do you want coffee locations?", "Or expenses?", "Or notes?"]
Confidence: 0.4 (ambiguous intent)
```

### Pattern 3: Event Creation with Inference
```
User: "Schedule the weekly meeting"

System:
1. READ: User wants weekly meeting, but no specific time
2. DISCOVER: Conversation history mentions "every Monday at 9am"
3. REASON: Inferred Monday 9am from context
4. EXTRACT: Set as weekly recurrence at 9am Monday

Note in thinking: "Inferred from conversation history"
Confidence: 0.75 (some inference needed)
```

---

## Red Flags & Solutions

| Red Flag | Cause | Solution |
|----------|-------|----------|
| confidence < 0.5 | Ambiguous query | Ask clarifying questions |
| Empty "thinking" | LLM skipped reasoning | Increase max_tokens |
| JSON parse error | Reasoning not followed by JSON | Use `extractJSON()` helper |
| Missing context | Incomplete data provided | Add more conversation history |
| Over-matching | LLM too eager to match | Add "be conservative" guidance |

---

## Tuning the Prompts

### For Speed (Fast Responses)
```
// Use compact prompt
Use shorter reasoning
Return just the essential "thinking"
Max tokens: 300
Temperature: 0.0
```

### For Accuracy (Complex Queries)
```
// Use full prompt
Encourage detailed reasoning
Show full thinking process
Max tokens: 500
Temperature: 0.0
```

### For Creativity (Suggestions)
```
// Modify the prompt
Ask "what else might be relevant?"
Explore edge cases
Temperature: 0.3-0.5
```

---

## Testing Your Prompts

### Test 1: Ambiguous Intent
```
Query: "Show me meetings"
Expected: LLM asks for clarification
Check: needs_clarification = true
```

### Test 2: Clear Intent
```
Query: "How much did I spend on pizza in November?"
Expected: Direct answer with confidence 0.9+
Check: thinking explains the logic
```

### Test 3: Multi-Turn Context
```
First: "Schedule a meeting"
Follow-up: "Make it Friday at 2pm"
Expected: LLM remembers the meeting
Check: Uses conversation history for inference
```

### Test 4: Edge Case
```
Query: "Where did I lose my keys?"
Expected: LLM acknowledges data limitation
Check: needs_clarification = true, low confidence
```

---

## Summary

| When | Use | Benefit |
|------|-----|---------|
| Searching data | Full 4-step prompt | Discovers connections |
| Creating items | Reasoning-first extraction | Captures full context |
| Ambiguous queries | Ask for clarification | Prevents wrong assumptions |
| Debug failures | Check "thinking" field | See LLM's logic |
| Quick responses | Compact prompt | Fast but accurate |

The key is: **Let the LLM explain its thinking, don't force it into pre-made categories.**
