# Architectural decisions — FXIOS-16660

Decisions are numbered and immutable; a superseded decision gets a new entry that references it.

---

## D-001 — Strangler-fig migration, not a big-bang rewrite

> **Partially superseded by D-016.** The strangler-fig method stands; the final-phase deletion of
> the Redux core does not — a reduced core is retained as the browser event bus.

**Context.** 274 files and ~54k LOC depend on Redux, and `AppState` is a single enum-of-screens
that every reducer and middleware pattern-matches on. A single atomic swap would be unreviewable
and unbisectable.

**Decision.** Redux and MVVM coexist. A module leaves `PresentedComponentsState` only when its
view model is in place. The Redux core is deleted in the final phase, once the last consumer is gone.

**Consequence.** The app builds and runs green after every commit. The `Redux` import lingers in
`AppState.swift` until Phase 4, which is expected, not debt.

---

## D-002 — Swift Concurrency, not Combine

**Context.** The ticket originally said "MVVM + Combine"; the final PR title specifies
"Swift Concurrency Async Await based where applicable but not combine".

**Decision.** No `import Combine` is added. Side effects that were middleware closures become
`async` methods awaited from `@MainActor` view models.

**Rationale.** The middlewares are overwhelmingly *imperative one-shot effects* (submit a report,
fetch top sites, record telemetry), not stream compositions — `async`/`await` expresses those
directly, and `Publisher` chains would add a second concurrency model alongside the Swift
Concurrency the codebase is already adopting (`@MainActor` is on `Store`, `Middleware`, and most
view controllers).

---

## D-003 — State is published via a single `onStateChange` closure

**Context.** Consumers are UIKit view controllers, not SwiftUI. Options considered:
`ObservableObject` + `@Published`, `AsyncStream`, the Observation framework (`@Observable`),
and a plain closure.

**Decision.** Each view model exposes:

```swift
private(set) var state: XxxState { didSet { onStateChange?(state) } }
var onStateChange: ((XxxState) -> Void)?
```

**Rationale.**
- `@Published` requires Combine (excluded by D-002).
- `AsyncStream` forces every view controller to own a `Task` and a cancellation path — more
  ceremony than a UIKit screen needs, and it makes updates arrive on a later turn of the run loop,
  which changes UIKit layout timing versus today's synchronous `newState(state:)`.
- A closure is a **1:1 replacement for `StoreSubscriber.newState(state:)`** — same synchronous,
  same-tick delivery — so migrating a screen does not change its update semantics. That keeps the
  diff about architecture, not about timing regressions.
- `@Observable` is the right long-term answer for SwiftUI-backed screens and is used where the
  screen is already SwiftUI; it is not forced onto UIKit screens.

**Consequence.** `state` is settable only inside the view model, preserving the
"state changes in one place" property that Redux provided, minus the indirection.

---

## D-004 — Cross-module action listening becomes explicit delegation

**Context.** Redux let any middleware observe any action. `TabManagerMiddleware` alone reacts to
9 foreign action types (`HomepageAction`, `MainMenuAction`, `ShortcutsLibraryAction`, …). This
implicit coupling is the single hardest part of the migration.

**Decision.** Each such edge becomes an explicit, typed dependency — a `weak var delegate` or an
injected protocol — declared at the boundary and satisfied by the owning coordinator.

**Rationale.** It makes the dependency graph visible to the compiler and to reviewers. Where Redux
hid a fan-out behind a string of `as?` casts, the delegate protocol names it.

**Consequence.** Some fan-outs (one action, many listeners) become several delegate calls. Where a
true broadcast is needed, the owning coordinator does the fan-out rather than every listener
sniffing the global action stream.

---

## D-005 — `windowUUID` stays; view models are per-window

**Context.** Redux supports iPad multi-window by keying every screen state and action with a
`WindowUUID`, letting two windows hold two `HomepageState`s at once.

**Decision.** Keep `windowUUID` as a stored property on each view model. View models are created
and owned by the per-window coordinator, so window scoping is enforced by ownership instead of by
UUID filtering inside reducers.

**Rationale.** Ownership is a stronger guarantee than a `guard action.windowUUID == state.windowUUID`
check that every reducer had to remember to write. It also deletes that boilerplate from ~47 action
handlers.

---

## D-006 — Intents stay `@MainActor`; `await` only around real I/O

**Context.** `Store.dispatch` queued actions so each fully passed through reducers and middlewares
before the next began. Naive `async` intents would lose that serialization and allow interleaving.

**Decision.** View models are `@MainActor`. Intent methods are synchronous where the effect is
synchronous; `async` appears only where the old middleware itself did I/O. State mutation happens
on the main actor before and after each `await`.

**Rationale.** Preserves the ordering guarantee for everything that was already synchronous, and
scopes the genuinely concurrent surface to the handful of places that actually touch disk/network.

**Consequence.** Any state read across an `await` must be re-read afterwards, not captured before —
enforced by review, and by keeping `state` a `private(set)` stored property rather than a captured value.

---

## D-007 — Reducer tests are rewritten as view-model tests before the reducer is deleted

**Context.** State reducers have substantial test coverage (e.g. `WebCompatReporterStateTests`,
`HomepageStateTests`, `TabsPanelStateTests`) that encodes real product behaviour.

**Decision.** For each module, port the reducer tests to the view model **first**, in the same
commit that introduces the view model, and delete the reducer only once the ported tests pass.

**Rationale.** The reducer tests are the specification of the behaviour being moved. Deleting them
alongside the reducer would silently drop that spec; porting them first turns the migration into a
refactor verified by its own tests.

---

## D-008 — Middleware telemetry moves into the view model, not a separate service

**Context.** Middlewares mix genuine side effects (submit a report) with telemetry
(`telemetry.reasonSelected(category:)`).

**Decision.** Telemetry calls move onto the view model intent that triggers them, using the same
injected telemetry object the middleware used.

**Rationale.** Telemetry is a consequence of the user intent and belongs with it. Injecting the same
telemetry type keeps the existing telemetry tests meaningful.

---

## D-009 — Reducer tests that only exercised Redux plumbing are dropped, not ported

