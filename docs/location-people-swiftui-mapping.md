# Locations + People SwiftUI Mapping

This maps the exported Figma code bundle at:

- `/Users/alishahamin/Downloads/Design Locations and People Pages/src/app/components/LocationsPage.tsx`
- `/Users/alishahamin/Downloads/Design Locations and People Pages/src/app/components/PeoplePage.tsx`
- `/Users/alishahamin/Downloads/Design Locations and People Pages/src/app/components/TopChrome.tsx`
- `/Users/alishahamin/Downloads/Design Locations and People Pages/src/app/components/SegmentedControl.tsx`

onto Seline’s current SwiftUI structure.

The main app targets are:

- `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MapsViewNew.swift`
- `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/Components/PeopleListView.swift`
- `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/LocationTimelineView.swift`

## Design intent

The exported design follows the new home-page direction correctly:

- monochrome shell
- orange reserved for primary action and active state
- tighter vertical rhythm
- flatter sections
- less box-on-box nesting

That direction should carry into SwiftUI with one important addition:

## Required addition: preserve the map cutout

The exported `LocationsPage.tsx` does not include the existing Seline mini-map module, but the real app should keep it.

Do not remove the map from the page.

Instead, represent it as a cutout-style visual module in the new layout:

- place it directly below the hero and above `Top places`
- keep the live map behavior from `MiniMapView`
- give it a more intentional silhouette so it reads as a visual anchor, not a generic rectangle

### Recommended cutout treatment

Use the current `MiniMapView` in `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MapsViewNew.swift` and wrap it in a custom container with:

- large outer radius
- one carved utility notch/cutout in the top-right or bottom-right area
- the map expand and recenter actions living inside that cutout zone
- surrounding monochrome surface so the map feels embedded into the page language

This should feel like the map version of a hero visual, not a plain inset map card.

## Shared shell mapping

### Top chrome

Figma source:

- `TopChrome.tsx`

SwiftUI destination:

- `headerSection`
- `hubHeader`
- `hubMainPagePicker`
- search trigger inside `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MapsViewNew.swift`

### Implementation notes

Replace the current maps header card structure with a home-style top chrome:

- left: search capsule
- middle: orange primary action
- right: profile / utility circle
- segmented control remains directly below or integrated into the same header block

For consistency with the redesigned home page:

- search should visually match the home search field
- the orange primary action should match the home add button
- the utility/profile circle should match the home profile control

## Locations page mapping

### 1. Hero module

Figma source:

- `LocationsPage.tsx` hero block

SwiftUI destination:

- replace `savedOverviewCard` in `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MapsViewNew.swift`

### Content mapping

Use existing data sources:

- title and supporting sentence:
  - `hubCurrentLocationSummary`
  - `filteredSavedPlacesForQuery.count`
  - `todayVisitCount`
  - `hubPeriodVisits.count`
  - `hubTotalVisitMinutes`
- right rail metrics:
  - `hubPeriodVisits.count`
  - `formatDuration(minutes:)`

### Layout changes

Current `savedOverviewCard` is still stats-first and widget-like.

Replace it with:

- small eyebrow `LOCATIONS`
- larger editorial headline
- one compact explanatory sentence
- right-side month summary rail
- fixed hero action row

### 2. Hero actions

Figma source:

- `Current`
- `Visits`
- `Saved`
- `Timeline`

SwiftUI destination:

- new fixed actions inside the rebuilt `savedOverviewCard`

### Interaction mapping

- `Current`
  - scroll to or expand current place strip
- `Visits`
  - scroll to `Top places` / recent visit content
- `Saved`
  - scroll to saved places stream
- `Timeline`
  - set `selectedHubDetail = .timeline`

Do not make these dynamic chips. Keep them fixed, like the new home hero buttons.

### 3. Map cutout module

SwiftUI destination:

- based on `miniMapSection`
- uses `MiniMapView`

### Placement

Insert immediately after the hero and before `Current place strip` or `Top places`.

Recommended order:

1. hero
2. map cutout
3. current place strip
4. top places
5. saved places
6. timeline entry

### Why this order

It preserves the strongest visual from the real app while still following the exported hierarchy.

### 4. Current place strip

Figma source:

- `LIVE`
- current place name
- short summary
- three quick place pills

SwiftUI destination:

- new section in `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MapsViewNew.swift`

