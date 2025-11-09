# Seline Layout - Quick Reference Guide

## Core Files Map

```
Seline/Views/
├── MainAppView.swift ......................... Main app container (tab-based)
├── Components/
│   ├── ConversationSearchView.swift ......... Chat interface with sidebar overlay
│   ├── ConversationSidebarView.swift ....... Chat history sidebar (380pt max width)
│   ├── FolderSidebarView.swift ............. Notes folder navigation
│   ├── EmailCardWidget.swift ............... 50% width card widget
│   ├── NotesCardWidget.swift ............... 50% width card widget
│   └── [other components]
├── EmailView.swift .......................... Email tab
├── EventsView.swift ......................... Events tab
├── NotesView.swift .......................... Notes tab
└── MapsViewNew.swift ........................ Maps tab
```

## Layout Dimensions at a Glance

### Sidebars
| Component | Min Width | Ideal Width | Max Width |
|-----------|-----------|-------------|-----------|
| Conversation Sidebar | 300pt | 380pt | 380pt |

### Padding Standards
| Location | Horizontal | Vertical |
|----------|-----------|----------|
| Header/Footer | 16pt | 12pt |
| Message area | 16pt | 16pt |
| Section headers | 16pt | 8pt |
| Row/Item padding | 12-16pt | 10-12pt |
| Message bubble | 12pt | 10pt |

### Widget Layout
```
Home Tab Content:
├── Spending + ETA Widget (full width)
├── Events Card (full width, expands)
└── Email + Notes Cards
    ├── 50% width: Email Card (height: 170pt)
    └── 50% width: Notes Card (height: 170pt)
    └── Gap: 8pt
    └── Side padding: 12pt
```

## Navigation Structure

```
MainAppView (Root)
│
├─ TabSelection.home
│  └─ HomeView (with header + widgets + bottom tab)
│
├─ TabSelection.email
│  └─ EmailView
│
├─ TabSelection.events
│  └─ EventsView
│
├─ TabSelection.notes
│  └─ NotesView
│
└─ TabSelection.maps
   └─ MapsViewNew

fullScreenCover:
└─ ConversationSearchView
   ├─ Header (fixed, 16pt padding)
   ├─ Message thread (scrollable, 16pt padding)
   ├─ Input area (fixed, 16pt padding)
   └─ ConversationSidebarView (overlay, slide-in from left)
```

## Message Layout Details

### User Message
```
┌─────────────────────────────────┐
│ Spacer ││ Bubble with content   │
│        ││ (white bg, dark mode) │
│        ││ (black bg, light mode)│
└─────────────────────────────────┘
```

### AI Message
```
┌─────────────────────────────────┐
│ ││ Bubble with markdown       │ Spacer │
│ ││ (gray 0.15 opacity bg)     │        │
│ ││ (0.5pt stroke border)      │        │
└─────────────────────────────────┘
```

### Bubble Styling
- Padding: 12pt horizontal, 10pt vertical
- Corner radius: 12pt
- User messages: No stroke
- AI messages: 0.5pt gray stroke
- Spacing between messages: 16pt vertical

## Sidebar (ConversationSidebarView) Structure

```
┌──────────────────────────┐
│  Header Section          │ 12pt v-padding
│  ┌─────────────────────┐ │
│  │ Chats | Edit | ... │ │ 16pt h-padding
│  └─────────────────────┘ │
│  ┌─────────────────────┐ │
│  │ New Chat (gray bg)  │ │
│  └─────────────────────┘ │
├──────────────────────────┤
│  ScrollView              │
│  ┌─────────────────────┐ │
│  │ Recent Conversations│ │ Section header
│  ├─────────────────────┤ │
│  │ Chat Title    [5]   │ │ Row: 16pt h, 12pt v
│  ├─────────────────────┤ │ Divider (0.3 opacity)
│  │ Chat Title    [3]   │ │
│  ├─────────────────────┤ │
│  │ ...                 │ │
│  └─────────────────────┘ │
└──────────────────────────┘
  Max Width: 380pt
  Background: gmailDarkBackground (dark)
              or white (light)
```

## Color Tokens

### Dark Mode
- Primary background: `Color.gmailDarkBackground`
- Secondary bg: `Color(red: 0.15, green: 0.15, blue: 0.15)`
- Tertiary bg: `Color.gray.opacity(0.15)`
- Text primary: `Color.white`
- Text secondary: `Color.white.opacity(0.6)`
- Dividers: `Color.white.opacity(0.1-0.3)`

### Light Mode
- Primary background: `Color.white`
- Secondary bg: `Color(red: 0.95, green: 0.95, blue: 0.95)`
- Tertiary bg: `Color.gray.opacity(0.15)`
- Text primary: `Color.black`
- Text secondary: `Color.black.opacity(0.6)`
- Dividers: `Color.black.opacity(0.1-0.3)`

## Animation Timings

| Animation | Duration | Curve |
|-----------|----------|-------|
| Sidebar slide | 0.2s | easeInOut |
| Folder expand/collapse | 0.2s | easeInOut |
| Search fade | 0.2s | easeInOut |
| Tab transitions | system | system |

## Key Frame Modifiers

```swift
// Conversation Sidebar
.frame(minWidth: 300, idealWidth: 380, maxWidth: 380)

// Fixed header/footer width
.frame(width: geometry.size.width, height: geometry.size.height)

// 50/50 split widgets
.frame(width: (geometry.size.width - 8) * 0.5)

// Fixed card height
.frame(height: 170)

// Folder indentation
.frame(width: CGFloat(depth * 24))

// Flexible content
.frame(maxHeight: .infinity)
```

## Z-Index Layers

| Z-Index | Component | Purpose |
|---------|-----------|---------|
| 20 | Conversation Sidebar | Overlay above main content |
| 10 | Sidebar toggle button | Clickable above content |
| 100 | Header section | Above scrollable content |
| 0 | Main content | Base layer |

## Common Padding Patterns

```swift
// Full width with side margins
.padding(.horizontal, 16)

// Compact horizontal padding
.padding(.horizontal, 12)

// Header style
.padding(.horizontal, 16).padding(.vertical, 12)

// Row style
.padding(.horizontal, 16).padding(.vertical, 12)

// Bubble/message style
.padding(.horizontal, 12).padding(.vertical, 10)

// Section header style
.padding(.horizontal, 16).padding(.vertical, 8)
```

## Responsive Breakpoints

Seline uses **GeometryReader** for all responsive sizing:
- No fixed breakpoints
- All widths are percentages or calculations of parent
- Uses `geometry.size.width` and `geometry.size.height` for dynamic layout
- Sidebar has fixed 380pt max, adapts to screen if smaller

## Layout Best Practices Used

1. ✓ Fixed header/footer for persistent UI
2. ✓ Scrollable content areas in middle
3. ✓ Consistent padding (16pt standard)
4. ✓ Dynamic width via GeometryReader
5. ✓ Overlay sidebars with z-index layering
6. ✓ Smooth transitions (0.2s easeInOut)
7. ✓ Color scheme aware (light/dark)
8. ✓ Safe area awareness with ignoresSafeArea()
9. ✓ Flexible spacing with Spacer()
10. ✓ Message bubbles with directional alignment

