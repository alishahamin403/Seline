#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/Users/alishahamin/Desktop/Vibecode/Seline}"
VIEWS_DIR="$ROOT/Seline/Views"

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

score_file() {
  local file="$1"
  local lines observed on_change on_receive async_reloads timers geometry animations notifications score
  lines="$(wc -l < "$file" | tr -d ' ')"
  observed="$(rg -o '@StateObject|@ObservedObject|@EnvironmentObject' "$file" | wc -l | tr -d ' ' || true)"
  on_change="$(rg -o '\.onChange\(' "$file" | wc -l | tr -d ' ' || true)"
  on_receive="$(rg -o '\.onReceive\(' "$file" | wc -l | tr -d ' ' || true)"
  async_reloads="$(rg -o '\.task|Task \{' "$file" | wc -l | tr -d ' ' || true)"
  timers="$(rg -o 'Timer\.|CADisplayLink' "$file" | wc -l | tr -d ' ' || true)"
  geometry="$(rg -o 'GeometryReader' "$file" | wc -l | tr -d ' ' || true)"
  animations="$(rg -o '\.animation\(|withAnimation\(' "$file" | wc -l | tr -d ' ' || true)"
  notifications="$(rg -o 'NotificationCenter\.default|NSNotification\.Name' "$file" | wc -l | tr -d ' ' || true)"
  score=$((lines + observed * 120 + on_change * 60 + on_receive * 70 + async_reloads * 60 + timers * 120 + geometry * 80 + animations * 35 + notifications * 70))

  local risk expensive fix
  if (( score >= 2500 )); then
    risk="High"
  elif (( score >= 1000 )); then
    risk="Medium"
  else
    risk="Low"
  fi

  if (( timers > 0 )); then
    expensive="Repeating timers or display-driven state updates"
    fix="Replace repeating timers with visibility-scoped tasks or TimelineView; avoid offscreen work."
  elif (( observed >= 6 )); then
    expensive="Broad singleton observation fan-out"
    fix="Split this screen into smaller projections so unrelated service changes do not invalidate the whole view."
  elif (( on_change + on_receive + async_reloads >= 8 )); then
    expensive="Duplicated lifecycle-driven reload paths"
    fix="Deduplicate refresh ownership and debounce view-triggered reloads."
  elif (( lines >= 1200 )); then
    expensive="Large view body with likely derived collection churn"
    fix="Extract subviews and move sorting/grouping/filtering into cached state."
  elif (( geometry > 0 && animations >= 4 )); then
    expensive="Animated geometry work in a scrolling layout"
    fix="Reduce animation scope and keep geometry readers out of repeated list rows."
  else
    expensive="No standout hotspot from static scan"
    fix="Keep data prep cached and verify with runtime profiling before changing behavior."
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$score" "$risk" "$lines" "$observed" "$timers" "$notifications" "$async_reloads" "$geometry" "$animations" "$expensive" "$fix" "$file" \
    >> "$tmpfile"
}

while IFS= read -r file; do
  score_file "$file"
done < <(rg --files "$VIEWS_DIR" -g '*.swift')

sort -nr "$tmpfile" -o "$tmpfile"

cat <<'EOF'
# Seline View Performance Audit

## Prioritized Findings

1. `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MainAppView.swift`
   Root invalidation fan-out was too broad and the location widget path was doing per-second work. The implementation now routes dashboard counts through `HomeDashboardState`, removes several unused root observers, and stops reloading WidgetKit every second.

2. `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/NotesView.swift`
   Notes list grouping/search/filtering was being refreshed from broad object change notifications. The implementation now uses `NotesHubState` to cache pinned, recent, and month-grouped notes from explicit inputs instead of `objectWillChange`.

3. `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/Components/ConversationSearchView.swift`
   Chat was carrying multiple repeating timers and decorative continuous animations. The implementation replaces timer-driven autoscroll/loading states with a single visibility-scoped task plus `TimelineView`-driven loading indicators.

4. `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MapsViewNew.swift`
   The maps hub had a forced `.id(colorScheme)` full rebuild and its own repeating timer. The implementation removes the forced identity reset and replaces the timer with a cancellable task loop scoped to the active visit state.

5. `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/EmailView.swift`
   Day sections were being rebuilt from multiple lifecycle hooks. The implementation moves list section caching into `EmailHubState` so tab/filter changes and service updates coalesce into one derived state path.

6. `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/Components/DailyOverviewWidget.swift`
   The home overview was deriving task/birthday slices in view code. The implementation moves those cached slices into `HomeDashboardState` and reuses shared formatters.

## Appendix

| Risk | Score | File | Observed Sources | Timers | Notifications | Async Reloads | Geometry | Animations | Expensive Derived Work | Recommended Fix |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
EOF

while IFS=$'\t' read -r score risk lines observed timers notifications async_reloads geometry animations expensive fix file; do
  printf '| %s | %s | `%s` | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$risk" "$score" "$file" "$observed" "$timers" "$notifications" "$async_reloads" "$geometry" "$animations" "$expensive" "$fix"
done < "$tmpfile"
