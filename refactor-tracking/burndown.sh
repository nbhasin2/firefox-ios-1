#!/usr/bin/env bash
# Refreshes the burn-down numbers in PROGRESS.md. Run from anywhere.
#
# Targets are not all zero: D-016 retains a reduced Redux core as the browser event bus.
# Metrics are grouped so that "Redux is still imported" is never mistaken for "not finished".
# Exits non-zero if a guardrail is breached.
set -euo pipefail
cd "$(dirname "$0")/.."

SWIFT=(--include='*.swift')
CLIENT=firefox-ios/Client
BUS='GeneralBrowserAction|NavigationBrowserAction|GeneralBrowserMiddlewareAction'

# `|| true` on every grep: a metric reaching zero must not abort the script.
# Every stage needs `|| true`: under pipefail an empty grep result fails the whole pipeline, so a
# metric reaching zero would abort the script instead of printing the zero.
files() { { { grep -rlE "$1" "${SWIFT[@]}" firefox-ios BrowserKit 2>/dev/null || true; } | grep -v '\.build' || true; } | wc -l | tr -d ' '; }
sites() { { grep -rnE "$1" "${SWIFT[@]}" "$CLIENT" 2>/dev/null || true; } | wc -l | tr -d ' '; }

row() { printf '  %-42s %6s   target %s\n' "$1" "$2" "$3"; }

# The middleware type itself, not the *MiddlewareAction families, which are retained bus
# vocabulary (D-042). Counted across the whole repo because the machinery lived in BrowserKit.
middlewares=$(files 'Middleware<|MiddlewareClosure|middlewares: \[')
# Renamed once screens stopped subscribing; both spellings counted so the metric stays honest.
subscribers=$(sites 'func subscribeToRedux|store\.subscribe\(')
# AppComponent.swift is deleted once the screen-state tree is gone.
components=$({ grep -cE '^\s+case ' "$CLIENT/Redux/GlobalState/AppComponent.swift" 2>/dev/null || echo 0; })
# Type declarations only. A parameter typed `Action` is not a new family, and since the reducers
# became functions there are plenty of those.
all_actions=$(sites '^(struct|final class|class|enum) [A-Za-z]+: (Action|ModernAction)\b')
bus_actions=$({ grep -rnE "^(struct|final class|class|enum) ($BUS): " "${SWIFT[@]}" "$CLIENT" 2>/dev/null || true; } | wc -l | tr -d ' ')
screen_actions=$(( all_actions - bus_actions ))
ACTION_BUDGET=19

echo "Screen state — must reach zero"
row "files with middleware plumbing"     "$middlewares"     0
row "StoreSubscriber screens"           "$subscribers"     0
row "AppComponent cases"                "$components"      0

imports=$(files 'import Redux')
dispatches=$(sites 'store\.dispatch|\.dispatch\(')
bus_files=$(grep -rlE "$BUS" "${SWIFT[@]}" "$CLIENT" 2>/dev/null | wc -l | tr -d ' ')
bus_sites=$(grep -rnE "$BUS" "${SWIFT[@]}" "$CLIENT" 2>/dev/null | grep -cE 'dispatch\(' || true)

echo
echo "Retained bus (D-016) — converges to a budget, not to zero"
row "files with import Redux"           "$imports"    "~31"
row "dispatch call sites"               "$dispatches" "~18"
row "files touching browser actions"    "$bus_files"  "~31"
row "browser-level dispatch sites"      "$bus_sites"  "~18"
# Was "screen Action types", targeting zero, back when an action existed to feed a screen state.
# No screen state is left, so every remaining family is the vocabulary the bus is addressed in
# (D-016). It is a budget now: it must not grow.
row "action families on the bus"        "$screen_actions" "<= $ACTION_BUDGET"

# D-017 guardrail. Convention: a notification introduced by this migration is declared as a
# Notification.Name inside a *ViewModel.swift file (as TrackingProtectionViewModel does).
#
# Budget of 3, each justified:
#   1-2. trackingProtectionBlockedTrackersDidChange / ...ConnectionStatusDidChange (D-014).
#        Browser-level and therefore on the wrong side of D-017; they move to the bus in
#        Phase 4 item 22, once dispatching no longer traverses the whole reducer chain.
#     3. homepageSectionSettingsChanged (D-017 row three, legitimate and permanent).
#        Settings screens have no ownership path to the homepage and a section toggle is not a
#        browser-level event. One notification carries all six homepage section toggles, so this
#        does not grow as the remaining homepage sections migrate.
NOTIF_BUDGET=3
notifs=$(grep -rn 'Notification\.Name("' "${SWIFT[@]}" "$CLIENT" 2>/dev/null \
  | grep -c 'ViewModel\.swift' || true)

echo
echo "Guardrails (D-017) — must not grow"
row "migration-introduced notification names" "$notifs" "<= $NOTIF_BUDGET"

status=0
if [ "$screen_actions" -gt "$ACTION_BUDGET" ]; then
  echo
  echo "FAIL: $screen_actions action families exceeds the budget of $ACTION_BUDGET."
  echo "      A new family means something is being modelled as a screen again; give it an owner."
  status=1
fi
if [ "$notifs" -gt "$NOTIF_BUDGET" ]; then
  echo
  echo "FAIL: $notifs migration-introduced notifications exceeds the budget of $NOTIF_BUDGET."
  echo "      D-017: an ownerless *browser-level* signal belongs on the bus, not NotificationCenter."
  status=1
fi
if [ "$middlewares" -eq 0 ] && [ "$components" -gt 0 ]; then
  echo
  echo "FAIL: the middleware layer is gone but AppComponent still has $components cases — screen state leaked."
  status=1
fi
exit $status
