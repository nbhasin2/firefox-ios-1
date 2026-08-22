# FXIOS-16660 — Remove Redux, migrate to MVVM + Swift Concurrency

## Goal

Replace Redux **screen state** in Firefox iOS with MVVM using Swift Concurrency (`async`/`await`,
`@MainActor`), and retain a reduced Redux core as a typed **browser event bus**.
**Not Combine** — see [DECISIONS.md](DECISIONS.md) D-002.

The end state is a hybrid, decided in **D-016** on the evidence gathered in Phases 0–2:

| Redux was doing two jobs | Fate |
| - | - |
| Holding every screen's state in one global `AppState` tree, reduced by 40 action types and 23 middlewares | **Deleted** — this is where the ~54k LOC and all the ceremony live |
| Typed, window-keyed broadcast of browser-level events between 31 senders that hold no reference to their 5 receivers | **Kept** — nothing in MVVM replaces it, and the fallback (`NotificationCenter`) is worse |

Read D-016 before changing the scope of this plan. "Redux is still imported" is no longer, on its
own, evidence that the migration is incomplete — see the burn-down targets in
[PROGRESS.md](PROGRESS.md), which distinguish retained-bus usage from screen-state usage.

## Measured scope (baseline, `main` @ f2a42cbea7)

| Metric | Count |
| - | - |
| Swift files with `import Redux` | 200 |
| Swift files touching a Redux construct | 274 |
| Total LOC in Redux-importing files | ~54,200 |
| `store.dispatch` call sites | 451 |
| `Action` / `ModernAction` conforming types | 47 |
| Middleware files | 28 registered in `AppState.middlewares` |
| `StoreSubscriber` conformances (migration units) | 20 |
| Screen components in `AppComponent` | 17 |
| Redux core (BrowserKit/Sources/Redux) | 8 files, 412 LOC |

This is a rewrite of the app's central nervous system, not a localized refactor. The plan is
therefore **strangler-fig**: Redux and MVVM coexist while modules are moved one at a time, and
the Redux core is deleted only after the last consumer is gone.

## Architecture: before → after

**Before** — one global `Store<AppState>`; every screen is a `ScreenState` case inside
`PresentedComponentsState`; view controllers conform to `StoreSubscriber` and receive
`newState(state:)`; side effects live in `Middleware` closures that read the whole `AppState`
and re-`dispatch`.

**After** — per-screen `@MainActor final class XxxViewModel`:

- owns a plain `XxxState` **struct** (no `ScreenState`, no `Equatable` requirement from a protocol)
- exposes **intent methods** (`selectCategory(_:)`, `submit() async`) in place of dispatched actions
- performs side effects **inline with `async`/`await`**, replacing the middleware
- publishes changes through a single `onStateChange: ((State) -> Void)?` callback
  (see D-003 for why a callback and not `@Published`/`AsyncStream`)
- is constructor-injected with its services, so tests need no global store

View controllers hold the view model, set `onStateChange`, and call intent methods. Cross-screen
communication that previously happened by "middleware observes another module's action" is routed
by the single rule in **D-017**: a delegate where an ownership path exists (D-004), the browser
event bus where the signal is a browser-level event between ownerless peers (D-016), and
`NotificationCenter` only for ownerless non-browser signals (D-014).

**What the retained bus is.** `Action`, `ActionType`, and `Store`'s dispatch/subscribe path — no
`AppState`, no reducers, no middlewares. A screen subscribes to browser-level actions it cares
about and filters on `windowUUID`; it never stores state in the bus.

## Phases

Ordering is driven by the **action-coupling map** in [FILES_TO_CHANGE.md](FILES_TO_CHANGE.md):
migrate modules whose actions no other middleware consumes first, so each phase is independently
shippable and the app builds and runs green after every phase.

### Phase 0 — Analysis & scaffolding
- [x] Inventory every Redux file and construct
- [x] Build the middleware ⇢ action coupling map
- [x] Create tracking docs, branch `nbhasin2/FXIOS-16660-remove-redux-mvvm-combine`
- [ ] Establish baseline: Fennec builds green, record test baseline

