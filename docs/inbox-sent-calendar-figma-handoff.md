# Seline Figma Handoff: Inbox + Sent + Calendar

This handoff is intended to be dropped into Figma as the source brief for redesigned `Inbox`, `Sent`, and `Calendar` mobile pages that match the approved Seline home-page redesign.

Use this as the design prompt for a new Figma file or for a redesign pass inside an existing file.

## Goal

Design `Inbox`, `Sent`, and `Calendar` so they feel like the same product as the redesigned `Home`, `Locations`, and `People` pages:

- modern
- elegant
- tighter and less boxy
- editorial rather than dashboard-heavy
- monochrome first, with orange only for primary actions or active emphasis

The result should feel denser, calmer, and more intentional than the current stacked-card layouts.

## Shared Design System

Use the approved home page as the visual anchor.

### Core direction

- Background:
  - light: pure white
  - dark: true black / near-black
- Surfaces:
  - one primary surface language only
  - avoid translucent gray glass
  - avoid card-inside-card unless it clearly improves hierarchy
- Accent:
  - use the existing orange only for:
    - compose / add action
    - selected or live emphasis
    - urgent or action-needed state
- Typography:
  - large editorial headlines
  - compact uppercase eyebrow labels
  - quiet supporting copy
- Corners:
  - large outer radius, softer inner radius
- Shadows:
  - minimal, especially in dark mode
- Spacing:
  - dense but breathable
  - reduce dead vertical gaps

### Frame setup

- Create six frames:
  - `Inbox - Light`
  - `Inbox - Dark`
  - `Sent - Light`
  - `Sent - Dark`
  - `Calendar - Light`
  - `Calendar - Dark`
- Frame size:
  - `430 x 932`
- Grid:
  - 4 columns
  - 20 side margin
  - 12 gutter

### Top chrome

Match the new home-page structure:

- left: search capsule or search icon trigger
- middle/right: orange primary action
- far right: utility/profile circle

For email/calendar, keep the top chrome lighter and tighter than the current version.

Search:

- placeholder: `Search`
- no subtitle text
- lighter placeholder styling

Primary actions:

- Inbox / Sent:
  - orange compose button
- Calendar:
  - orange add event button

## Shared Email IA

These pages should feel related:

- `Inbox`
- `Sent`
- `Calendar`

Use one shared segmented navigation row near the top:

- `Inbox`
- `Sent`
- `Calendar`

The selected tab should use the same monochrome pill treatment used elsewhere in the app.

If layout becomes tight, prioritize:

1. segmented control
2. primary action
3. search

## Inbox Page

### Page intent

This page should feel like a communication command center, not a generic mail client.

The hierarchy should be:

1. top chrome
2. inbox hero
3. action-needed / priority summary
4. grouped mail stream
5. compact secondary insights

### Hero module

Replace the current stats-first inbox card with one integrated editorial module.

#### Structure

- eyebrow: `INBOX`
- left side:
  - headline such as `18 messages worth your attention`
  - supporting sentence:
    - example: `Most of today’s mail is concentrated around follow-ups, receipts, and a few action-required threads.`
- right side:
  - compact summary rail:
    - `Today`
    - unread count
    - action-required count

#### Bottom hero actions

Exactly 3 compact buttons:

- `Unread`
- `Action needed`
- `Compose`

Behavior:

- `Unread`: filters or focuses unread mail
- `Action needed`: jumps to the highest-priority queue
- `Compose`: opens compose flow

### Priority strip

Immediately below the hero, add a slim inbox context strip.

This should show:

- one short sentence summarizing the inbox state
- examples:
  - `3 threads are waiting on a reply`
  - `Receipts and confirmations dominate this morning`
  - `Your inbox is quieter than usual today`

Then show 3 compact chips:

- waiting replies
- receipts / promos
- important

### Mail stream

The message list should feel flatter and more editorial.

Section header:

- `Today`
- then `Earlier`

Rows:

- one outer surface only
- divider-separated rows
- avoid heavy boxed email cards
- each row should show:
  - sender
  - subject
  - one clean preview line
  - timestamp
  - subtle unread or priority indicator

Do not show too many badges at once.

### Secondary insight module

Near the bottom, add one tighter summary module:

- eyebrow: `PATTERNS`
- sentence:
  - example: `You usually answer travel and logistics messages first, while newsletters can safely wait.`

This should feel like a quiet assistant observation, not analytics.

### Inbox wireframe

```text
[ Search ]   [+ compose]   [profile]

[ Inbox | Sent | Calendar ]

INBOX                              Today
18 messages worth your             9 unread
attention                          3 action needed
Most of today’s mail is
concentrated around follow-ups,
receipts, and a few priority threads.

[Unread] [Action needed] [Compose]

3 threads are waiting on a reply.
[Reply queue] [Receipts] [Important]

Today
Mom                            Re: dinner plans               9:12
Vision Centre                  Invoice and confirmation       8:44
Amazon                         Your package is arriving       7:52

Earlier
...

PATTERNS
You usually clear personal logistics first, then newsletters later.
```

