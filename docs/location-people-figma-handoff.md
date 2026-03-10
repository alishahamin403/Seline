# Seline Figma Handoff: Locations + People

This handoff is intended to be dropped into Figma as the source brief for redesigned `Locations` and `People` mobile pages that match the approved home-page redesign.

Figma MCP was not available in this session, so this file is the exact design brief to use for the Figma build.

## Goal

Design `Locations` and `People` so they feel like the same product as the redesigned `Home` page:

- modern
- elegant
- lighter visual density than the current nested-box layouts
- editorial rather than dashboard-heavy
- monochrome first, with orange only for primary actions or missing/active emphasis

The result should feel tighter, more intentional, and less “card inside card inside card.”

## Shared Design System

Use the approved home page as the visual anchor.

### Core direction

- Background:
  - light: pure white
  - dark: true black / near-black
- Surfaces:
  - one primary page surface language only
  - avoid translucent gray glass
  - avoid stacked inset boxes unless the content truly needs separation
- Accent:
  - use the existing orange only for:
    - primary action button
    - active / live state
    - missing / needs-attention state
- Typography:
  - large editorial headlines
  - compact uppercase eyebrow labels
  - body copy should feel quiet and neutral
- Corners:
  - large outer radius, softer inner radius
- Shadows:
  - minimal, especially in dark mode
- Spacing:
  - dense but breathable
  - reduce dead vertical space

### Frame setup

- Create two frames for each page:
  - `Locations - Light`
  - `Locations - Dark`
  - `People - Light`
  - `People - Dark`
- Frame size:
  - `430 x 932`
- Grid:
  - 4 columns
  - 20 side margin
  - 12 gutter

### Top chrome

Match the new home-page structure:

- left: search capsule
- center/right: orange primary action button
- far right: utility/profile circle

Search field:

- placeholder: `Search`
- smaller, lighter, unbolded placeholder
- no subtitle text

Buttons:

- primary action is orange circle
- secondary utility button is monochrome circle

## Locations Page

### Page intent

This page should feel like a place memory hub, not a settings panel and not a map admin screen.

The hierarchy should be:

1. search + actions
2. editorial hero
3. top places / current context
4. timeline entry point
5. saved places stream

### Top navigation row

Keep the existing segmented IA, but make it cleaner:

- segmented control:
  - `Locations`
  - `People`
  - `Timeline`
- selected tab should use the strong monochrome pill treatment already used elsewhere
- search action remains on the right if the app still needs the dedicated search entry point

If space becomes too crowded, prioritize:

1. segmented control
2. search
3. primary add button

### Hero module

Replace the current boxy stats-first top area with one integrated hero.

#### Structure

- eyebrow: `LOCATIONS`
- left side:
  - headline such as `12 places you return to`
  - one supporting sentence:
    - example: `Most of your recent movement is concentrated between work, home, and a small set of anchor stops.`
- right side:
  - compact period summary rail
  - examples:
    - `This month`
    - `84 visits`
    - `32 hr`

#### Bottom hero actions

Exactly 4 compact buttons, matching the home hero button treatment:

- `Current`
- `Visits`
- `Saved`
- `Timeline`

Behavior:

- `Current`: opens current location / active place context
- `Visits`: focuses recent visit summary
- `Saved`: focuses saved places list
- `Timeline`: jumps into the timeline detail

### Current place strip

Immediately below the hero, include one slim integrated module:

- label: `LIVE` orange capsule when relevant
- current place name large
- one short line:
  - example: `You’ve been moving mostly between Mississauga anchors today.`

Then show 3 compact place pills or mini-cards:

- current place
- most visited recent stop
- most recent new / unusual stop

Each item should feel like a quick access object, not a heavy card.

### Top places section

Replace “top categories + more cards” with a cleaner mixed list.

Section header:

- `Top places`

Section composition:

- 3 ranked rows only
- each row includes:
  - rank number
  - place name
  - category
  - visit count
  - tiny bar or confidence track on the right

This should feel closer to the home spending category rows than to the current nested place cards.

### Saved places stream

Below top places, show a flatter directory.

Section header:

- `Saved places`
- right-side text action: `See all`

Rows:

- one surface only
- divider-separated rows
- each row shows:
  - place name
  - category or folder
  - last visited / visit count
  - favorite marker if applicable

Do not wrap each row in an extra box.

### Timeline entry module

Add a tight bridge module near the bottom:

- eyebrow: `TIMELINE`
- sentence:
  - example: `Open your day-by-day movement history, visit notes, receipts, and people connections.`
- one primary monochrome button:
  - `Open timeline`

### Locations wireframe