**Context.** Some reducer tests assert on Redux's own routing rather than on product behaviour —
`test_unknownAction_returnsDefaultState`, `test_actionWithDifferentWindowUUID_returnsDefaultState`,
and the transient-field tests (`test_previewPayload_doesNotSurviveTheNextAction`,
`test_actionAfterDidSubmit_clearsShouldDismiss`).

**Decision.** These are deleted rather than ported, and each deletion is noted in the module's
commit message.

**Rationale.** They test invariants that no longer exist. "An action for another window is ignored"
is meaningless once view models are owned per window (D-005). "The preview payload does not survive
the next action" existed only because a one-shot event had to be modelled as state that needed
clearing; as a callback there is nothing to clear. Porting them would mean inventing behaviour to
test.

**Consequence.** Per-module test counts drop even where product coverage is unchanged. The
migration must not be judged by test count alone — D-007 (port behaviour tests first) is the
coverage guarantee.

---

## D-010 — Parallel worktree migration is not used for module migrations

**Context.** The plan allows spawning sub-agents in worktrees for parallel work.

**Decision.** Module migrations run serially on one branch. Sub-agents are used for read-only
analysis briefs, which parallelise cleanly.

**Rationale.** Every module migration edits the same three shared files — `AppState.swift`,
`AppComponent.swift`, `PresentedComponentsState.swift` — and always at adjacent lines inside the
same switch statements. Parallel worktrees would conflict on every merge, and the conflicts would
be in exactly the code whose correctness the compiler can no longer check once a case is half-removed.
Serial migration keeps each module's build verifiably green.

---

## D-011 — Leaf modules keep `import Redux` for browser-level actions until Phase 3

> **Amended by D-016.** "Until Phase 3" is now "permanently": these dispatches are the retained
> browser event bus, not debt to be paid off.

**Context.** Analysis of NativeErrorPage and PasswordGenerator surfaced a coupling the
middleware map did not show: **31 files across 14 modules** dispatch `GeneralBrowserAction`,
`NavigationBrowserAction`, or `GeneralBrowserMiddlewareAction`. These are not the module's own
actions — they are requests *to* `BrowserViewController` ("reload this tab", "navigate back",
"show the password generator"). `NativeErrorPageViewController` alone dispatches five of them.

**Decision.** A Phase 1/2 module migration removes the module's **own** Redux — its `ScreenState`,
`Action` types, `Middleware`, and `StoreSubscriber` conformance — but leaves browser-level
dispatches in place. Such a module still has `import Redux` after its migration, and that is the
expected end state until `BrowserViewController` migrates in Phase 3.

**Rationale.** Converting a browser-level dispatch requires a `BrowserViewController` API to
convert it *to*, which does not exist until BVC itself is migrated. Inventing a parallel delegate
path early would mean two routes to the same behaviour and a second migration later.

**Consequence.** The `import Redux` file count (200) will not fall to zero linearly with module
count — it drops sharply in Phase 3 when BVC lands. Per-module completion must be judged by the
"Definition of done" in PLAN.md, not by the burn-down alone. WebCompatReporter is the exception
that reached zero in Phase 1: it dispatches no browser-level actions.

---

## D-012 — Coupling must be measured at the reducer level too, not just the middleware level

**Context.** The original phase ordering came from a middleware ⇢ action map. Module briefs then
showed that **reducers also consume foreign actions**: `AddressBarState` and `ToolbarState` both
reduce `SearchEngineSelectionAction`; `ShortcutsLibraryState` reduces `TopSitesAction`;
`BrowserViewControllerState` reduces seven foreign action types.

**Decision.** Phase membership is determined by three tests, all of which must pass for a module to
count as a Phase 1 leaf:

1. no foreign **middleware** consumes its actions,
2. no foreign **reducer** consumes its actions,
3. its own reducer consumes no foreign actions.

**Consequence.** Phase 1 shrinks from 8 modules to 5. SearchEngineSelection moves to Phase 3 (it is
effectively part of the Toolbar), ShortcutsLibrary to Phase 3 (Homepage/Tabs), StartAtHome to
Phase 3 (BrowserViewController), and TranslationSettings pairs with Translations in Phase 2.

**Rationale.** A middleware-only map understates coupling by about half. Migrating
SearchEngineSelection as a "leaf" would have left `AddressBarState` reducing an action type that no
longer exists — caught by the compiler, but only after the module had been rewritten around a wrong
assumption. Both maps are now generated by script and stored in FILES_TO_CHANGE.md.

---

## D-013 — `async` bridges must narrow non-`Sendable` callback payloads at the boundary

**Context.** Converting `PasswordGeneratorMiddleware` to `async`/`await` meant wrapping WebKit's
`evaluateJavascriptInDefaultContentWorld(_:_:_:)` in `withCheckedThrowingContinuation`. The
callback hands back `Any?`, which is not `Sendable`, so resuming the continuation with it fails
under Swift 6 concurrency checking: *"sending 'result' risks causing data races"*.

**Decision.** An `async` bridge over a completion handler converts the payload to a concrete
`Sendable` type **inside** the callback, before resuming. The bridge here is named
`evaluateStringInDefaultContentWorld(_:in:)` and returns `String?`, which is what both call sites
actually wanted.

**Rationale.** The alternative — marking things `@unchecked Sendable` or `nonisolated(unsafe)` —
reintroduces exactly the unsafety this migration is removing (see the `cachedPasswordRules` static
it replaced). Narrowing at the boundary is enforced by the compiler and makes the bridge's contract
narrower and clearer than the API it wraps.

**Consequence.** Expect this for every middleware that wrapped a completion handler. Three related
traps, all hit while migrating this one module:

- **Callback payload.** `Any?` cannot cross a continuation. Narrow it in the callback.
- **Stored non-`Sendable` service.** `await storedService.asyncMethod()` from a `@MainActor` type
  sends the stored property into a nonisolated context and is rejected. A *uniquely-referenced
  local* can cross, so construct the service inside the async function —
  `await RemoteSettingsUtils().fetchLocalRecords(…)`. This is what the old middleware did inside
  its `Task`, which is why the pattern only broke once the call was hoisted into a stored property.
  Testability is preserved by injecting the surrounding protocol (`PasswordRulesProviding`) rather
  than the service.
