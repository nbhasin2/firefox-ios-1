# WorldCup Live Activity Design

Date: 2026-06-12
Status: Approved (brainstorming complete, ready for implementation plan)

## Overview

Add an iOS Live Activity (Lock Screen + Dynamic Island) for the Firefox iOS
WorldCup homepage feature. When a user follows a national team, the app starts a
Live Activity that shows that team's live/current match score plus their next
fixture. The activity updates from the existing WorldCup polling feed while the
app has runtime, and ends when the team is no longer relevant.

This reuses the existing WidgetKit extension and the proven Download Live
Activity pattern. No new target, entitlement, or feature flag is introduced.

## Locked Decisions

- Q1 trigger: START when a team is followed. Show that team's live/current match
  score plus their next match. Surface = iOS Live Activity (Lock Screen +
  Dynamic Island).
- Q2 end conditions: END on ANY of (a) user unfollows or changes team (change =
  end old + start new); (b) followed team eliminated; (c) after the team's last
  match (no next match); (d) the tournament fully ends.
- Q3 update mechanism: LOCAL client-side updates only for v1. The app updates the
  activity from the existing WorldCup polling feed when it has runtime
  (foreground / brief background). No backend or APNs push. Score may go stale
  while the phone is locked and the app suspended. Matches the Download Live
  Activity pattern.
- Q4 feature gating: REUSE the existing `worldCupWidget` Nimbus flag as-is. The
  activity is gated by the same flag as the homepage card. No new flag or
  variable.
- Q5 tap behavior: Tapping the activity opens Firefox to the homepage WorldCup
  card via a deep link.

## Architecture: Approach A (Middleware-Driven Orchestrator)

A new `WorldCupLiveActivityManager` is called by `WorldCupMiddleware` on the two
events it already handles: `selectTeam` (start / replace / end) and `didUpdate`
(update score, or end on elimination / no-next-match). The manager owns a single
`Activity<WorldCupLiveActivityAttributes>?`.

Rejected alternatives:
- Approach B (observe the feed directly): `WorldCupFeed.onUpdate` is a single
  closure already consumed by the middleware; observing it separately would
  duplicate orchestration logic.
- Approach C (BVC-owned, like `DownloadLiveActivityWrapper`): the
  BrowserViewController does not observe WorldCup state, so this would require
  new wiring for no benefit.

## Section 1: Components and File Layout

New files (all `@available(iOS 17, *)`):

- `WidgetKit/WorldCup/WorldCupLiveActivityAttributes.swift` -
  `WorldCupLiveActivityAttributes: ActivityAttributes` with nested
  `ContentState`. Compiled into BOTH the app and the widget extension targets
  (the app/widget contract). Mirrors `DownloadLiveActivityAttributes`.
- `WidgetKit/WorldCup/WorldCupLiveActivity.swift` - the `Widget` with
  `ActivityConfiguration`, Lock Screen view, and Dynamic Island
  (expanded / compact / minimal). Registered in `WidgetKit/WidgetKit.swift`
  `FirefoxWidgets` bundle behind `if #available(iOS 17, *)`.
- `Client/Frontend/Home/Homepage/WorldCup/WorldCupLiveActivityManager.swift` -
  `@MainActor` class owning `Activity<WorldCupLiveActivityAttributes>?`. Methods
  `start(from:)`, `update(from:)`, `end(reason:)`. Mirrors
  `DownloadLiveActivityWrapper`.
- `Client/Frontend/Home/Homepage/WorldCup/WorldCupLiveActivityMapper.swift` -
  pure function `WorldCupSectionState -> ContentState?`, unit-testable without
  ActivityKit.

Modified files:
- `WorldCupMiddleware.swift` (call the manager on `selectTeam` + `didUpdate`).
- `WidgetKit/WidgetKit.swift` (register the activity).
- Deep-link wiring (Section 5): `Route.swift`, `RouteBuilder`,
  `BrowserCoordinator`.

No new target, entitlement, or flag. The WidgetKit extension and the
`group.org.mozilla.ios.<flavor>` App Group already exist; the `worldCupWidget`
flag is reused.