```text
[ Search            ]   [+]   [profile]

[ Locations | People | Timeline ]

LOCATIONS                          This month
12 places you return to            84 visits
Most of your recent movement       32 hr
is concentrated between work,
home, and a few anchor stops.

[Current] [Visits] [Saved] [Timeline]

LIVE
Ace Hotel Toronto
You’ve been moving mostly between downtown anchors today.
[Ace Hotel] [Tim Hortons] [Union]

Top places
01  Ace Hotel Toronto          Hotel / Downtown      18
02  Tim Hortons                Coffee                11
03  Union Station              Transit                8

Saved places                                   See all
Ace Hotel Toronto
Downtown • 18 visits
-----------------------------------------------
Tim Hortons
Coffee • 11 visits
-----------------------------------------------
...

TIMELINE
Open your day-by-day movement history, visit notes,
receipts, and people connections.
[ Open timeline ]
```

## People Page

### Page intent

This page should feel like a relationship hub, not a CRM and not a card grid.

The page should emphasize:

- people you care about
- recent relationship activity
- fast category filtering
- cleaner directory browsing

### Hero module

Keep the page title, but reduce redundant summary text.

#### Structure

- eyebrow: `PEOPLE`
- large title:
  - `People`
- short supporting sentence:
  - example: `Your close circle, family, and important connections in one place.`
- right-side actions:
  - import contacts
  - add person

Then include 3 compact metrics on a single row:

- `Total`
- `Favorites`
- `Birthdays soon`

These should match the home page stat treatment.

### Favorites strip

Keep this, but make it more premium and less chunky.

- horizontal row
- avatar + name + relationship
- lower visual weight
- one shared parent surface, not separated boxed chips

### Relationship section redesign

Use the flatter direction already chosen in the app review.

#### Structure

- section header: `Relationship`
- filter chips:
  - `All`
  - `Family`
  - `Close Friend`
  - `Friend`
  - `Coworker`
  - etc

Below that:

- one continuous grouped list
- group header text only, not an inner card
- divider-separated rows under each group

Each row:

- avatar
- name
- one secondary line:
  - `Updated 4 hrs ago`
  - or `Seen at Meadowvale Jamatkhana`
- favorite star on the right if applicable
- chevron for drill-in

No nested card around each group.
No card around each person row.
Only the outer section surface and thin dividers.

### Recent relationship activity module

Add a small editorial section beneath the directory header or after the first group:

- header: `Recent activity`
- 3 event rows max
- examples:
  - `Dad was linked to 2 visits this week`
  - `Agithan was updated today`
  - `Mom has a birthday coming up in 6 days`

This helps the page feel alive without becoming analytics-heavy.

### Empty states

If there are no people:

- keep one elegant starter module
- sentence:
  - `Save the people you care about, then connect them to places, visits, and notes.`
- actions:
  - `Add person`
  - `Import contacts`

### People wireframe

```text
[ Search            ]   [+]   [profile]

[ Locations | People | Timeline ]

PEOPLE
People
Your close circle, family, and important
connections in one place.
                    [import] [+]

[Total] [Favorites] [Birthdays soon]

Favourites
[avatar name role] [avatar name role] [avatar name role]

Relationship
[All] [Family] [Close Friend] [Friend] [Coworker]

Recent activity
Dad was linked to 2 visits this week
Agithan was updated today
Mom has a birthday in 6 days

Family                                              2
[avatar] Dad                        Updated 4 hrs ago     >
----------------------------------------------------------
[avatar] Mom                        Updated 3 hrs ago     >

Close Friend                                        5
[avatar] Agithan Amur              Seen today            >
----------------------------------------------------------
[avatar] ...
```

## Component Mapping to Existing SwiftUI

These designs are intended to map onto the current app structure:

- `Locations / People / Timeline` shell:
  - `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MapsViewNew.swift`
- `People` page:
  - `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/Components/PeopleListView.swift`
- `Timeline` page:
  - `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/LocationTimelineView.swift`

## Figma Build Notes

### Component naming

Use these component names in Figma:

- `TopChrome/SearchBar`
- `TopChrome/PrimaryAction`
- `TopChrome/ProfileButton`
- `SegmentedTabs/Hub`
- `Card/Hero`
- `Card/Section`
- `Row/MetricTile`
- `Row/PlaceRank`
- `Row/PersonDirectory`
- `Chip/Filter`
- `Chip/Status`
- `Pill/Action`

### Variants

Each of these should have:

- light
- dark
- pressed
- selected where relevant

### Interaction prototype suggestions

- tap `Current`, `Visits`, `Saved`, `Timeline` in Locations hero:
  - scroll or swap to related section
- tap relationship chip:
  - filter grouped list
- tap person row:
  - open profile detail
- tap place row:
  - open place detail

## Design guardrails

Avoid:

- heavy nested cards
- glossy translucent gray glass
- too many micro metrics
- duplicate text that repeats what a metric tile already says
- large dead vertical gaps

Prefer:

- one strong surface per section
- concise supporting copy
- ranked rows and dividers over extra boxes
- large typography with tight supporting metadata
- consistent home-page action styling
