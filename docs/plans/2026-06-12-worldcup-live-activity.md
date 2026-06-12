# WorldCup Live Activity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an iOS Live Activity (Lock Screen + Dynamic Island) that starts when a user follows a WorldCup team, shows that team's live/current match score plus their next fixture, updates from the existing WorldCup polling feed, and ends when the team is no longer relevant.

**Architecture:** Middleware-driven orchestrator. A new `@MainActor` `WorldCupLiveActivityManager` is called by `WorldCupMiddleware` on the two events it already handles (`selectTeam`, `didUpdate`). A pure `WorldCupLiveActivityMapper` turns `WorldCupSectionState` into a Codable `ContentState`. The Live Activity UI lives in the existing WidgetKit extension. Reuses the `worldCupWidget` Nimbus flag, the `group.org.mozilla.ios.<flavor>` App Group, and the iOS 17+ availability gate already used by the Download Live Activity.

**Tech Stack:** Swift 6.3, ActivityKit, WidgetKit, SwiftUI, Redux (BrowserKit), Swift Testing / XCTest. Build/test via `fxios test` (Homebrew Swift-ArgumentParser CLI wrapping xcodebuild, Fennec scheme).

**Design reference:** `docs/plans/2026-06-12-worldcup-live-activity-design.md`

**Template files to mirror (read these first):**
- `WidgetKit/DownloadManager/DownloadLiveActivity.swift` (attributes + Widget + DynamicIsland)
- `WidgetKit/WidgetKit.swift` (bundle registration, iOS 17 gate)
- `Client/Frontend/Browser/DownloadHelper/DownloadLiveActivityWrapper.swift` (request/update/end)
- `Client/Utils/DownloadLiveActivityUtil.swift` (content-state building)
- `firefox-ios-tests/Tests/ClientTests/Downloads/DownloadLiveActivityTest.swift` (test style)

**Key existing files to modify:**
- `Client/Frontend/Home/Homepage/WorldCup/WorldCupMiddleware.swift` (worldCupProvider L34-56; selectTeam L47-50; startFeed L58-64; dispatches `WorldCupAction(.didUpdate, selectedCountryId:)`)
- `WidgetKit/WidgetKit.swift`
- `Client/Coordinators/Router/Route.swift` (`Route.homepanel(HomepanelSection)` L42; nested `HomepanelSection` enum)
- `Client/Coordinators/Router/RouteBuilder.swift` (`makeRoute(url:)` L41-178)
- `Client/Coordinators/Browser/BrowserCoordinator.swift` (`canHandle`/`handle` L295-351)

**Source-of-truth model facts:**
- `WorldCupSectionState`: `windowUUID, shouldShowSection, isMilestone2, hasWorldCupStarted, selectedCountryId: String?, matches: [WorldCupMatches], apiError, defaultMatchIndex`.
- `WorldCupMatches`: `phaseTitle, telemetryPhaseValue, dateLabel: String?, isLive: Bool, featuredMatch: [WorldCupMatch], upcomingMatches: [WorldCupMatch]`.
- `WorldCupMatch`: `homeFlagAssetName, homeCode, awayFlagAssetName, awayCode, date: String, score: Score?, winnerKey: String?`; `Score { score: String "2 - 1"; clock: String "45'" }`.
- `WorldCupStore.isFeatureEnabled` = `featureFlagsProvider.isEnabled(.worldCupWidget)`; `WorldCupStore.selectedTeam` reads the persisted FIFA code.
- `WorldCupCountry.localizedName(forID:)` gives the localized team display name.

**Conventions:**
- All Live Activity code MUST be `@available(iOS 17, *)` (deployment floor is iOS 15).
- NO em dashes (U+2014) anywhere. Use hyphens or parentheses.
- Comments only where non-trivial (per repo AGENTS.md).
- Add every new file to the correct Xcode target(s) in `Client.xcodeproj/project.pbxproj`. The attributes file must be a member of BOTH the `Client` app target AND the `WidgetKitExtension` target. The Widget/UI files are WidgetKitExtension only. The manager/mapper are `Client` only. Tests go in the `ClientTests` target.

---

## Task 0: Branch and baseline

**Step 1:** Confirm clean tree on a feature branch.

Run: `git status` then `git checkout -b nb/worldcup-live-activity`
Expected: new branch created from current `main`.