## Section 2: Data Model

`WorldCupLiveActivityAttributes` static attributes (immutable per activity, set
at start; changing team = end old + start new):
- `teamCode: String` (FIFA 3-letter, e.g. "BRA")
- `teamDisplayName: String` (localized, e.g. "Brazil")

Dynamic `ContentState` (Codable, Hashable; rebuilt from `WorldCupSectionState`
on every `didUpdate`):
- `currentMatch: MatchSnapshot?` (live / most-relevant match, nil if none)
- `nextMatch: MatchSnapshot?` (team's upcoming fixture, nil if none)
- `lastUpdated: Date` (for "updated X ago" and staleness)

`MatchSnapshot` (Codable, Hashable):
- `homeCode: String`, `awayCode: String`
- `homeFlagAsset: String` (== code today), `awayFlagAsset: String`
- `scoreText: String?` ("2 - 1", nil when not started)
- `clockText: String?` ("45'", nil when not live)
- `isLive: Bool`
- `kickoffText: String?` (next match, e.g. "Sat 16:00")
- `phaseTitle: String` ("Group Stage", "Round of 16")

Mapper logic (pure fn `WorldCupSectionState -> ContentState?` in
`WorldCupLiveActivityMapper.swift`, unit-testable without ActivityKit): from
`selectedCountryId` + `matches: [WorldCupMatches]`: `currentMatch` = followed
team's match where `isLive == true` else most-recent / in-progress; `nextMatch` =
team's earliest upcoming fixture (from `upcomingMatches`); copy
score / clock / codes / flags straight from `WorldCupMatch`.

Flag-asset risk (acknowledged): flags load via `Image(country.id)` from the MAIN
APP asset catalog; the Live Activity renders in the WIDGET EXTENSION process, so
flag assets must be a target member of WidgetKitExtension OR fall back to the
3-letter code text. The plan must include an explicit task to verify / add flag
assets to the widget target, with a text-code fallback as the safety net.

## Section 3: Lifecycle and Control Flow

All orchestration lives in `WorldCupLiveActivityManager` (`@MainActor`,
iOS 17+), called by `WorldCupMiddleware` on the two events it already handles
(`selectTeam`, `didUpdate`). The manager owns a single
`Activity<WorldCupLiveActivityAttributes>?`.

START (driven by `selectTeam`): trigger = middleware `selectTeam` with a non-nil
`countryId` AND `worldCupStore.isFeatureEnabled` (`worldCupWidget` flag) true AND
`ActivityAuthorizationInfo().areActivitiesEnabled` true. If an activity is
already running for a DIFFERENT team, end the old one first then request the new
one (change = end + start). If `countryId` is nil (deselect), treat as END.
Build the initial `ContentState` from the current `WorldCupSectionState` via the
mapper; call `Activity.request(...)`.

UPDATE (driven by `didUpdate`): trigger = `didUpdate` while an activity is live.
Re-run the mapper on the new state, call `activity.update(using:)`. This is the
only path that refreshes live score/clock; it piggybacks on the existing
polling -> Redux loop, no new polling.

END (evaluated on `didUpdate` plus deselect on `selectTeam`) when ANY:
(a) `selectedCountryId` became nil (unfollowed) -> end immediately;
(b) team eliminated - the feed already flips eliminated teams to the
flattened / no-team view, which clears `selectedCountryId` and collapses into
case (a); also defensively check "no current + no next";
(c) last match played - mapper yields `currentMatch == nil && nextMatch == nil`
-> end;
(d) tournament ended - same terminal signal as (c).
End uses `.end(using: finalContent, dismissalPolicy: .after(date))` so the
finished match lingers about 2-4 hours then disappears.

Guards / idempotency: all calls no-op cleanly if iOS < 17, activities are
disabled, or there is no state change. Cold start: if a team is followed and a
match is live or upcoming, the manager reconciles (starts the activity if none) -
hooked off the same `enteredForeground` / `initialize` path the feed uses.

## Section 4: UI Layout

All views `@available(iOS 17, *)` in `WidgetKit/WorldCup/WorldCupLiveActivity.swift`,
mirroring `DownloadLiveActivity.swift` structure.

Lock Screen / Banner card: top row = home flag + code, score ("2 - 1", or "vs"
if not started), away code + flag, then clock ("45'") + a red LIVE dot on the
right. Phase title (small, secondary) under the score. If a next match exists: a
thin divider + a "Next:" line with two codes + kickoff text. If
`currentMatch == nil` (between matches), the next match becomes the hero row
instead.

Dynamic Island expanded: `.leading` = home flag + code, `.trailing` = away code +
flag, `.center` = score + clock (or kickoff text), `.bottom` = phase title +
optional "Next:" line. `compactLeading` = home flag (or team code).
`compactTrailing` = score "2-1" if live else kickoff "16:00". `minimal` = single
followed-team flag.

Visuals: reuse system colors; LIVE = small red dot + "LIVE". Flags via
`Image(code)` with a text-code fallback (Section 2 asset-target risk). The whole
surface uses `.widgetURL(deepLinkURL)` so any tap routes to the WorldCup card
(Section 5). Staleness: if `Date.now - lastUpdated > ~5 min` while a match is
live, render the clock in a secondary color to signal possibly-stale data.

## Section 5: Deep Link (Option A)

Reuse `Route.homepanel`. Tapping the Live Activity (Lock Screen or Dynamic
Island) sets `.widgetURL(URL(string: "firefox://deep-link?url=/homepanel/worldcup"))`
(`firefox://` = the existing `MOZ_PUBLIC_URL_SCHEME`).

Flow: iOS opens the app with the URL -> `SceneDelegate.openURLContexts` ->
`handleOpenURL` -> `RouteBuilder.makeRoute(url:)` -> `Route` ->
`SceneCoordinator.findAndHandle` -> `BrowserCoordinator.handle`.

Implementation: add a `worldCup` case to the nested `HomepanelSection` enum
(`Route.swift`, `Route.homepanel(HomepanelSection)`), teach
`RouteBuilder.makeRoute` to map the `/homepanel/worldcup` path (or a
`homepanel?section=worldcup` host) to it, and have `BrowserCoordinator.handle`
open the homepage. v1 scope = open the homepage only; scrolling / animating to
the specific WorldCup card is an OPTIONAL stretch task in the plan (do not couple
to homepage scroll internals).

Rejected Option B (a brand-new `Route.worldCup` case): touches every exhaustive
`Route` switch for little gain.

## Section 6: Testing

Tier 1 - Mapper unit tests (core, ActivityKit-free, no simulator):
`firefox-ios-tests/Tests/ClientTests/WorldCup/WorldCupLiveActivityMapperTests.swift`.
`WorldCupLiveActivityMapper` is a pure fn `WorldCupSectionState -> ContentState?`.
Tests: current-match selection (isLive preferred, else most-recent / in-progress
fallback); next-match selection (earliest upcoming, nil when none); field-copy
fidelity (scoreText / clockText / codes / flags / phaseTitle copied from the
chosen `WorldCupMatch`; scoreText nil not-started, clockText nil not-live);
end-condition signals (`selectedCountryId` nil -> mapper nil; both currentMatch
and nextMatch nil -> nil); staleness `lastUpdated` set + Codable encode/decode
round-trip.

Tier 2 - Manager logic tests (light, `@available(iOS 17, *)`): inject a thin
protocol seam over `Activity.request/update/end` so branches are testable
without live ActivityKit: feature-flag-disabled -> no-op; activities-not-enabled
-> no-op; same-team `didUpdate` -> update path; different-team `selectTeam` ->
end + start; nil `countryId` -> end. Mirrors `DownloadLiveActivityTest.swift`
structure.

Tier 3 - Manual QA checklist (in the plan, not automated): follow a team during
a live match -> activity on Lock Screen + Dynamic Island; score updates on
foreground; change team -> old ends / new starts; eliminated / last match ->
ends with linger; tap -> opens homepage WorldCup card.

Out of scope for v1: SwiftUI snapshot tests of the Live Activity views (no
supported headless render for `ActivityConfiguration`; manual QA covers this).