- **Task-based request coalescing.** A stored `Task` handle drags the fetched element type into
  `Sendable` territory for no real gain. `PasswordRulesProvider` dropped its in-flight dedup: the
  underlying read is a local JSON load, so a rare duplicate fetch is cheaper than the concurrency
  surface.

Budget for this. Three build cycles of this module's migration went to `Sendable` diagnostics
rather than to the architecture change itself.


---

## D-014 — Ownerless cross-module signals become notifications, not delegates

> **Narrowed by D-017.** With the bus retained, an ownerless *browser-level* signal goes on the bus;
> `NotificationCenter` is the last resort. The two signals below move to the bus in Phase 4.

**Context.** D-004 converts cross-module action listening into explicit delegation. TrackingProtection
broke that rule for two of its inbound edges: `TabContentBlocker` posts a blocked-tracker count
change and `BrowserViewController` posts a secure-content change, and **neither holds a reference to
the tracking protection screen**. There is no ownership path to hang a delegate on — which is
precisely why the original code reached for the global store.

**Decision.** Where the sender has no reference to the receiver and acquiring one would mean
inventing an ownership relationship, the signal becomes a `NotificationCenter` notification carrying
the `WindowUUID`. The receiving view model conforms to `Notifiable` and filters on that UUID.

**Rationale.** A delegate would require threading a reference from the coordinator through
`TabContentBlocker`, which is owned by the tab, not the screen — coupling two subsystems that are
currently independent, to replace one that was already decoupled. The notification keeps them
decoupled while making the payload and the window filter explicit.

**Consequence.** This is the first case where Redux was doing something a delegate genuinely cannot,
and it will recur. Use the D-004 delegate by default; reach for a notification only when the sender
provably has no reference to the receiver, and always carry the `WindowUUID` so the reducer's window
guard survives. The `@objc` handler cannot be actor-isolated, so it hops to `@MainActor` before
touching the delegate.

---

## D-015 — QuickAnswers and Summarizer are sub-features, not modules; they migrate with their host

**Context.** Both were scheduled as Phase 2 modules on the strength of their folder size and their
own middleware. Analysis shows neither is a screen: neither owns a `ScreenState`, neither appears in
`AppComponent`, and neither has a `StoreSubscriber`.

- QuickAnswers' state is `HeaderState.showQuickAnswersButton`, a Homepage section state whose
  reducer consumes `QuickAnswersMiddlewareAction`. `QuickAnswersMiddleware`'s entire job is to turn
  `HomepageActionType.initialize` / `.viewWillAppear` into that action.
- Summarizer's state is `BrowserViewControllerState.shouldShowReaderModeBarSummarizerButton`, and
  `SummarizerMiddleware` consumes `GeneralBrowserAction`, `NavigationBrowserAction` and
  `ToolbarAction`.

**Decision.** Move both to Phase 3. QuickAnswers migrates with Homepage; Summarizer migrates with
BrowserViewController and Toolbar.

**Rationale.** Migrating them now would mean either leaving the dispatch in place (achieving
nothing) or reaching into `HeaderState` and `BrowserViewControllerState` before those migrate —
the same mistake D-012 caught for SearchEngineSelection. There is no seam to cut at.

**Consequence.** Phase 2 is four items, not six. Both middlewares are *already* services in
practice: `HeaderState` default-constructs `QuickAnswersMiddleware()` as a `QuickAnswersStore`, and
`ToolbarMiddleware` and `TabManagerMiddleware` default-construct `SummarizerMiddleware()` as a
`SummarizerConfigFactory`. When their host migrates, the work is to keep those two protocols,
rename the implementations to `…Service`, and delete only the Redux plumbing — not to design
anything new.

---

## D-016 — The end state is MVVM plus a retained browser event bus, not full Redux removal