**Step 2:** Read the five template files listed above to internalize the exact APIs (`Activity.request`, `ActivityConfiguration`, `DynamicIsland`, `ActivityAuthorizationInfo`).

**Step 3:** Commit nothing yet (no changes).

---

## Task 1: Activity attributes + ContentState (the app/widget contract)

**Files:**
- Create: `WidgetKit/WorldCup/WorldCupLiveActivityAttributes.swift`
- pbxproj: add file to BOTH `Client` and `WidgetKitExtension` targets.

**Step 1: Write the type.** Mirror `DownloadLiveActivityAttributes`.

```swift
import Foundation
import ActivityKit

@available(iOS 17, *)
public struct WorldCupLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var currentMatch: MatchSnapshot?
        public var nextMatch: MatchSnapshot?
        public var lastUpdated: Date

        public init(currentMatch: MatchSnapshot?, nextMatch: MatchSnapshot?, lastUpdated: Date) {
            self.currentMatch = currentMatch
            self.nextMatch = nextMatch
            self.lastUpdated = lastUpdated
        }
    }

    public struct MatchSnapshot: Codable, Hashable {
        public var homeCode: String
        public var awayCode: String
        public var homeFlagAsset: String
        public var awayFlagAsset: String
        public var scoreText: String?
        public var clockText: String?
        public var isLive: Bool
        public var kickoffText: String?
        public var phaseTitle: String

        public init(homeCode: String, awayCode: String, homeFlagAsset: String, awayFlagAsset: String,
                    scoreText: String?, clockText: String?, isLive: Bool, kickoffText: String?, phaseTitle: String) {
            self.homeCode = homeCode
            self.awayCode = awayCode
            self.homeFlagAsset = homeFlagAsset
            self.awayFlagAsset = awayFlagAsset
            self.scoreText = scoreText
            self.clockText = clockText
            self.isLive = isLive
            self.kickoffText = kickoffText
            self.phaseTitle = phaseTitle
        }
    }

    public var teamCode: String
    public var teamDisplayName: String

    public init(teamCode: String, teamDisplayName: String) {
        self.teamCode = teamCode
        self.teamDisplayName = teamDisplayName
    }
}
```

**Step 2: Add to targets.** Open `Client.xcodeproj`, add the new file to target membership `Client` AND `WidgetKitExtension` (mirror how `DownloadLiveActivity.swift`/its attributes are shared). Verify in the File Inspector.

**Step 3: Build.** Run: `fxios build -p firefox`
Expected: compiles in both targets, no errors.

**Step 4: Commit.**

```bash
git add WidgetKit/WorldCup/WorldCupLiveActivityAttributes.swift firefox-ios/Client.xcodeproj/project.pbxproj
git commit -m "feat(worldcup): add Live Activity attributes and content state"
```

---

## Task 2: Mapper (pure WorldCupSectionState -> ContentState?) - TDD

This is the core testable logic. No ActivityKit import; operate on the
`WorldCupLiveActivityAttributes.ContentState` and `MatchSnapshot` value types
(those are `@available(iOS 17, *)`, so the mapper and its tests are gated too).

**Files:**
- Create: `Client/Frontend/Home/Homepage/WorldCup/WorldCupLiveActivityMapper.swift`
- Test: `firefox-ios-tests/Tests/ClientTests/WorldCup/WorldCupLiveActivityMapperTests.swift`
- pbxproj: mapper -> `Client`; test -> `ClientTests`.

**Step 1: Write failing tests.** Cover the locked behaviors.