### Phase 1 — Isolated leaf screens
A module qualifies only if **all three** hold: no foreign middleware consumes its actions, no
foreign *reducer* consumes its actions, and its own reducer consumes no foreign actions. See the
two coupling maps in [FILES_TO_CHANGE.md](FILES_TO_CHANGE.md).

1. **WebCompatReporter** (433 LOC) — pilot; proves the pattern end-to-end
2. **PasswordGenerator** (942 LOC)
3. **NativeErrorPage** (1,993 LOC) — keeps browser-level dispatches permanently (D-011, as amended by D-016)
4. **TrackingProtection** (4,349 LOC)
5. **Microsurvey** — survey screen only; the *prompt* is coupled to Toolbar

### Phase 2 — Screens with one coupling edge
Each has exactly one foreign edge, converted to a delegate call in the same commit.

6. **TranslationSettings** — `TranslationSettingsState` consumes `TranslationsAction` ✅
7. **Translations** (runtime, ~700 LOC) — pairs with 6
8. **TermsOfUse** (1,481 LOC) — consumes `HomepageAction` ✅
9. **MainMenu** (2,369 LOC) — consumed by `TabManagerMiddleware` + `ThemeMiddleware`
10. **FeltPrivacy** + **ThemeSettings** — consume `PrivateModeAction`

Moved to Phase 3 by D-015: **QuickAnswers** (its state is `HeaderState`, a Homepage section) and
**Summarizer** (its state is `BrowserViewControllerState`). Neither is a screen.

### Phase 3 — Hub modules (highest coupling)
These are the load-bearing ones; each is split into several ≤500-line commits.

**Design (D-016/D-017).** Hub migration is not "delete the store and wire up delegates". Each hub
keeps talking to the bus; what it loses is its `ScreenState` and its middleware. Per hub:

1. Its `…State` struct moves into a `@MainActor` view model owned by the per-window coordinator,
   and its `AppComponent` case is deleted (as for any leaf).
2. Its middleware's genuine side effects move onto view-model intents (D-008); the middleware file
   is deleted.
3. The foreign actions the middleware observed are triaged with the D-017 table. Only the rows that
   resolve to "browser event bus" keep an `Action` type — the rest become delegate calls.
4. The hub **subscribes** to the bus for the browser-level actions it consumes today, replacing the
   reducer's `as?` cast chain with a typed handler. Its `windowUUID` filter stays (D-005).

Consequently the four hubs each end with a view model **and** a bus subscription, and the 31 sender
files keep their `import Redux`. That is the intended terminal state, not remaining work.

11. **Homepage** (94 files, 12,163 LOC) — fans out to 8 middlewares
    (Merino, TopSites, MessageCard, Bookmarks, TrackerBlockerModule, Wallpaper, RemoteTabsPanel, Homepage)
12. **ShortcutsLibrary** (686 LOC) — `ShortcutsLibraryState` consumes `TopSitesAction` and
    `TabManagerMiddleware` consumes `ShortcutsLibraryAction`; moves with Homepage/Tabs
13. **Tabs / TabTray** (47 files, 8,988 LOC) — `TabManagerMiddleware` is the single largest consumer
14. **Toolbar** (21 files, 5,455 LOC) — consumes microsurvey + general-browser actions
15. **SearchEngineSelection** (1,351 LOC) — `AddressBarState` and `ToolbarState` reducers consume
    `SearchEngineSelectionAction`; moves with Toolbar
16. **MicrosurveyPrompt** — folded in with Toolbar
17. **StartAtHome** — `BrowserViewControllerState` consumes `StartAtHomeAction`
18. **BrowserViewController** — the integration hub; migrates last, and takes **QuickAnswers**
    and **Summarizer** with it (D-015: their state lives in `HeaderState` and
    `BrowserViewControllerState`, so neither can move before its host)

### Phase 4 — Reduce Redux to the bus (was: global teardown)
Rewritten by D-016. The core is narrowed, not deleted.

