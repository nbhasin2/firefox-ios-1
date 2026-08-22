# FXIOS-16660 — Remove Redux, migrate to MVVM + Swift Concurrency

## Goal

Remove the Redux architecture (`Store`, `Action`, `Reducer`, `Middleware`, `StoreSubscriber`,
`AppState`) from Firefox iOS and replace it with MVVM using Swift Concurrency (`async`/`await`,
`AsyncStream`, `@MainActor`). **Not Combine** — see [DECISIONS.md](DECISIONS.md) D-002.

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
communication that previously happened by "middleware observes another module's action" becomes
an explicit delegate or injected coordinator call (D-004).

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
3. **NativeErrorPage** (1,993 LOC) — keeps browser-level dispatches until Phase 3 (D-011)
4. **TrackingProtection** (4,349 LOC)
5. **Microsurvey** — survey screen only; the *prompt* is coupled to Toolbar

### Phase 2 — Screens with one coupling edge
Each has exactly one foreign edge, converted to a delegate call in the same commit.

6. **TranslationSettings** + **Translations** — `TranslationSettingsState` consumes
   `TranslationsAction`, so the pair moves together
7. **TermsOfUse** (1,481 LOC) — consumes `HomepageAction`
8. **QuickAnswers** / **Summarizer** — consume `HomepageAction` / toolbar + browser actions
9. **MainMenu** (2,369 LOC) — consumed by `TabManagerMiddleware` + `ThemeMiddleware`
10. **FeltPrivacy** + **ThemeSettings** — consume `PrivateModeAction`

### Phase 3 — Hub modules (highest coupling)
These are the load-bearing ones; each is split into several ≤500-line commits.

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
18. **BrowserViewController** — the integration hub; migrates last

### Phase 4 — Global teardown
19. Delete `Client/Redux/GlobalState/` (`AppState`, `ScreenState`, `AppComponent`,
    `ComponentAction`, `PresentedComponentsState`)
20. Delete `BrowserKit/Sources/Redux` + `BrowserKit/Tests/ReduxTests`, drop the `Redux` product
    from `Package.swift` and the Client target
21. Remove `Redux` from `TestKit`, strip `import Redux` app-wide
22. Final SwiftLint + full `fxios test` + simulator build

## Definition of done per module

A module is done when **all** hold:

- No `import Redux` in any of its files, **except** where the file dispatches a browser-level
  action (`GeneralBrowserAction`, `NavigationBrowserAction`) — those survive until Phase 3 (D-011)
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