```swift
import XCTest
@testable import Client

@available(iOS 17, *)
final class WorldCupLiveActivityMapperTests: XCTestCase {
    // Helpers build WorldCupSectionState with controlled matches.

    func testReturnsNilWhenNoTeamSelected() {
        let state = makeState(selectedCountryId: nil, matches: [liveCard()])
        XCTAssertNil(WorldCupLiveActivityMapper.contentState(from: state))
    }

    func testReturnsNilWhenNoCurrentAndNoNextMatch() {
        let state = makeState(selectedCountryId: "BRA", matches: [])
        XCTAssertNil(WorldCupLiveActivityMapper.contentState(from: state))
    }

    func testPrefersLiveMatchAsCurrent() {
        let state = makeState(selectedCountryId: "BRA", matches: [liveCard()])
        let cs = WorldCupLiveActivityMapper.contentState(from: state)
        XCTAssertEqual(cs?.currentMatch?.isLive, true)
        XCTAssertEqual(cs?.currentMatch?.scoreText, "2 - 1")
        XCTAssertEqual(cs?.currentMatch?.clockText, "45'")
    }

    func testNextMatchIsEarliestUpcoming() {
        let state = makeState(selectedCountryId: "BRA", matches: [upcomingOnlyCard()])
        let cs = WorldCupLiveActivityMapper.contentState(from: state)
        XCTAssertNil(cs?.currentMatch)
        XCTAssertNotNil(cs?.nextMatch)
        XCTAssertNil(cs?.nextMatch?.scoreText) // not started
    }

    func testFieldCopyFidelity() {
        let cs = WorldCupLiveActivityMapper.contentState(from: makeState(selectedCountryId: "BRA", matches: [liveCard()]))
        let m = cs?.currentMatch
        XCTAssertEqual(m?.homeCode, "BRA")
        XCTAssertEqual(m?.awayCode, "ARG")
        XCTAssertEqual(m?.phaseTitle, "Group Stage")
    }

    func testContentStateCodableRoundTrip() throws {
        let cs = WorldCupLiveActivityMapper.contentState(from: makeState(selectedCountryId: "BRA", matches: [liveCard()]))!
        let data = try JSONEncoder().encode(cs)
        let decoded = try JSONDecoder().decode(WorldCupLiveActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, cs)
    }
}
```

Add private helpers in the test file (`makeState`, `liveCard`, `upcomingOnlyCard`) that build real `WorldCupSectionState` / `WorldCupMatches` / `WorldCupMatch` values. Inspect those initializers in the WorldCup source to get exact argument labels before writing the helpers.

**Step 2: Run, verify fail.**
Run: `fxios test --filter WorldCupLiveActivityMapperTests`
Expected: FAIL (type `WorldCupLiveActivityMapper` not found).

**Step 3: Implement the mapper.**

```swift
import Foundation

@available(iOS 17, *)
enum WorldCupLiveActivityMapper {
    static func contentState(
        from state: WorldCupSectionState,
        now: Date = Date()
    ) -> WorldCupLiveActivityAttributes.ContentState? {
        guard state.selectedCountryId != nil else { return nil }

        let current = currentMatch(in: state.matches)
        let next = nextMatch(in: state.matches)
        guard current != nil || next != nil else { return nil }

        return .init(currentMatch: current, nextMatch: next, lastUpdated: now)
    }

    private static func currentMatch(in cards: [WorldCupMatches]) -> WorldCupLiveActivityAttributes.MatchSnapshot? {
        // Prefer a live featured match, else the most recent featured match.
        if let liveCard = cards.first(where: { $0.isLive }),
           let match = liveCard.featuredMatch.first {
            return snapshot(from: match, phaseTitle: liveCard.phaseTitle, isLive: true)
        }
        if let card = cards.first(where: { !$0.featuredMatch.isEmpty }),
           let match = card.featuredMatch.first {
            return snapshot(from: match, phaseTitle: card.phaseTitle, isLive: card.isLive)
        }
        return nil
    }

    private static func nextMatch(in cards: [WorldCupMatches]) -> WorldCupLiveActivityAttributes.MatchSnapshot? {
        for card in cards {
            if let upcoming = card.upcomingMatches.first {
                return snapshot(from: upcoming, phaseTitle: card.phaseTitle, isLive: false)
            }
        }
        return nil
    }

    private static func snapshot(from match: WorldCupMatch, phaseTitle: String, isLive: Bool) -> WorldCupLiveActivityAttributes.MatchSnapshot {
        .init(
            homeCode: match.homeCode,
            awayCode: match.awayCode,
            homeFlagAsset: match.homeFlagAssetName,
            awayFlagAsset: match.awayFlagAssetName,
            scoreText: match.score?.score,
            clockText: isLive ? match.score?.clock : nil,
            isLive: isLive,
            kickoffText: isLive ? nil : match.date,
            phaseTitle: phaseTitle
        )
    }
}
```

Note: adjust `currentMatch`/`nextMatch` selection to match the real shape of `WorldCupMatches` (featured vs upcoming) discovered while writing test helpers. Keep the public contract (`contentState(from:now:)`) stable.

**Step 4: Run, verify pass.**
Run: `fxios test --filter WorldCupLiveActivityMapperTests`
Expected: PASS (all cases).