### Data mapping

Build from:

- `nearbyLocation`
- `hubCurrentLocationSummary`
- `topLocations`
- recent/current saved place context from location service

### Replace / reuse

This should replace the old heavier “summary + favorites” approach near the top of the page.

It should not be another large card with nested tiles.

### 5. Top places

Figma source:

- ranked 3-row list

SwiftUI destination:

- reuse `topLocations`
- currently loaded by `loadTopLocations()`

### Implementation notes

Render as:

- rank number
- place name
- category/subtitle
- visit count
- right-side mini progress track

This is cleaner than the current folder-first treatment and should appear before folders.

### 6. Saved places stream

Figma source:

- divider-separated saved place list

SwiftUI destination:

- replace the current `savedFoldersSection` as the primary browsing surface

### Important change

The folder model should still exist, but visually the first-class browsing surface should be flatter:

- one outer section
- divider-separated rows
- optional folder/category metadata on each row

If folders still need expansion, make them secondary or collapsible beneath the primary saved stream instead of the first thing users see.

### 7. Timeline entry module

Figma source:

- bottom CTA card for timeline

SwiftUI destination:

- new small section near bottom of `locationsTabContent`

### Action

- button sets `selectedHubDetail = .timeline`

## People page mapping

### 1. Hero module

Figma source:

- `PeoplePage.tsx` hero block

SwiftUI destination:

- `peopleHeroCard` in `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/Components/PeopleListView.swift`

### Implementation notes

The current SwiftUI hero is already close.

Keep:

- title
- metrics
- import / add actions

Tighten it toward the exported version:

- keep the supporting sentence under `People`
- reduce extra vertical padding
- keep three metric tiles in one row

### 2. Favorites strip

Figma source:

- compact horizontal favorites row

SwiftUI destination:

- `favoritesOverview`

### Required change

Make it flatter and lower weight.

The current implementation is close, but the exported design is more neutral and less pill-heavy.

### 3. Relationship section

Figma source:

- section title
- filter chips
- recent activity
- grouped flat rows

SwiftUI destination:

- `peopleDirectorySection`
- `relationshipFilterChips`
- `relationshipGroupSection(_:)`

### Current state

You already flattened the group presentation earlier, which is the correct direction.

To match the export exactly:

- keep one outer section surface
- keep group headers simple
- rows should stay divider-separated
- no extra inner group card shells

### 4. Recent activity module

Figma source:

- compact editorial list under relationship chips

SwiftUI destination:

- add inside `peopleDirectorySection`, above grouped rows

### Data sources

Use current people-derived recency data:

- `hubRecentPeople` style logic already exists in `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MapsViewNew.swift`
- `peopleManager.people`
- birthdays cache already exists in `PeopleListView.swift`

### 5. Person rows

Figma source:

- avatar
- name
- update line
- favorite star
- chevron

SwiftUI destination:

- `PersonRowView(style: .plain, ...)`

No major structural change is needed. This is mostly spacing and visual polish.

## Timeline tab

Do not redesign it to match the export’s flattened overview cards.

Keep `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/LocationTimelineView.swift` as the functional detailed timeline.

What should change is only the way `Locations` points into it:

- through the hero `Timeline` action
- through the bottom CTA module

## Styling tokens to carry over

From the exported theme:

- light background: pure white
- dark background: black
- card fill: same as background tone, not tinted
- muted surfaces:
  - light: very soft gray
  - dark: near-black charcoal
- border:
  - subtle 8% contrast
- orange accent:
  - `#FF6B35`

SwiftUI equivalents should live through existing Seline tokens in:

- `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Utils/ShadcnColors.swift`

## Recommended implementation order

1. Rebuild the maps header to match the home-style chrome.
2. Replace `savedOverviewCard` with the exported locations hero.
3. Add the map cutout module directly under the hero using `MiniMapView`.
4. Add current place strip.
5. Convert `topLocations` into the ranked list section.
6. Rework saved places browsing into a flatter stream.
7. Add the bottom timeline CTA.
8. Tighten `PeopleListView` hero.
9. Insert recent activity module into `People`.
10. Adjust favorites and grouped rows to match export spacing.

## Non-goals

Do not:

- remove map functionality from locations
- remove the timeline tab
- turn people into a card grid
- reintroduce ambient gradients or tinted page backgrounds