## Sent Page

### Page intent

This page should feel like a clear record of outgoing communication and follow-through, not a mirrored inbox.

The hierarchy should be:

1. top chrome
2. sent hero
3. follow-up / awaiting reply summary
4. sent stream
5. communication rhythm insight

### Hero module

Make the top card outcome-oriented.

#### Structure

- eyebrow: `SENT`
- left side:
  - headline such as `14 messages you sent this week`
  - supporting sentence:
    - example: `Most of your outgoing messages were personal follow-ups and scheduling replies.`
- right side:
  - compact summary rail:
    - `Today`
    - sent today
    - awaiting reply count

#### Bottom hero actions

Exactly 3 compact buttons:

- `Awaiting reply`
- `Today`
- `Compose`

### Follow-up strip

Immediately below the hero, include one short contextual strip:

- sentence:
  - example: `4 recent messages may still need a response back.`

Then show 3 compact chips:

- awaiting reply
- sent this week
- longest outstanding

### Sent stream

Flatten the list the same way as inbox, but make it more about recipients and outcomes.

Each row should show:

- recipient / thread
- subject
- one concise preview
- sent time / day
- optional subtle state:
  - replied
  - still waiting

Avoid making this look like a spreadsheet of sent mail.

### Secondary insight module

Near the bottom, include one quiet reflective module:

- eyebrow: `FOLLOW-UP`
- example sentence:
  - `You’ve been most responsive in practical conversations, while lower-priority sends tend to sit without follow-up.`

### Sent wireframe

```text
[ Search ]   [+ compose]   [profile]

[ Inbox | Sent | Calendar ]

SENT                               Today
14 messages you sent               3 sent
this week                          4 awaiting reply
Most of your outgoing mail was
personal follow-ups and schedule
coordination.

[Awaiting reply] [Today] [Compose]

4 recent messages may still need a response back.
[Awaiting] [This week] [Longest waiting]

Today
Tasif                         Re: tonight                     6:08
Work thread                   Updated files                   3:24

Earlier
...

FOLLOW-UP
You tend to close logistics quickly and leave low-signal sends open longer.
```

## Calendar Page

### Page intent

This page should feel like a planning surface, not a utilities panel.

The hierarchy should be:

1. top chrome
2. calendar hero
3. month / week / agenda navigation
4. calendar grid or week strip
5. agenda stream

### Hero module

Replace the current top calendar card with one integrated planning hero.

#### Structure

- eyebrow: `CALENDAR`
- left side:
  - headline such as `6 things on deck today`
  - supporting sentence:
    - example: `Your day is light in the morning and busier in the evening, with one synced event and two personal tasks.`
- right side:
  - compact summary rail:
    - selected date
    - events today
    - synced count

#### Bottom hero actions

Exactly 3 compact buttons:

- `Today`
- `Important`
- `Add event`

These should match the new home hero button treatment.

### Calendar navigator

Keep the current calendar functionality, but make the presentation cleaner.

Use a tighter module for:

- month title
- previous / next buttons
- `Today` pill
- calendar grid

The grid should remain the primary planning object, not be buried inside extra containers.

### Agenda section

Below the calendar grid, use a flatter agenda stream.

Section header:

- `Agenda`
- selected date subtitle

Then group events by:

- `All Day`
- `Morning`
- `Afternoon`
- `Evening`

Each event row should show:

- title
- time or `All day`
- small category or source chip
- completion or synced state if relevant

Avoid overly decorative event cards.

### Planning insight strip

Add one quiet supporting strip beneath the calendar or agenda:

- eyebrow: `PACE`
- example:
  - `This day has a calm start and a heavier second half, so it reads better as a planning day than a reactive one.`

### Calendar wireframe

```text
[ Search ]   [+ add]   [profile]

[ Inbox | Sent | Calendar ]

CALENDAR                          Sunday, March 8
6 things on deck today            4 today
Your day is light in the          1 synced
morning and busier in the
evening, with one calendar
event and a few personal tasks.

[Today] [Important] [Add event]

March 2026                  [Today]
[<]                                [>]
S  M  T  W  T  F  S
...

PACE
This day starts calmly and gets denser later, so the afternoon is where most planning pressure sits.

Agenda
Sunday, March 8

Morning
Eye exam                          10:00 AM

Afternoon
Grocery run                       2:00 PM

Evening
Dinner with family                7:00 PM
```

## What to Avoid

Do not design these pages like standard Apple Mail / Google Calendar clones.

Avoid:

- too many nested cards
- tinted gray glass surfaces
- crowded badges and labels on every row
- multiple competing accent colors
- giant empty top padding
- boxed widgets stacked without a clear narrative

## Output Expectation

The final design should feel like one family with:

- Home
- Locations
- People
- Inbox
- Sent
- Calendar

It should preserve Seline’s product identity:

- editorial
- quiet
- monochrome
- dense without feeling cramped
- orange used carefully and intentionally