**Step 5: Commit.**

```bash
git add firefox-ios/Client/Frontend/Home/Homepage/WorldCup/WorldCupLiveActivityMapper.swift firefox-ios/firefox-ios-tests/Tests/ClientTests/WorldCup/WorldCupLiveActivityMapperTests.swift firefox-ios/Client.xcodeproj/project.pbxproj
git commit -m "feat(worldcup): add Live Activity state mapper with tests"
```

---

## Task 3: ActivityKit seam protocol (for testable manager)

To unit-test the manager without a live ActivityKit runtime, define a thin
protocol the manager depends on, plus a real implementation.

**Files:**
- Create: `Client/Frontend/Home/Homepage/WorldCup/WorldCupLiveActivityControlling.swift`
- pbxproj: `Client` target.

**Step 1: Define the seam.**

```swift
import Foundation

@available(iOS 17, *)
protocol WorldCupLiveActivityControlling: AnyObject {
    var hasActiveActivity: Bool { get }
    var activeTeamCode: String? { get }
    var areActivitiesEnabled: Bool { get }

    func start(attributes: WorldCupLiveActivityAttributes,
               content: WorldCupLiveActivityAttributes.ContentState)
    func update(content: WorldCupLiveActivityAttributes.ContentState)
    func end(content: WorldCupLiveActivityAttributes.ContentState?)
}
```

**Step 2: Real implementation wrapping `Activity`.** Mirror `DownloadLiveActivityWrapper` (`.request`, `.update(using:)`, `.end(using:dismissalPolicy:)`). Use `ActivityAuthorizationInfo().areActivitiesEnabled`. Track `activeTeamCode` from the activity attributes. End uses `.end(using: content, dismissalPolicy: .after(Date().addingTimeInterval(60 * 60 * 3)))` (about 3h linger).

```swift
import Foundation
import ActivityKit

@available(iOS 17, *)
final class WorldCupLiveActivityController: WorldCupLiveActivityControlling {
    private var activity: Activity<WorldCupLiveActivityAttributes>?

    var hasActiveActivity: Bool { activity != nil }
    var activeTeamCode: String? { activity?.attributes.teamCode }
    var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(attributes: WorldCupLiveActivityAttributes,
               content: WorldCupLiveActivityAttributes.ContentState) {
        guard activity == nil else { return }
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: content, staleDate: nil)
            )
        } catch {
            activity = nil
        }
    }

    func update(content: WorldCupLiveActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(.init(state: content, staleDate: nil)) }
    }

    func end(content: WorldCupLiveActivityAttributes.ContentState?) {
        guard let activity else { return }
        let dismissal: ActivityUIDismissalPolicy = .after(Date().addingTimeInterval(60 * 60 * 3))
        Task {
            if let content {
                await activity.end(.init(state: content, staleDate: nil), dismissalPolicy: dismissal)
            } else {
                await activity.end(nil, dismissalPolicy: dismissal)
            }
        }
        self.activity = nil
    }
}
```

Verify the exact `ActivityContent` / `.end` signatures against the iOS 17 SDK and the Download wrapper before finalizing.

**Step 3: Build.** Run: `fxios build -p firefox` -> compiles.

**Step 4: Commit.**

```bash
git add firefox-ios/Client/Frontend/Home/Homepage/WorldCup/WorldCupLiveActivityControlling.swift firefox-ios/Client.xcodeproj/project.pbxproj
git commit -m "feat(worldcup): add Live Activity control seam and ActivityKit wrapper"
```

---

## Task 4: Manager orchestration - TDD

**Files:**
- Create: `Client/Frontend/Home/Homepage/WorldCup/WorldCupLiveActivityManager.swift`
- Test: `firefox-ios-tests/Tests/ClientTests/WorldCup/WorldCupLiveActivityManagerTests.swift`
- pbxproj: manager -> `Client`; test -> `ClientTests`.

**Step 1: Write failing tests with a fake controller.**

