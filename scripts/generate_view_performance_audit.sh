#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-/Users/alishahamin/Desktop/Vibecode/Seline}"
APP_ROOT="$ROOT/Seline"

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

score_file() {
  local file="$1"
  local lines observed on_change on_receive async_reloads timers geometry animations notifications widget_reload object_will_change detached_tasks score
  lines="$(wc -l < "$file" | tr -d ' ')"
  observed="$(rg -o '@StateObject|@ObservedObject|@EnvironmentObject' "$file" | wc -l | tr -d ' ' || true)"
  on_change="$(rg -o '\.onChange\(' "$file" | wc -l | tr -d ' ' || true)"
  on_receive="$(rg -o '\.onReceive\(' "$file" | wc -l | tr -d ' ' || true)"
  async_reloads="$(rg -o '\.task\b|Task \{|Task\.detached' "$file" | wc -l | tr -d ' ' || true)"
  timers="$(rg -o 'Timer\.|CADisplayLink|while !Task\.isCancelled|TimelineView\(\.periodic' "$file" | wc -l | tr -d ' ' || true)"
  geometry="$(rg -o 'GeometryReader' "$file" | wc -l | tr -d ' ' || true)"
  animations="$(rg -o '\.animation\(|withAnimation\(' "$file" | wc -l | tr -d ' ' || true)"
  notifications="$(rg -o 'NotificationCenter\.default|NSNotification\.Name|UIApplication\.didBecomeActiveNotification|UIApplication\.didEnterBackgroundNotification' "$file" | wc -l | tr -d ' ' || true)"
  widget_reload="$(rg -o 'WidgetCenter\.shared\.reloadAllTimelines\(|WidgetInvalidationCoordinator\.shared\.requestReload\(' "$file" | wc -l | tr -d ' ' || true)"
  object_will_change="$(rg -o 'objectWillChange\.send\(' "$file" | wc -l | tr -d ' ' || true)"
  detached_tasks="$(rg -o 'Task\.detached' "$file" | wc -l | tr -d ' ' || true)"

  score=$((lines \
    + observed * 120 \
    + on_change * 55 \
    + on_receive * 65 \
    + async_reloads * 55 \
    + timers * 110 \
    + geometry * 70 \
    + animations * 30 \
    + notifications * 60 \
    + widget_reload * 140 \
    + object_will_change * 140 \
    + detached_tasks * 80))

  local risk expensive fix
  if (( score >= 3200 )); then
    risk="High"
  elif (( score >= 1500 )); then
    risk="Medium"
  else
    risk="Low"
  fi

  if (( widget_reload > 0 && notifications > 0 )); then
    expensive="Widget invalidation fan-out from lifecycle or notification churn"
    fix="Route widget refreshes through one debounced coordinator and remove duplicate refresh owners."
  elif (( object_will_change > 0 )); then
    expensive="Manual objectWillChange fan-out"
    fix="Prefer stable @Published reassignments or page-scoped projections so unrelated tabs do not invalidate."
  elif (( timers > 0 )); then
    expensive="Repeating timers or periodic redraw work"
    fix="Scope periodic updates to visible subviews with TimelineView or cancellable page state."
  elif (( observed >= 6 )); then
    expensive="Broad singleton observation fan-out"
    fix="Split view models into smaller projection states and stop observing broad managers at the root."
  elif (( on_change + on_receive + async_reloads >= 10 )); then
    expensive="Duplicated lifecycle-driven reload paths"
    fix="Deduplicate refresh ownership, debounce external events, and move warmups off the first-interaction path."
  elif (( detached_tasks >= 3 )); then
    expensive="Detached background work launched from UI paths"
    fix="Queue non-critical work behind a coordinator so launch, scroll, and tab switching stay responsive."
  elif (( lines >= 1200 )); then
    expensive="Large view or service with likely derived-data churn"
    fix="Cache grouped, filtered, and sorted collections instead of recomputing them inside render paths."
  else
    expensive="No single dominant hotspot from static scan"
    fix="Profile with Instruments and verify the runtime owner of refresh or invalidation work."
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$score" "$risk" "$lines" "$observed" "$timers" "$notifications" "$async_reloads" "$widget_reload" "$object_will_change" "$detached_tasks" "$expensive" "$fix" "$geometry" "$file" \
    >> "$tmpfile"
}

while IFS= read -r file; do
  score_file "$file"
done < <(rg --files "$APP_ROOT" -g '*.swift')

sort -nr "$tmpfile" -o "$tmpfile"

cat <<'EOF'
# Seline Runtime Performance Audit

## Prioritized Findings
EOF

rank=0
while IFS=$'\t' read -r score risk lines observed timers notifications async_reloads widget_reload object_will_change detached_tasks expensive fix geometry file; do
  rank=$((rank + 1))
  if (( rank > 8 )); then
    break
  fi

  printf '\n%d. `%s`\n' "$rank" "$file"
  printf '   Risk: %s | Score: %s | Timers: %s | Notifications: %s | Widget Reload Sites: %s | objectWillChange: %s\n' \
    "$risk" "$score" "$timers" "$notifications" "$widget_reload" "$object_will_change"
  printf '   Hotspot: %s\n' "$expensive"
  printf '   Suggested fix: %s\n' "$fix"
done < "$tmpfile"

cat <<'EOF'

## Appendix

| Risk | Score | File | Observed Sources | Timers | Notifications | Async Reloads | Widget Reload Sites | objectWillChange | Detached Tasks | Geometry | Expensive Derived Work | Recommended Fix |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
EOF

while IFS=$'\t' read -r score risk lines observed timers notifications async_reloads widget_reload object_will_change detached_tasks expensive fix geometry file; do
  printf '| %s | %s | `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$risk" "$score" "$file" "$observed" "$timers" "$notifications" "$async_reloads" "$widget_reload" "$object_will_change" "$detached_tasks" "$geometry" "$expensive" "$fix"
done < "$tmpfile"
