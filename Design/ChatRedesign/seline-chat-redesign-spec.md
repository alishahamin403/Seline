# Seline Chat Redesign

## Direction
Rebuild chat around a ChatGPT-style interaction model:
- one calm centered conversation column
- left-side thread rail
- sticky top bar with minimal chrome
- grounded, expandable evidence cards that support the answer instead of competing with it

The Seline touch should come from warmth and precision, not decoration:
- warm ivory in light mode instead of cold pure white
- graphite and espresso neutrals in dark mode instead of blue-black
- soft apricot accent carried over from `Color.homeGlassAccent`
- slightly more editorial typography than the current utilitarian chat
- cards that feel like personal records, not generic API payloads

## Visual System

### Light
- App background: `#F7F3ED`
- Main surface: `#FFFDF9`
- Raised surface: `#FFFFFF`
- Border: `#E6DED3`
- Primary text: `#171412`
- Secondary text: `#6E655D`
- Accent: `#F4A16C`
- Accent soft fill: `#FCE6D8`
- Success: `#2F7D57`
- Warning: `#B86A24`

### Dark
- App background: `#14110F`
- Main surface: `#1C1816`
- Raised surface: `#221D1B`
- Border: `rgba(255,255,255,0.08)`
- Primary text: `#F5EFE8`
- Secondary text: `rgba(245,239,232,0.68)`
- Accent: `#F3A46F`
- Accent soft fill: `rgba(243,164,111,0.16)`

### Type
- Keep Geist as the base face for continuity.
- Page title: 17 semibold
- Assistant body: 16 regular, line height ~25
- User bubble: 15 medium
- Card eyebrow: 11 semibold, +0.5 tracking
- Card title: 14 semibold
- Card metadata: 12 regular

## Layout

### Desktop / iPad width
- Sidebar width: `280`
- Conversation max width: `760`
- Whole shell sits in a full-bleed ambient background.
- Conversation column is centered and padded generously.
- Top bar remains visible but visually quiet.

### Mobile
- Sidebar remains a sheet / overlay.
- Top bar becomes slimmer.
- Composer docks lower with larger tap targets.
- Evidence cards use full width and tighter internal spacing.

## Shell
- Replace the current hard divider header with a softer sticky header that fades into background.
- Left button opens history.
- Center title becomes `Seline` with small status text beneath when thinking.
- Right action stays `new chat`, but rendered as a small ghost pill rather than a bordered circle.
- Remove the feeling of separate panels stacked on top of each other; the screen should read as one continuous chat canvas.

## Conversation Rhythm
- Assistant messages are plain prose first. No enclosing assistant bubble.
- User messages remain right-aligned, but become softer pills with stronger contrast separation from assistant prose.
- Vertical rhythm should mirror ChatGPT:
  - 28 top breathing room above first turn
  - 24 between turns
  - 14 between assistant answer and evidence block
  - 10 between stacked cards in the same block

## Composer
- Composer should look like a docked prompt bar, not a form field inside a toolbar.
- Height baseline: `56`
- Corners: `28`
- Leading controls:
  - attach / voice circle
  - optional context chip row above the field when tools are active
- Text placeholder: `Ask anything about your life, plans, places, or inbox`
- Send button becomes a solid accent circle only when enabled.
- When empty, quick prompts appear above the composer as horizontally scrollable suggestion pills.

## Sidebar
- Visually closer to ChatGPT:
  - slim search field
  - compact thread rows
  - stronger selection fill
  - subtler metadata
- Thread rows should feel denser and calmer than the current version.
- Selected row uses warm accent wash plus a sharper border.

## Assistant Output Blocks

### Markdown answer
- No outer bubble.
- Pure text column with optional inline bold and bullet styling.
- If the answer includes sections, section labels should be subdued small caps, not heavy headlines.

### Evidence cards
Evidence cards should become the signature Seline component.

Structure:
1. Source badge row
2. Primary record title
3. One-sentence summary line
4. Optional supporting detail
5. Footer metadata chips

Card behavior:
- whole card tappable
- hover lifts by 2px and strengthens border
- subtle source-colored icon disc
- metadata chips never exceed two lines
- cards should visually group by source family without becoming rainbow-colored

Source treatment:
- Email: warm amber icon disc, sender + timestamp emphasized
- Calendar/Event: muted blue-gray accent, time range prominent
- Visit/Place: clay red pin accent, distance or neighborhood in footer
- Receipt: sage accent, amount right-aligned in footer
- Person: neutral graphite accent, relationship tags optional
- Note/Journal: cream paper tint inside the card body

### Places block
- Replace the current stack of identical rows with a proper “place results rail”.
- If map is shown, it lives in a clipped 12:7 preview card above results.
- Result rows include:
  - numbered marker chip
  - place name
  - rating / hours / distance line
  - right-side ETA pill when available

### Sources / web citations
- Sources should render as quiet linked rows.
- Reduce visual weight versus evidence cards.
- Keep favicon-like icon, source name, title, external arrow.

### Follow-up suggestions
- Render as small ghost pills in a wrap layout rather than vertical blocks.
- Tone should feel like suggested continuations, not CTA cards.

## Thinking State
- Replace the bordered “thinking row” card with a slim in-flow status line:
  - animated three-dot pulse
  - label like `Checking calendar, inbox, and places`
  - active source chips inline

## Motion
- Composer focus lifts the dock slightly and brightens border.
- New assistant answer fades in with 12px upward motion.
- Evidence cards stagger in after prose.
- Sidebar open/close keeps existing spring feel but uses dimmer scrim.

## Accessibility
- Maintain at least 4.5:1 contrast on all body text.
- User bubble fill must not collapse contrast in dark mode.
- Tap targets stay at least `44x44`.
- Do not rely on color alone to communicate source type; pair color with icon and label.

## Implementation Notes
- Keep `ChatView` as the entry point in `EventsView.swift`.
- Break the redesign into local subviews instead of growing `EventsView.swift` further.
- Preserve the current data model and output blocks; redesign presentation only in the UI pass.
- First implementation should cover:
  - shell
  - composer
  - assistant prose
  - evidence card system
  - place results
  - follow-up pills
- Debug trace UI should stay hidden for now.

## Approval Checklist
- Does the conversation feel close enough to ChatGPT?
- Is the warmth level right for Seline, or should it be more minimal?
- Do the evidence cards feel premium enough to become the default answer support UI?
- Should the sidebar remain pure black/white, or pick up more of the warm accent system?