**Supersedes** the teardown clause of [D-001](#d-001) and the "until Phase 3" qualifier in
[D-011](#d-011).

**Context.** The goal inherited from the ticket title was "remove Redux". Phases 0–2 produced the
measurement that tests that goal:

| | Count |
| - | - |
| Files dispatching `GeneralBrowserAction` / `NavigationBrowserAction` / `GeneralBrowserMiddlewareAction` | 31 |
| Distinct module directories those senders live in | 15 |
| Consumers of those actions | 5 (`HomepageMiddleware`, `BrowserViewControllerState`, `ToolbarState`, `ToolbarMiddleware`, `SummarizeMiddleware`) |

The senders include `LoginsHelper`, `TabScrollController`, `TabContentBlocker`,
`TabManagerImplementation` and five already-migrated leaf screens. **None of them holds a
reference to Homepage, Toolbar or BrowserViewController**, and giving them one would mean
inventing an ownership relationship between subsystems that are deliberately independent.

That is exactly the condition D-014 identified — and D-014 treated it as an exception worth two
`NotificationCenter` posts. At 31 senders it is not an exception; it is the dominant shape of the
work that remains. Completing a pure-MVVM migration means converting all 31 into notifications:
an untyped global broadcast with a hand-written `windowUUID` filter at every receiver. That is
the same coupling the store already expresses, minus the type checking, minus the single place to
trace it, minus the compiler's help when a payload changes.

**Decision.** Redux is split into the two distinct jobs it was doing, and only one of them is
removed.

*Removed (unchanged from the original plan):* `AppState`, `ScreenState`, `AppComponent`,
`ComponentState`, `PresentedComponentsState`, every per-screen `…State` reducer, and every
registered middleware. This is where essentially all of the ~54k LOC and all of the ceremony
lives — the window guards, the `AppComponent` cases, the `as?` cast chains.

*Retained, permanently and by design:* the `Redux` module reduced to a typed, window-keyed
**browser event bus** — `Action`, `ActionType`, and `Store`'s dispatch/subscribe path — plus the
three browser-level action families. Screens subscribe to the bus for cross-cutting browser
events; they do not keep state in it.

**Rationale.** The two jobs have opposite cost/benefit.

1. *Screen state container.* One global tree holding 15 screens' state, pattern-matched by every
   reducer. Pure overhead for a screen only one object reads — this is what MVVM replaces, and
   Phase 1 demonstrated the win concretely (Microsurvey stored no state at all; NativeErrorPage's
   per-window bleed was a bug that ownership made unrepresentable).
2. *Many-to-many typed broadcast between ownerless peers.* Nothing in MVVM replaces this. The
   fallback is `NotificationCenter`, which is strictly worse along every axis the migration cares
   about.

Removing (1) and keeping (2) takes the entire benefit of the migration without paying for it with
31 untyped notification posts.

**Consequence.**
- The five migrated Phase 1 leaves need **no rework**. Their residual `import Redux` for browser
  dispatches was correct, and is now permanent rather than debt to be paid in Phase 3.
- Phase 4 changes from "delete Redux" to "reduce Redux to the bus" — see PLAN.md.
- The burn-down targets are no longer 0. They are the retained-bus budget, tracked separately from
  screen-state usage, so that "Redux still present" cannot silently mean "migration incomplete".
- The PR title must describe what is happening: *replace Redux screen state with MVVM*, not
  *remove Redux*. The branch name keeps its ticket slug.

**Rejected alternative — keep full Redux (state + reducers + middleware) inside the four hub
modules, MVVM everywhere else.** This is the more obvious reading of "hybrid", and it is worse: it
leaves the 12,163-LOC Homepage stack entirely untouched, keeps two complete architectures alive
for contributors to learn, and preserves precisely the ceremony the migration exists to delete. The
hubs' Redux dependency is on the *bus*, not on the *state tree* — so the bus is what to keep.

---

## D-017 — One routing rule for every cross-module signal

**Narrows** [D-014](#d-014), which is now the last resort rather than the second option.

**Context.** With the bus retained (D-016) there are three ways for one module to signal another,
and the choice was previously made per-case. That is how notification sprawl starts.

**Decision.** The sender's relationship to the receiver picks the mechanism. In order:

| Condition | Mechanism |
| - | - |
| The sender owns, or is owned by, the receiver — or a coordinator owns both | **Delegate / injected protocol** (D-004) |
| No ownership path, and the signal is a browser-level event (navigation, tab lifecycle, page load, content blocking, secure-content, private-mode) | **Browser event bus** (D-016) |
| No ownership path, and the signal is not browser-level | **`NotificationCenter`**, carrying the `WindowUUID`, justified in the commit message (D-014) |

**Rationale.** The middle row is the one D-014 was missing, because when it was written the bus was
scheduled for deletion. Restoring it converts the common case — an ownerless *browser* signal —
from the worst mechanism to the best one, and leaves `NotificationCenter` covering only genuinely
rare edges.

**Consequence.** The two notifications introduced for TrackingProtection by D-014 are on the wrong
side of this line: a blocked-tracker count change from `TabContentBlocker` and a secure-content
change from `BrowserViewController` are both browser-level events with no ownership path — row two,
not row three.

They are **not** moved yet. Until Phase 4 narrows the core, dispatching through `Store` still runs
the action through `AppState` and the whole reducer chain — for a screen that no longer has a state
case in it. That is worse than the notification they replaced. The move is therefore scheduled as
Phase 4 item 22, once the bus is a bus and not a state tree, and the budget in `burndown.sh` stays
at 2 until then. New code does not get the same latitude: rows one and two cover every case a
migration is likely to hit, so a third notification should not appear.

`refactor-tracking/burndown.sh` reports the count of migration-introduced notification posts so that
row three staying rare is a measured fact rather than an intention.

---

## D-018 — Translations runtime moves to Phase 3, with Toolbar and BrowserViewController

**Extends** [D-012](#d-012) and [D-015](#d-015) — the same test, applied to the third module that
looked like a Phase 2 leaf and is not one.

**Context.** PLAN listed "Translations runtime" as Phase 2 module 7. Measuring it against the
D-012 three-part test:

| Check | Result |
| - | - |
| Owns an `AppComponent` case | No — it has no screen state of its own |
| Its own reducer consumes foreign actions | Yes — `TranslationsMiddleware` consumes `ToolbarAction` and `ToolbarMiddlewareAction` |
| Foreign reducers consume its actions | Yes — `AddressBarState` and `ToolbarState` both reduce `TranslationsAction` |
| Its one state type is free-standing | No — `AutoTranslatePromptState` is a stored property of `BrowserViewControllerState` |

**Decision.** Move it to Phase 3, migrating with Toolbar (modules 14–16) and BrowserViewController
(module 18).

**Rationale.** It is coupled to Toolbar in *both* directions and keeps its only state inside the
BVC state tree. There is nothing to cut at until both hosts have moved. Migrating it now would mean
reaching into `AddressBarState`, `ToolbarState` and `BrowserViewControllerState` — the precise
mistake D-012 was written to prevent.

**Consequence.** Phase 2 is four modules, not five: TranslationSettings and TermsOfUse (both done),
MainMenu, and FeltPrivacy + ThemeSettings. Note that TranslationSettings *was* separable and is
already migrated — the settings screen owns its own component, while the runtime does not. Three
modules have now been re-scoped out of Phase 2 by the same test (D-012, D-015, D-018); the
lesson is that folder size is a poor proxy for separability, and the coupling maps are the only
reliable input.

---

## D-019 — The retained bus needed a subscribe side; `ActionObserving` adds it

**Implements** the missing half of [D-016](#d-016).

**Context.** D-016 says each Phase 3 hub "ends with a view model **and** a bus subscription", and
D-017 routes ownerless browser-level signals to the bus. Neither is possible as written: `Store`
exposes `dispatch` and `subscribe(_:transform:)`, and the latter is *state-change* notification —
it hands the subscriber a slice of `AppState`. A screen that has moved its state into a view model
has no slice left to subscribe to.

Concretely, `SearchBarState` consumes `GeneralBrowserActionType.enteredZeroSearchScreen` and
`.didUnhideToolbar`. Migrating it means keeping a `ScreenState` in the tree purely to have
something to hang a subscription off — which is the thing the migration removes.

**Decision.** Add `ActionObserving` to the Redux module: `addActionObserver(_:handler:)` /
`removeActionObserver(_:)`, with observers held weakly and notified from `Store.executeAction`
after the reducers and middlewares run. `DefaultDispatchStore` inherits it, so the existing global
`store` is a bus without a cast.

**Rationale.** This is Phase 4's "narrow Redux to a bus" work, pulled forward because Phase 3
cannot proceed without it. It is additive — no existing subscriber or reducer changes — and it is
the API the retained core is supposed to expose, not a workaround.

**Consequence.**
- Only legacy `Action`s are delivered. `ModernAction` carries its `windowUUID` separately and has
  no consumer that needs observing yet; adding it later is mechanical.
- Observers filter on `windowUUID` themselves, exactly as reducers did (D-005).
- Deallocated observers are swept before each notification, so a handler cannot resurrect one
  mid-iteration.
- `MockStoreForMiddleware` mirrors the behaviour, so a test can assert what a view model heard from
  the bus rather than what it dispatched.

## D-020 — Quick Answers settings changes ride the homepage's viewWillAppear, not a notification

`QuickAnswersMiddleware` recomputed `isQuickAnswersEnabled` on three triggers:
`HomepageActionType.initialize`, `HomepageActionType.viewWillAppear`, and
`QuickAnswersActionType.didSettingsChange` dispatched by the two settings screens.

The third is redundant. The setting can only be changed from a screen presented over the
homepage, so returning to the homepage fires `viewWillAppear` and recomputes anyway. Dropping
it removes an action type, a struct, and two dispatch sites without adding a notification —
the D-017 budget stays at 3. `HeaderViewModelTests.test_refresh_afterTheSettingChanges_...`
pins the behaviour.

## D-021 — Header state stays a plain struct

`HeaderState` is the diffable data source's item identity (`HomeItem.header(HeaderState, ...)`)
and the type `HomepageHeaderCell.configure` takes. Turning it into a view-model-owned
`HeaderConfiguration` would have churned the cell, the item enum and every measurement path for
no gain, so only its `StateType` conformance and reducer go. `HeaderViewModel` owns an instance
and republishes it. Same shape as the wallpaper slice that follows.

## D-022 — The wallpaper picker reuses `.WallpaperDidChange` rather than a new notification

`WallpaperMiddleware` existed to translate `WallpaperActionType.wallpaperSelected`, dispatched by
`WallpaperSettingsViewModel`, into `wallpaperDidChange` for the homepage's reducer. But
`WallpaperManager.setCurrentWallpaper` was *already* posting `.WallpaperDidChange` on the same
code path — the action was a second, parallel announcement of the same event.

`WallpaperViewModel` observes the notification that already exists and re-reads the manager. The
settings screen goes back to just setting the wallpaper. No new notification, so the D-017
budget stays at 3, and one of the two announcement paths goes away.

## D-023 — BrowserViewController hands the homepage its available height directly

`HomepageActionType.availableContentHeightDidChange` carried two CGFloats from BVC into
`WallpaperState`. BVC embeds the homepage — `contentContainer.contentController as?
HomepageViewController`, which it already does elsewhere — so this is D-017 row one, an
ownership path, and becomes a method call. The redundant-update guard BVC held (it read
`HomepageState` back out of the store to compare) moves into the view model's `didSet`.

This is the first BVC→homepage edge cut. `HomepageActionType` loses a case and `HomepageAction`
loses two fields.

## D-024 — Top-sites telemetry becomes a service before the section migrates

`TopSitesMiddleware` opened with "if this gets too big, should split out the telemetry"; it had.
Roughly 140 of its 266 lines were telemetry, and three callers outside the homepage — the app
menu, the shortcuts library, and the homepage's own pin action — dispatched
`TopSitesActionType.shortcutPinned`/`shortcutUnpinned` *only* to reach it. Each had already done
the pinning itself; the action carried nothing but a `source` enum.

Splitting the telemetry out first is what makes the rest of TopSites separable: those three
foreign edges disappear without any of them having to migrate, and both action types go with
them. The remaining middleware is fetch, the in-flight coalescing guard, and the context-menu
mutations — which is what the next slice moves.

## D-025 — `TopSitesService` keeps dispatching `retrievedUpdatedSites` until ShortcutsLibrary migrates

Two screens read top sites: the homepage and the shortcuts library. `ShortcutsLibraryState`
reduces `TopSitesMiddlewareActionType.retrievedUpdatedSites`, and a reducer is a static function
— it cannot hold a service reference or subscribe to one. So the service publishes twice: to
`onSitesChange` for owners of their own state, and to the store for the reducer that is still
there.

This is the D-012 blocker resolved without migrating ShortcutsLibrary: the middleware, the fetch
triggers, and the mutation edges all move now, and one action survives as a shim that the
shortcuts library slice deletes. Recording it here so the shim is not mistaken for a design.

The five notifications that used to reach the middleware through
`HomepageMiddlewareActionType.topSitesUpdated` (`.TopSitesUpdated`, `.PrivateDataClearedHistory`,
`.DefaultSearchEngineUpdated`, `.ProfileDidFinishSyncing`, `.FirefoxAccountChanged`) are now
observed by `HomepageViewModel` per window, replacing `HomepageMiddleware`'s fan-out over every
window. None of them is new, so the D-017 budget is untouched.

## D-026 — Settings screens must not resolve the container in test-visible defaults

`TopSitesSectionState`'s convenience init briefly resolved `FeatureFlagProviding` from
`AppContainer`, and `TopSitesService.shared`'s lazy initialiser resolves three services. Both are
reached through default arguments, so any test that constructed a `HomepageViewModel` without
injecting them resolved the container at whatever moment the default happened to be evaluated —
which crashed hard (`Fatal error: No definition registered`) rather than failing an assertion,
taking the whole test process with it.

The rule this leaves: a view model that a test constructs must take every collaborator as an
injectable parameter, and the test helpers must pass them. `HomepageViewControllerTests` and
`HomepageDiffableDataSourceTests` now build a stubbed `HomepageViewModel` in every case rather
than letting `createSubject` fall through to the production defaults.

## D-027 — Jump back in reads the tab layer directly, and hears about it on the bus

Jump back in was the hardest section to separate: its two data sources lived in
`TabManagerMiddleware` and `RemoteTabsPanelMiddleware`, neither of which is migrating in Phase 3.
The D-012 test says look at what actually couples them, and what coupled them was two cheap
reads — `tabManager.recentlyAccessedNormalTabs` and `profile.getCachedClientsAndTabs` — that each
middleware wrapped in a dispatch. Neither needed the store. `TabManagerMiddleware` even carried
"FXIOS-11740 this should go to the homepage middleware" on its half.

So they become `RecentTabsProviding` and `SyncedTabProviding`, and the section migrates without
Tabs having to.

The refresh triggers show all three D-017 rows in one section:
- homepage `viewWillAppear` → direct call (ownership)
- `.ProfileDidFinishSyncing` / `.FirefoxAccountChanged` → notifications the homepage already
  observes, so `HomepageMiddleware`'s `jumpBackInLocalTabsUpdated`/`jumpBackInRemoteTabsUpdated`
  bridge disappears
- tab tray dismissed, top tabs opened or closed a tab → the bus (D-016), because those are
  browser-level events with no ownership path to the homepage

The last group is the second real use of the retained bus after the search bar, and the one that
justifies keeping it: twelve action-type cases across two middlewares collapse into one observer.

## D-028 — Homepage complete: the first screen fully off the screen-state tree

`HomepageState`, `HomepageTelemetryState` and `HomepageMiddleware` are gone, along with
`HomepageAction`, both of its action-type enums, and the `.homepage` `AppComponent` case.
`HomepageViewController` no longer conforms to `StoreSubscriber`. Ten sections migrated over the
phase; the last two fields of the state — `telemetryState` and `shouldShowPrivacyNotice` — moved
into `HomepageViewModel` in this slice.

Three things worth recording from the finale:

- `HomepageActionType.embeddedHomepage` carried `isZeroSearch` from `BrowserCoordinator`, which
  creates the homepage. That is an ownership path, so it is `setZeroSearch(_:)`.
- `GeneralBrowserActionType.didSelectedTabChangeToHomepage` drove the `shouldTriggerImpression`
  flag. A tab changing is browser-level with no ownership path here, so it comes off the bus.
  This is the third bus consumer, after the search bar and jump back in.
- `HomepageSectionLayoutProvider` held four `store.state.componentState(HomepageState.self, ...)`
  guards. Three of them bound a value nothing read — they were "is the homepage in the store"
  checks that survived their own purpose. Only one carried information, and it is a closure now.

What the homepage still touches of Redux is navigation and browser-level actions it dispatches
outward — `NavigationBrowserAction`, `GeneralBrowserAction`, `ToolbarAction`, `ContextMenuAction`
— which is exactly the D-016 end state for a migrated screen.

## D-029 — Shortcuts library migrated; D-025's shim is gone

`ShortcutsLibraryState`, `ShortcutsLibraryMiddleware` and the `.shortcutsLibrary` `AppComponent`
case are gone. The view model observes `TopSitesService` directly, so the service stops
dispatching `TopSitesMiddlewareActionType.retrievedUpdatedSites` — the shim D-025 introduced,
kept for exactly as long as a static reducer needed it. `TopSitesMiddlewareActionType` and
`TopSitesAction` go with it, and `TopSitesService` no longer imports Redux.

`ShortcutsLibraryActionType.switchTabToastButtonTapped` survives: `TabManagerMiddleware` consumes
it to select a tab, which is a genuine cross-module command rather than a state announcement. It
migrates with Tabs.

`shouldRecordImpressionTelemetry` was a state field whose only job was "have I recorded the
viewed event for this presentation" — a middleware read it, sent the event, and dispatched a
second action to clear it. That round trip is a private `Bool` on the view model.

## D-030 — Search engine selection: a screen that keeps dispatching, and should

`SearchEngineSelectionState` and `SearchEngineSelectionMiddleware` are gone. The middleware's load
half read `SearchEnginesManager.orderedEngines` and dispatched the result for the reducer to
store — a read the view model does itself.

Its other half is the interesting part. Tapping an engine announces two things the *toolbar*
reacts to: `ToolbarActionType.didStartEditingUrl` and
`SearchEngineSelectionActionType.didTapSearchEngine`, the latter reduced by both `ToolbarState`
and `AddressBarState`. Those stay as dispatches. This is the first module to land in the D-016
end state exactly as described: no `ScreenState`, no middleware, no subscription — and still an
`import Redux`, because it announces outward to screens that have not migrated.

`SearchEngineSelectionState.selectedSearchEngine` was written by the reducer and read by nobody;
the toolbar's reducers take the value off the action. Deleted with the state.

## D-031 — MicrosurveyPrompt is BVC-blocked, not next

`MicrosurveyPromptState` is a *field of* `BrowserViewControllerState`, not a component of its own,
so it has no separable boundary until BVC migrates. Recording this so the next pass does not pick
it up as a small module. Same for `StartAtHomeMiddleware`, which has no state or view of its own —
it is a browser-lifecycle helper that reacts to BVC actions.

## D-032 — `HomepageAction` deleted; two regressions the full-suite run caught

Running the whole of `ClientTests` after the homepage finale surfaced two things the per-slice
runs did not, both in `BrowserCoordinatorTests`:

1. **`isZeroSearch` was orphaned.** `BrowserCoordinator` still dispatched
   `HomepageActionType.embeddedHomepage` carrying it, and nothing read it any more. It is
   `homepageViewController.setZeroSearch(_:)` now — the coordinator embeds the homepage, so this
   is an ownership path. With it gone, `HomepageAction`, `HomepageActionType`,
   `HomepageMiddlewareActionType` and `HomepageTelemetryExtras` have no producer or consumer left
   and the whole `Homepage/Redux/` directory is deleted.

2. **The available-height push ran before the homepage was embedded.** D-023 turned BVC's dispatch
   into a direct call guarded on `contentContainer.contentController as? HomepageViewController`.
   `showHomepage` called it *before* `embedContent`, so on the first presentation the guard failed
   and the heights stayed at zero; the second presentation set them, which resized the spacer and
   scrolled the collection view back to the top. Moved after the embed.

The second is a real user-visible bug the old code avoided by accident — its guard
(`browserViewType == .normalHomepage || contentContainer.hasHomepage`) was loose enough to pass
before the embed. Worth noting for the modules still to migrate: replacing a store read with an
ownership check can tighten a guard in ways the call order was not written for.

Also removed a duplicate `AppContainer` resolve: `JumpBackInSectionState`'s convenience init
resolved `UserFeaturePreferring` that the view model had already resolved and was passing in.
The second resolve crashed the test process under `BrowserCoordinatorTests` — D-026 again.

## D-033 — TabPeek first out of the Tabs module, and a duplicated shortcut registration

Tabs is the largest remaining module, so it comes apart in pieces. TabPeek is the first: five
actions, four of which were commands on the tab and bookmark layers routed through the store
(bookmark it, unbookmark it, copy its URL, load its preview). Those are `TabPeekViewModel` method
calls now, `TabPeekState` loses its `ScreenState` conformance and the `.tabPeek` `AppComponent`
case goes.

`TabPeekActionType.closeTab` stays a dispatch: closing needs `TabsPanelState.isPrivateMode`, and
the tabs panel has not migrated. Same shape as `switchTabToastButtonTapped` in D-029 — a command
whose receiver is still a middleware.

Moving the code surfaced a duplicate: `resolveTabPeekActions`'s `addToBookmarks` case called both
`addToBookmarks(shareItem)` *and* `setBookmarkQuickActions(with:uuid:)`, and both registered the
`.openLastBookmark` dynamic shortcut. Bookmarking from tab peek registered it twice. The view
model does it once.

`TabManagerMiddleware`: 697 lines to 583.

## D-034 — RemoteTabsPanel: a sync state machine written as five round trips

`RemoteTabsPanelState` and `RemoteTabsPanelMiddleware` are gone, and the `.remoteTabsPanel`
`AppComponent` case with them. The middleware was a refresh state machine expressed as five
actions going out to the store and coming back — begin, succeed, fail, sync-began,
devices-changed. Every one was the screen announcing something to itself, so they are plain state
transitions on `RemoteTabsPanelViewModel`. `RemoteTabsPanelActionType` drops from eleven cases to
three.

What still dispatches is what actually leaves the screen: `TabTrayActionType.firefoxAccountChanged`
(reduced by `TabTrayState`) and the three commands `TabManagerMiddleware` performs — open, close,
flush.

The tab tray's sync button dispatched `refreshTabs`, which would have been orphaned. The tab tray
holds the panel in `childPanelControllers`, so that is an ownership path and becomes a call.

## D-035 — Test seams: `initialState`, not `newState`

Several panel tests seeded a screen by calling its `newState(_:)`. With the subscription gone
there is no such entry point, and adding one purely for tests would put a setter back on the view.
The pattern that has settled instead is an `initialState:` parameter on the view model, which the
view controller also takes for injection. `HeaderViewModel`, `WallpaperViewModel`,
`TopSitesSectionViewModel`, `JumpBackInSectionViewModel`, `ShortcutsLibraryViewModel` and now
`RemoteTabsPanelViewModel` all have one.

## D-036 — Tabs: the tray, the panels and the peek all off Redux

`TabTrayState`, `TabsPanelState` and their reducers lose their Redux conformance; the `.tabsTray`
and `.tabsPanel` `AppComponent` cases go, leaving two. `TabManagerMiddleware` drops from 697 lines
to 138 and now does three things only: write a screenshot to disk, select a tab for jump back in,
and select a tab for the shortcuts-library toast.

The middleware's real content was `TabsPanelService`: add a tab, move one, close one, close them
all, delete the old ones, select one, prefetch a screenshot. Every one was a command against
`TabManager` followed by a dispatched refresh. The commands are methods; the refresh is an
observer list, because one service serves the tray and its three panels.

Three things still leave the tab tray and stay dispatches, all browser-level:
`TabTrayActionType.dismissTabTray` (the homepage observes it for jump back in, and the tray
observes it to close), `GeneralBrowserActionType.showOverlay`, and
`TabTrayActionType.firefoxAccountChanged` from the synced-tabs panel. `ScreenshotActionType`
arrives on the bus in the other direction — the tab manager takes a screenshot, the panel rebinds.

Two deletions worth naming:

- **FXIOS-15973's workaround is gone.** `TabDisplayPanelViewController` carried a static
  `latestSubscriptionGeneration` map because the `.tabsPanel` component was shared per window
  across panel instances, so a closing panel could wipe the state a newly-opened one depended on.
  With state per panel there is nothing shared to wipe.
- **`TabPeekActionType` and `RemoteTabsPanelAction` are gone entirely.** Tab peek closes through
  the panel's service (the display view hands it over when building the peek), and the synced-tabs
  panel runs its three commands directly.

## D-037 — Two test-suite hazards worth remembering

`wait(for:)` with no timeout on an expectation that can no longer be fulfilled does not fail the
test — it hangs the whole suite. Three `TabManagerMiddlewareTests` cases waited on a refresh
dispatch that had moved to the bus, and the run never finished rather than reporting a failure.
When an action stops being dispatched, grep the tests for `dispatchCalled` before assuming a
compile-clean suite is a passing one.

`MockTabManager` keeps `tabs`, `normalTabs` and `privateTabs` as three independent arrays; seeding
`tabs` alone leaves `normalTabs` empty and the panel reads nothing.

## D-038 — Toolbar: keep the reducer, drop the screen state

`ToolbarState` is the one screen where almost everything displayed is browser state announced from
somewhere else — the URL changed, the page finished loading, reader mode became available, the tab
count moved, the search engine changed. Those announcements come from `BrowserViewController`, the
tab manager, Settings, the translations middleware and the search-engine picker, none of which
owns the toolbar. That is precisely what D-016 retains the bus for.

So the transitions do not move at all. `ToolbarState.reduce(_:with:)` *is* the old reducer body,
unchanged, and `ToolbarViewModel` calls it from a bus observer. What goes is the screen state in
the store, the four `store.subscribe` calls, and the last `AppComponent` case besides
`browserViewController`.

The ~1,900 lines of reducer in `ToolbarState`, `AddressBarState` and `NavigationBarState` are
untouched, and so are their test suites — 63 reducer tests kept their coverage by changing
`ToolbarState.reducer.legacyReducer(a, b)` to `ToolbarState.reduce(a, with: b)`. For a screen this
central, not rewriting the logic is the point.

`ToolbarViewModel` is per-window and reached through a small registry, because the toolbar's four
views, `BrowserViewController`, `TopTabsViewController`, the main menu and the translations
middleware all read the same state for a window. Ten `store.state.componentState(ToolbarState...)`
reads became `ToolbarViewModel.instance(for:).state`, and non-optional in the process — the store
lookup could fail, the instance cannot.

## D-039 — The screen-state tree is gone; `AppState` is empty

`BrowserViewControllerState` was the last screen state, and `BrowserViewController` its only
subscriber. Same treatment as the toolbar: the reducer body survives verbatim as
`BrowserViewControllerState.reduce(_:with:)`, the controller owns the value and applies it from a
bus observer.

With that, `AppComponent`, `ComponentState`, `PresentedComponentsState` and `ComponentAction` all
have nothing left to hold and are deleted. `AppState` is an empty struct, and
`AppState.componentState(_:for:window:)` — the lookup every screen used to reach its own state —
goes with them. This is the D-016 end state stated plainly: **the store keeps its dispatch and its
action observers, and keeps no screens.**

One coupling had to be broken to get here. `ToolbarMiddleware` read
`BrowserViewControllerState.microsurveyState.showPrompt` to decide which toolbar borders to hide,
and once BVC owned its own state there was no shared place to read it from. That is
`MicrosurveyPromptVisibilityStore`, the same one-boolean-per-window shape as
`SearchBarVisibilityStore`, and it goes the same way when the microsurvey prompt gets its own
view model.

### What is left of Redux, and why

Six middlewares and the bus. The middlewares that remain are the ones with no screen of their own
— they translate browser events into other browser events: `TabManagerMiddleware` (three tab
commands), `ToolbarMiddleware`, `MicrosurveyPromptMiddleware`, `StartAtHomeMiddleware`,
`SummarizerMiddleware`, `TranslationsMiddleware`. They are bus consumers that happen to be
registered as middlewares; converting them is Phase 4 work, not screen-state work.

## D-040 — The last six middlewares become bus observers; the middleware layer is deleted

`MicrosurveyPromptMiddleware`, `TabManagerMiddleware`, `ToolbarMiddleware`, `StartAtHomeMiddleware`,
`SummarizerMiddleware` and `TranslationsMiddleware` never had a screen. Each one reads a browser
event and does work or announces another event, which is what the bus is for. Converting them was
mechanical: the `lazy var legacyProvider: LegacyMiddlewareClosure<AppState> = { [self] state, action in`
became `func handle(_ action: Action)`, and the bodies did not change. The `state` parameter went
unused, because `AppState` is empty (D-039) — everything they read already lives on a view model.

`BrowserActionHandlers.shared.register()` in `AppDelegate` registers all six, in the order the
`middlewares` array had them. With nothing left to register, `Middleware.swift`, the store's
`middlewares` array and `emptyMiddlewareProviderFactory` are deleted.

Two side effects worth recording:

- `SummarizerActionHandlerTests` no longer needs `releaseMiddlewareProvidersFromMemory`. The retain
  cycle it worked around was the provider closure capturing `self`; a method does not.
- The `TranslationsActionHandler` suite seeded state by running the reducer over `AppState`. It
  seeds `ToolbarViewModel` instead — same state, new owner.

## D-041 — The bus owes the observers the two guarantees the middleware chain gave

Converting middlewares into observers is not a rename. The chain provided two things a flat
observer list does not, and both had to be rebuilt:

**Order.** Every reducer ran before any middleware, so a middleware always read post-action state.
`ToolbarActionHandler` reads the toolbar state, which `ToolbarViewModel` now owns and updates from
its own observer — and the handler registers at launch while the view model registers when its
window opens, so on a flat list the handler would read state one action behind. Observers now
declare a tier: `.state` observers (a view model reducing into state it owns) are delivered to
before `.effects` observers (the six handlers). Within a tier, registration order holds.
`notifyActionObservers` also moved after the state assignment, so an observer reading `store.state`
sees what a middleware was handed.

**Modern actions.** `notifyActionObservers` only forwarded legacy actions, so the four
`ToolbarModernAction` dispatch sites — keyboard hide, user scroll, accessory view, scroll handler —
reached nothing at all once the toolbar's subscription was gone. `addModernActionObserver` carries
them, as a separate registration rather than a cast inside the legacy handler, because a
`ModernAction` carries its window separately.

The general lesson: a delivery mechanism has a contract beyond "the handler runs". Ordering and
coverage were implicit in Redux's shape, so nothing named them, and nothing failed loudly when they
were dropped — the toolbar would simply have stopped responding to scrolls.

## D-042 — Rename the six to `*ActionHandler`; leave the `*MiddlewareAction` families alone

Nothing is a middleware any more, so the classes are `MicrosurveyPromptActionHandler`,
`TabManagerActionHandler`, `ToolbarActionHandler`, `StartAtHomeActionHandler`,
`SummarizerActionHandler`, `TranslationsActionHandler`, and `MockStoreForMiddleware` — which mocks
the bus, not a middleware — is `MockStore`.

The action families keep their names. `ToolbarMiddlewareAction`, `GeneralBrowserMiddlewareAction`,
`TabPanelMiddlewareAction` and the rest are the bus's vocabulary and are retained under D-016; the
convention they encode (a `*ViewAction` is dispatched by a view, a `*MiddlewareAction` is dispatched
back out by the thing that handled it) still holds, with the handler in the middleware's place.
Renaming them is 230-odd mechanical references across files this branch does not otherwise touch,
which buys accuracy in a name at the cost of a reviewable diff and a merge conflict in every one of
those files. Recorded as follow-up work, not done here.