```swift
import XCTest
@testable import Client

@available(iOS 17, *)
final class WorldCupLiveActivityManagerTests: XCTestCase {
    final class FakeController: WorldCupLiveActivityControlling {
        var hasActiveActivity = false
        var activeTeamCode: String?
        var areActivitiesEnabled = true
        var startCount = 0, updateCount = 0, endCount = 0

        func start(attributes: WorldCupLiveActivityAttributes, content: WorldCupLiveActivityAttributes.ContentState) {
            startCount += 1; hasActiveActivity = true; activeTeamCode = attributes.teamCode
        }
        func update(content: WorldCupLiveActivityAttributes.ContentState) { updateCount += 1 }
        func end(content: WorldCupLiveActivityAttributes.ContentState?) {
            endCount += 1; hasActiveActivity = false; activeTeamCode = nil
        }
    }

    func testNoOpWhenFeatureDisabled() { /* isFeatureEnabled=false -> startCount==0 */ }
    func testNoOpWhenActivitiesNotEnabled() { /* areActivitiesEnabled=false -> startCount==0 */ }
    func testSelectTeamStartsActivity() { /* non-nil id, live match -> startCount==1 */ }
    func testNilCountryEndsActivity() { /* active, then selectTeam nil -> endCount==1 */ }
    func testDifferentTeamEndsThenStarts() { /* active BRA, selectTeam ARG -> endCount==1, startCount==2 */ }
    func testDidUpdateUpdatesWhenActive() { /* active, didUpdate same team -> updateCount==1 */ }
    func testDidUpdateEndsWhenNoCurrentNoNext() { /* active, mapper nil -> endCount==1 */ }
}
```

Inject `isFeatureEnabled: Bool` and the `teamDisplayName` lookup so tests do not need the real Nimbus/store. Build state via the same helpers as Task 2 (factor them into a shared test helper file if convenient).

**Step 2: Run, verify fail.**
Run: `fxios test --filter WorldCupLiveActivityManagerTests`
Expected: FAIL (manager not found).

**Step 3: Implement the manager.**

```swift
import Foundation

@available(iOS 17, *)
@MainActor
final class WorldCupLiveActivityManager {
    private let controller: WorldCupLiveActivityControlling
    private let isFeatureEnabled: () -> Bool
    private let displayName: (String) -> String

    init(controller: WorldCupLiveActivityControlling = WorldCupLiveActivityController(),
         isFeatureEnabled: @escaping () -> Bool,
         displayName: @escaping (String) -> String = { WorldCupCountry.localizedName(forID: $0) }) {
        self.controller = controller
        self.isFeatureEnabled = isFeatureEnabled
        self.displayName = displayName
    }

    // Called by middleware on selectTeam.
    func handleSelectTeam(state: WorldCupSectionState) {
        guard isFeatureEnabled(), controller.areActivitiesEnabled else { return }
        guard let teamCode = state.selectedCountryId else {
            controller.end(content: nil)
            return
        }
        guard let content = WorldCupLiveActivityMapper.contentState(from: state) else {
            controller.end(content: nil)
            return
        }
        if controller.hasActiveActivity, controller.activeTeamCode != teamCode {
            controller.end(content: nil)
        }
        if !controller.hasActiveActivity {
            let attrs = WorldCupLiveActivityAttributes(teamCode: teamCode, teamDisplayName: displayName(teamCode))
            controller.start(attributes: attrs, content: content)
        } else {
            controller.update(content: content)
        }
    }

    // Called by middleware on didUpdate.
    func handleDidUpdate(state: WorldCupSectionState) {
        guard isFeatureEnabled(), controller.areActivitiesEnabled else { return }
        guard controller.hasActiveActivity else {
            // Cold-start reconcile: start if a team is followed and there is content.
            handleSelectTeam(state: state)
            return
        }
        guard let content = WorldCupLiveActivityMapper.contentState(from: state) else {
            controller.end(content: nil)
            return
        }
        controller.update(content: content)
    }
}
```

Adjust `WorldCupCountry.localizedName` call to its real signature.

**Step 4: Run, verify pass.**
Run: `fxios test --filter WorldCupLiveActivityManagerTests`
Expected: PASS.

**Step 5: Commit.**

```bash
git add firefox-ios/Client/Frontend/Home/Homepage/WorldCup/WorldCupLiveActivityManager.swift firefox-ios/firefox-ios-tests/Tests/ClientTests/WorldCup/WorldCupLiveActivityManagerTests.swift firefox-ios/Client.xcodeproj/project.pbxproj
git commit -m "feat(worldcup): add Live Activity manager with orchestration tests"
```

---

## Task 5: Wire the manager into WorldCupMiddleware