19. Delete `Client/Redux/GlobalState/` (`AppState`, `ScreenState`, `AppComponent`,
    `ComponentAction`, `PresentedComponentsState`). Unchanged from the original plan — by this
    point no screen state remains in the tree.
20. Narrow `BrowserKit/Sources/Redux` to the bus: keep `Action`, `ActionType`, and the
    dispatch/subscribe path; delete `Reducer`, `StoreSubscriber`'s state-tree coupling, and the
    generic `Store<State>` parameterisation over an app-wide state.
21. Rename the retained surface to say what it is (`BrowserEventBus`), and keep the three
    browser-level action families as its vocabulary. `import Redux` survives in the 31 sender files
    and the hub subscribers **by design** (D-016).
22. Move the two D-014 `NotificationCenter` signals onto the bus. Deferred to here on purpose:
    until step 20 lands, a dispatch still traverses `AppState` and the reducer chain, which is
    worse than the notification (D-017).
23. Keep the `Redux` product in `Package.swift` and on the Client target; keep `ReduxTests` for the
    retained surface and delete the tests covering the deleted reducer/state-tree API.
24. Final SwiftLint + full `fxios test` + simulator build

## Definition of done per module

A module is done when **all** hold:

- No `import Redux` in any of its files, **except** where the file dispatches or subscribes to a
  browser-level action (`GeneralBrowserAction`, `NavigationBrowserAction`,
  `GeneralBrowserMiddlewareAction`). Those are permanent and intended (D-016, superseding D-011's
  "until Phase 3")
- Every cross-module signal it introduces is justified against the D-017 routing table, and any
  `NotificationCenter` post is named in the commit message
- Its `State` no longer conforms to `ScreenState`; its case is removed from `ComponentState`/`AppComponent`
- Its `Action` types and `Middleware` are deleted
- Its view controller no longer conforms to `StoreSubscriber`
- Reducer tests are rewritten as view-model tests; middleware tests become async side-effect tests
- SwiftLint clean, Fennec compiles, module's tests pass

## Verification

```bash
# lint
swiftlint --strict --config .swiftlint.yml

# build
xcodebuild build -project firefox-ios/Client.xcodeproj -scheme Fennec \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# tests
fxios test
```

## Constraints

- Every commit ≤ 500 changed lines
- Push only to `origin` (nbhasin2/firefox-ios-1); never to `upstream`
- PR targets `mozilla-mobile/firefox-ios:main`

## Risk register

| Risk | Mitigation |
| - | - |
| Multi-window (iPad) state keyed by `WindowUUID` is a core Redux affordance | View models are instantiated per window and owned by the per-window coordinator; `windowUUID` stays a stored property (D-005) |
| Cross-module action listening is implicit and easy to miss | Coupling map in FILES_TO_CHANGE.md is derived by grep, not by hand; each removal is compiler-enforced |
| Redux guarantees serialized action processing; ad-hoc `async` does not | View-model intents stay `@MainActor`; awaits are only around genuine I/O (D-006) |
| 12k-LOC Homepage is too big for one pass | Split by section (TopSites, Merino, Bookmarks, MessageCard, Wallpaper) — each section already has its own state/middleware pair |
| Regression risk in untested UI paths | Rewrite reducer tests as view-model tests before deleting the reducer, never after |
| **Notification sprawl** — replacing the store with 31 untyped `NotificationCenter` posts, reproducing Redux without its type safety | The bus is retained for exactly this traffic (D-016); D-017 makes the choice a rule, and `burndown.sh` counts migration-introduced posts so growth is visible |
| **Hybrid drift** — the retained bus quietly regrowing into a state container | The bus has no reducers and no `AppState` after Phase 4; `burndown.sh` fails if a `ScreenState`/`AppComponent` case reappears |
| **"Redux still present" misread as "not done"** — a future contributor finishing the job by deleting the bus | D-016 records the rationale and the rejected alternative; PROGRESS.md targets are non-zero and labelled |