**Files:**
- Modify: `Client/Frontend/Home/Homepage/WorldCup/WorldCupMiddleware.swift`

**Step 1:** Add an `@available(iOS 17, *)` lazily-created `WorldCupLiveActivityManager` to the middleware, constructed with `isFeatureEnabled: { worldCupStore.isFeatureEnabled }`. Guard creation behind `if #available(iOS 17, *)`.

**Step 2:** In the `selectTeam` branch (after `setSelectedTeam` + `startFeed`), call `liveActivityManager.handleSelectTeam(state:)`. The middleware has `AppState`; obtain the current `WorldCupSectionState` for `action.windowUUID` the same way the reducer/section does (mirror how the cell reads section state). If only the post-`didUpdate` state is reliable, defer the start to the next `didUpdate` (the cold-start reconcile path handles this) and on `selectTeam` only handle the nil/teardown case immediately.

**Step 3:** In the `dispatch(snapshot:)` path that fires `WorldCupAction(.didUpdate, selectedCountryId:)`, after dispatch, build the `WorldCupSectionState` you just dispatched and call `liveActivityManager.handleDidUpdate(state:)`. Reuse the already-built snapshot data to avoid recomputation.

**Step 4: Build + run existing WorldCup tests.**
Run: `fxios test --filter WorldCup`
Expected: PASS (no regressions; mapper/manager tests still green).

**Step 5: Commit.**

```bash
git add firefox-ios/Client/Frontend/Home/Homepage/WorldCup/WorldCupMiddleware.swift
git commit -m "feat(worldcup): drive Live Activity from WorldCup middleware"
```

---

## Task 6: Live Activity UI (Widget + Dynamic Island)

**Files:**
- Create: `WidgetKit/WorldCup/WorldCupLiveActivity.swift`
- Modify: `WidgetKit/WidgetKit.swift`
- pbxproj: new file -> `WidgetKitExtension`.

**Step 1:** Implement `@available(iOS 17, *) struct WorldCupLiveActivity: Widget` with `ActivityConfiguration(for: WorldCupLiveActivityAttributes.self)`. Mirror `DownloadLiveActivity.swift` structure exactly.

Lock Screen view: top row home flag+code, score (`scoreText` or "vs"), away code+flag, clock + red "LIVE" dot when `isLive`; phase title small/secondary; if `nextMatch != nil` a divider + "Next:" line (two codes + `kickoffText`); if `currentMatch == nil` the next match is the hero row. Staleness: if `Date.now - lastUpdated > 5 * 60` and live, render clock in `.secondary`.

Dynamic Island: `.leading` home flag+code; `.trailing` away code+flag; `.center` score+clock (or kickoff); `.bottom` phase title + optional "Next:"; `compactLeading` home flag/code; `compactTrailing` score if live else kickoff; `minimal` followed-team flag.

Flags: `Image(code)` with a text-code fallback view (see Task 7). Whole surface: `.widgetURL(URL(string: "firefox://deep-link?url=/homepanel/worldcup"))`.

**Step 2:** Register in `WidgetKit/WidgetKit.swift` `FirefoxWidgets` body behind `if #available(iOS 17, *) { WorldCupLiveActivity() }` (same place `DownloadLiveActivity()` is registered).

**Step 3: Build the widget extension.**
Run: `fxios build -p firefox`
Expected: compiles; both `DownloadLiveActivity` and `WorldCupLiveActivity` registered.

**Step 4: Commit.**

```bash
git add WidgetKit/WorldCup/WorldCupLiveActivity.swift WidgetKit/WidgetKit.swift firefox-ios/Client.xcodeproj/project.pbxproj
git commit -m "feat(worldcup): add Live Activity Lock Screen and Dynamic Island UI"
```

---

## Task 7: Flag assets in the widget target + text fallback

**Files:**
- Modify: widget UI (flag rendering helper)
- Assets: ensure WorldCup flag image assets are a target member of `WidgetKitExtension`, OR confirm they are not and rely on fallback.

**Step 1:** Determine whether the flag asset catalog used by `Image(country.id)` is included in the WidgetKitExtension target. Search the asset catalog membership in pbxproj / `.xcassets` location.

**Step 2:** Implement a small `FlagView(code:)` helper: render `Image(code)` if the asset resolves, otherwise render the 3-letter code in a capsule. Because `UIImage(named:)` availability cannot be assumed at SwiftUI compile time, prefer: try the asset, and ALWAYS keep the code label as an accessibility label so meaning survives a missing image.

**Step 3:** If assets are NOT in the widget target and adding the full catalog is heavy, ship v1 with the text-code rendering (FIFA codes) and file a follow-up to add flag assets. Decision recorded here: text-code fallback is the acceptable v1 baseline.

**Step 4: Build + visual smoke (simulator).**
Run: `fxios build-run -p firefox` then trigger a follow on a seeded live match (see Task 9 QA) and inspect the Lock Screen.

**Step 5: Commit.**

```bash
git add -A
git commit -m "feat(worldcup): flag rendering with text-code fallback in widget target"
```

---

## Task 8: Deep link (Route.homepanel + HomepanelSection.worldCup)

**Files:**
- Modify: `Client/Coordinators/Router/Route.swift` (add `case worldCup` to nested `HomepanelSection`)
- Modify: `Client/Coordinators/Router/RouteBuilder.swift` (`makeRoute(url:)`)
- Modify: `Client/Coordinators/Browser/BrowserCoordinator.swift` (`handle` for `.homepanel(.worldCup)`)
- Test: extend an existing RouteBuilder test if one exists; otherwise add `firefox-ios-tests/Tests/ClientTests/Coordinators/RouteBuilderWorldCupTests.swift`.

**Step 1: Failing test** that `RouteBuilder.makeRoute(url: "firefox://deep-link?url=/homepanel/worldcup")` returns `.homepanel(.worldCup)` (match the actual deep-link URL convention used by existing homepanel routes - inspect `makeRoute` first and copy the exact pattern).

Run: `fxios test --filter RouteBuilderWorldCup`
Expected: FAIL.

**Step 2:** Add `case worldCup` to `HomepanelSection`. Map the path in `makeRoute`. In `BrowserCoordinator.handle`, route `.homepanel(.worldCup)` to show the homepage (reuse the existing homepanel/home handling; do NOT couple to scroll internals). Scrolling to the specific card is an optional stretch, not in v1.

**Step 3:** Run test -> PASS. Build -> compiles (all exhaustive `HomepanelSection` switches updated).

Run: `fxios test --filter RouteBuilderWorldCup`
Expected: PASS.

**Step 4: Commit.**

```bash
git add -A
git commit -m "feat(worldcup): deep link Live Activity tap to homepage WorldCup card"
```

---

## Task 9: Manual QA checklist (not automated)

Document and execute on a simulator / device with the `worldCupWidget` flag enabled and a seeded live match window (use the `WorldCupBaseHost` / `WorldCupPollInterval` dev prefs and date pinning if needed).

- Follow a team during a live match -> activity appears on Lock Screen + Dynamic Island.
- Score/clock updates when app foregrounds.
- Change team -> old activity ends, new one starts.
- Unfollow -> activity ends.
- Team eliminated / last match -> activity ends and lingers ~3h.
- Tap activity -> Firefox opens to the homepage WorldCup card.
- iOS 16 / 15 device or activities-disabled -> no crash, no activity (guards hold).

Record results in the PR description.

---

## Task 10: Full test pass + PR

**Step 1:** Run the full WorldCup + Live Activity test set.
Run: `fxios test --filter WorldCup` and `fxios test --filter LiveActivity`
Expected: all PASS.

**Step 2:** Run SwiftLint (build phase) clean; ensure no em dashes introduced.

**Step 3:** Open PR using `PULL_REQUEST_TEMPLATE`, fill relevant sections, link the Bugzilla/JIRA ticket number (from the ticket). Summarize: design doc link, the six approved sections, manual QA results, and the flag-asset fallback decision.

**Step 4:** Request review (use requesting-code-review skill).

---

## Notes / Risks

- Reading section state inside the middleware: confirm the exact accessor for `WorldCupSectionState` by window before Task 5; if awkward, lean on the `didUpdate` cold-start reconcile path so `selectTeam` only needs to handle teardown.
- ActivityKit API exact signatures (`ActivityContent`, `.end`, `staleDate`) must be verified against the iOS 17 SDK and the Download wrapper - do not guess; copy the working pattern.
- Flag assets in the widget process are the main UI risk; text-code fallback de-risks v1.
- LSP may show phantom "No such module Redux/Common" - that is an SPM artifact, not a real error; trust `fxios build`.
