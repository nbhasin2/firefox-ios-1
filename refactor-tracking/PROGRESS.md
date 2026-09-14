# Progress — FXIOS-16660

Branch: `nbhasin2/FXIOS-16660-remove-redux-mvvm-combine`
Baseline: `main` @ f2a42cbea7

## Burn-down

Targets are **not zero**: D-016 retains a reduced Redux core as the browser event bus. The table is
split so that "Redux is still imported" cannot be misread as "the migration is unfinished".

### Screen state — must reach zero

| Metric | Baseline | Current | Target |
| - | - | - | - |
| Registered middlewares | 28 | 20 | **0** |
| `StoreSubscriber` screens | 20 | 13 | **0** |
| Screens in `AppComponent` | 17 | 10 | **0** |
| Screen `Action` types (non-browser) | 44 | 31 | **0** |

### Retained bus — converges to a budget, not to zero

| Metric | Baseline | Current | Target |
| - | - | - | - |
| Files with `import Redux` | 200 | 161 | ≈31 (bus senders + hub subscribers) |
| `dispatch` call sites | 451 | 363 | ≈18 (browser-level only) |
| Browser-level action families | 3 | 3 | 3 (`GeneralBrowser`, `NavigationBrowser`, `GeneralBrowserMiddleware`) |

### Guardrails — must not grow

| Metric | Budget | Current | Rule |
| - | - | - | - |
| Migration-introduced `NotificationCenter` names | ≤ 2 | 2 | D-017 row three is a last resort; both current entries are scheduled to move to the bus |

Refresh with `refactor-tracking/burndown.sh`, which prints current-vs-target and exits non-zero on a
guardrail breach.

## Phase status

| Phase | Scope | Status |
| - | - | - |
| 0 — Analysis & scaffolding | Inventory, both coupling maps, tracking docs, branch | **Done** |
| 1 — Isolated leaf screens | 5 modules (was 8; see D-012) | **Done** |
| 2 — Single-coupling screens | 5 modules (2 done; see D-012, D-015) | **In progress** |
| 3 — Hub modules | Homepage, Tabs, Toolbar, BVC — each ends with a view model **and** a bus subscription (D-016) | Not started |
| 4 — Reduce Redux to the bus | Delete `AppState` + screen state; keep `Action`/`Store` as the browser event bus (D-016) | Not started |

## Module status

Legend: ⬜ not started · 🟡 in progress · ✅ done

### Phase 1 — isolated leaves

| # | Module | LOC | Status | Notes |
| - | - | - | - | - |
| 1 | WebCompatReporter | 433 | ✅ | Fully Redux-free; app builds, 76 tests pass |
| 2 | PasswordGenerator | 942 | ✅ | Fully Redux-free; removed `nonisolated(unsafe)` rules cache (FXIOS-12590) |
| 3 | NativeErrorPage | 1,993 | ✅ | Fixed per-window error bleed; keeps browser-level dispatches (D-011) |
| 4 | TrackingProtection | 4,349 | ✅ | Redux was a navigation command bus; refresh signals became notifications |
| 5 | Microsurvey (survey) | ~800 | ✅ | Screen now holds no state; Prompt half stays until Toolbar |

Moved out of Phase 1 by D-012 (reducer-level coupling): SearchEngineSelection → Phase 3 (Toolbar),
ShortcutsLibrary → Phase 3 (Homepage/Tabs), StartAtHome → Phase 3 (BVC),
TranslationSettings → Phase 2 (the settings screen is separable; the runtime is not — D-018).

### Phase 2 — single inbound coupling

Numbering matches [PLAN.md](PLAN.md) Phase 2.

| # | Module | LOC | Status | Commit |
| - | - | - | - | - |
| 6 | TranslationSettings | ~1,100 | ✅ | `b7215b3655`, `476a9d85f5` |
| 7 | Translations (runtime) | ~700 | ➡️ Phase 3 | moved by D-018 |
| 8 | TermsOfUse | 1,481 | ✅ | `6f6f552cc4` |
| 9 | MainMenu | 2,369 | ✅ | Extracted MainMenuTabInfoProvider; fixed FXIOS-13675 unsafe fan-out |
| 10 | FeltPrivacy + ThemeSettings | ~120 | ✅ | Both deleted; the round trip set the same theme twice |

Not in Phase 2: **ShortcutsLibrary** moved to Phase 3 by D-012 (its state reduces `TopSitesAction`),
and **QuickAnswers** / **Summarizer** moved to Phase 3 by D-015 (neither is a screen). Earlier
revisions of this table listed all three here, contradicting PLAN.md.

### Phase 3 — hubs

The `#` column is the [PLAN.md](PLAN.md) module number; a module lands as several
≤500-line commits, one per row. Each hub keeps a bus subscription when it is done (D-016).

| # | Work item | Status | Commit |
| - | - | - | - | - |
| 11 | Homepage — TopSites | ⬜ | — |
| 11 | Homepage — Merino | ⬜ | — |
| 11 | Homepage — MessageCard | ⬜ | — |
| 11 | Homepage — Bookmarks / JumpBackIn | ⬜ | — |
| 11 | Homepage — Wallpaper | ⬜ | — |
| 11 | Homepage — TrackerBlockerModule | ⬜ | — |
| 11 | Homepage — shell + HomepageState + bus subscription | ⬜ | — |
| 12 | ShortcutsLibrary (moved here by D-012) | ⬜ | — |
| 13 | Tabs — TabsPanel | ⬜ | — |
| 13 | Tabs — TabTray | ⬜ | — |
| 13 | Tabs — RemoteTabsPanel | ⬜ | — |
| 13 | Tabs — TabPeek | ⬜ | — |
| 13 | Tabs — TabManagerMiddleware teardown + bus subscription | ⬜ | — |
| 14 | Toolbar — AddressBar | ⬜ | — |
| 14 | Toolbar — NavigationBar | ⬜ | — |
| 14 | Toolbar — ToolbarMiddleware teardown + bus subscription | ⬜ | — |
| 15 | SearchEngineSelection (moved here by D-012) | ⬜ | — |
| 16 | MicrosurveyPrompt | ⬜ | — |
| 17 | StartAtHome (moved here by D-012) | ⬜ | — |
| 18 | BrowserViewController + bus subscription | ⬜ | — |
| 18 | QuickAnswers + Summarizer (moved here by D-015) | ⬜ | — |

### Phase 4 — reduce Redux to the bus

Rewritten by D-016: the core is narrowed, not deleted. Items 21 and 22 previously read "delete
`BrowserKit/Sources/Redux`" and "drop the `Redux` product", which the hybrid end state reverses.

| # | Item | Status | Commit |
| - | - | - | - |
| 19 | Delete `Client/Redux/GlobalState/` (`AppState`, `ScreenState`, `AppComponent`, `PresentedComponentsState`) | ⬜ | — |
| 20 | Narrow `BrowserKit/Sources/Redux` to `Action` + dispatch/subscribe; delete `Reducer` and the state-tree coupling | ⬜ | — |
| 21 | Rename the retained surface to `BrowserEventBus`; keep the three browser action families | ⬜ | — |
| 22 | Move the two D-014 notifications onto the bus, now that dispatching no longer goes through `AppState` (D-017) | ⬜ | — |
| 23 | Keep the `Redux` product on Client/TestKit; delete only the tests covering the removed reducer API | ⬜ | — |
| 24 | Final lint + `fxios test` + simulator build | ⬜ | — |

## Verification log

| Date | Check | Result |
| - | - | - |
| 2026-08-21 | Baseline Fennec simulator build | Pass (exit 0) |
| 2026-08-21 | Fennec build after WebCompatReporter | Pass (exit 0) |
| 2026-08-21 | WebCompatReporter tests (4 suites, 76 tests) | Pass |
| 2026-08-21 | Fennec build after PasswordGenerator | Pass, after 3 Sendable fixes (D-013) |
| 2026-08-21 | WebCompatReporter + PasswordGenerator tests | 197/199 pass; 2 pre-existing Google Lens camera failures |
| 2026-08-22 | Fennec build after NativeErrorPage | Pass (exit 0) |
| 2026-08-22 | NativeErrorPage + BrowserViewController tests (111) | Pass, 0 failures |
| 2026-08-22 | Fennec build after Microsurvey survey | Pass, after a `@MainActor` closure-type fix |
| 2026-08-22 | Microsurvey + Toolbar tests (91) | Pass, 0 failures |
| 2026-08-22 | Fennec build after TrackingProtection | Pass (exit 0), first try |
| 2026-08-22 | TrackingProtection tests (20) | Pass, 0 failures |
| 2026-08-22 | Fennec build + tests after TranslationSettings | Pass (`b7215b3655`, `476a9d85f5`) |
| 2026-08-22 | Fennec build + tests after TermsOfUse | Pass (`6f6f552cc4`); 12 view-model tests replace 26 reducer/middleware tests (D-009) |

## Notes / blockers

- **Phase 1 is smaller than first planned.** The original ordering used a middleware-only
  coupling map. Reducers consume foreign actions too (D-012), which moved three modules to
  later phases.
- **`import Redux` will not fall to zero — by design.** 31 files across 15 module directories
  dispatch browser-level actions to 5 consumers. D-011 assumed these convert once
  `BrowserViewController` migrates; **D-016 supersedes that** — they stay on the retained browser
  event bus permanently, because the alternative is 31 untyped `NotificationCenter` posts.
- **Shared-file churn is the real bottleneck.** Every module migration edits `AppState.swift`,
  `AppComponent.swift`, and `PresentedComponentsState.swift` at adjacent lines, which is why
  migrations run serially (D-010).
- **Two latent bugs found and fixed so far**, both caused by middlewares holding mutable state
  outside the store: `PasswordGeneratorMiddleware`'s racing `nonisolated(unsafe)` rules cache
  (FXIOS-12590) and `NativeErrorPageMiddleware`'s single app-wide error helper, which bled one
  window's error page into another on iPad.
- **Two pre-existing test failures on this host.** `BrowserCoordinatorTests`
  `testShowGoogleLensCamera_whenCameraUnavailable_*` assumes the simulator has no camera;
  `CameraCoordinator` defaults `isCameraAvailable` to
  `UIImagePickerController.isSourceTypeAvailable(.camera)`, which is true here via Mac camera
  passthrough. Unrelated to this migration.
- **Commit size.** Removing a module's Redux triple lands 600-1900 changed lines, over the
  500-line target. It cannot be split further without intermediate commits that fail to compile,
  because the new and old types collide on name. Each commit is module-scoped and builds.
- **Grep for `ComponentState` cases, not just type names, before deleting a screen.** Removing the
  survey broke `MicrosurveyPromptMiddlewareTests`, which seeded an `AppState` containing
  `.microsurvey(...)` in a test-only `setupAppState()` helper. A search for the Survey types alone
  missed it. Hub modules have many more hand-built `AppState` fixtures.
- **`Client.xcodeproj` needs hand editing per file.** Only 9 folders are
  `PBXFileSystemSynchronizedRootGroup`s; everything else is explicitly referenced. Adding or
  deleting a file requires four pbxproj lines, handled by `refactor-tracking/tools/pbx_add.py`
  and `pbx_remove.py`.

## Homepage complete (Phase 3, module group C)

Ten sections migrated one slice at a time, in this order: MessageCard, TrackerBlockerModule,
Bookmarks, Merino, SearchBar, Header, Wallpaper, TopSites, JumpBackIn, then the finale
(`HomepageState`, `HomepageTelemetryState`, `HomepageMiddleware`, `StoreSubscriber`).

Counters at the start of the homepage and now:

| | start | now |
|---|---|---|
| registered middlewares | 13 | 9 |
| StoreSubscriber screens | 12 | 11 |
| AppComponent cases | 9 | 8 |
| files with `import Redux` | 138 | 121 |
| dispatch call sites | 316 | 277 |
| migration-introduced notifications | 3 | 3 |

### What the homepage taught

- **Keep the state struct, drop the conformance.** Five of the ten sections had a state struct
  that the diffable data source or a cell takes by value (`HeaderState`, `WallpaperState`,
  `TopSitesSectionState`, `JumpBackInSectionState`). Removing `StateType`/`ScreenState` and the
  reducer while leaving the struct kept the churn to the reducer itself. Inventing a parallel
  `Configuration` type would have touched every cell and the item enum for nothing (D-021).
- **The bus earned its keep here.** Three sections consume it — the search bar's hide events, jump
  back in's tab events, and the homepage's own tab-changed impression reset. Jump back in alone
  collapses twelve action-type cases across two middlewares into one observer (D-027).
- **Middlewares that were services in all but name.** `QuickAnswersMiddleware` was already being
  default-constructed as a `QuickAnswersStore` by the header's state (D-020). `WallpaperMiddleware`
  re-announced an event `WallpaperManager` was already posting as a notification (D-022).
  `TopSitesMiddleware` said in its own doc comment that its telemetry should be split out (D-024).
- **Dead code surfaces when you move it.** The row-count settings row dispatched on every draw of
  its `status` getter; `HomepageTelemetryExtras.topSitesTelemetryConfig` had been nil at every call
  site since it was added; three of the layout provider's four store reads bound a value nothing
  used.
- **Two more real bugs fixed.** A retain cycle in `HomepageViewController` — the news transition
  header took two unapplied method references, which capture `self` strongly, and the supplementary
  view holds them for the homepage's whole lifetime. And the shortcuts library sized its grid from
  the *homepage's* tiles-per-row read out of the store, rather than from its own width.
- **Test hygiene rule that emerged (D-026).** A view model a test constructs must take every
  collaborator as a parameter, and the helpers must pass them. Falling through to an
  `AppContainer.shared.resolve()` default crashes the test *process* rather than failing an
  assertion, because the mock helper resets the container between tests.

## Checkpoint after Tabs

Full `ClientTests`: 2212 tests, 2 skipped, 1 failure — `BrowserCoordinatorTests`
`testShowGoogleLensCamera_whenCameraUnavailable_*`, the known host artifact (the Mac camera
passthrough makes the simulator report a camera).

One flake seen once and not reproducible:
`SwipeUpTabPreviewGestureHandlerTests.testHandlePanGesture_whenInteractiveGestureDisabled_doesNotDispatch`
asserts the mock store is empty. Probing it printed an empty array, and it passes on repeat runs
in isolation. Looks like cross-test contamination of the shared store rather than anything this
migration introduced, but worth re-checking in the final sweep.

Counters: middlewares 6 (from 28), StoreSubscriber screens 5 (from 12), AppComponent cases 2
(from 10 — `browserViewController` and `toolbar`), `import Redux` 106 (from 138), dispatch sites
205 (from 316).

## Phase 3 complete — the middleware layer is gone

The six remaining middlewares are bus-observing services (D-040), so the store is constructed with
no middlewares at all and `Middleware.swift` is deleted. What is left of Redux is exactly what
D-016 said would be left: `Action`, `ActionType`, a window-keyed dispatch, and the observer list.

### The part that was not mechanical

Converting a middleware into an observer looks like a rename — the body does not change — and that
is the trap. The middleware chain guaranteed two things that nothing in the code named, so nothing
failed loudly when they were dropped (D-041):

1. **Every reducer ran before any middleware.** `ToolbarActionHandler` reads the toolbar state that
   `ToolbarViewModel` owns. The handler registers at launch, the view model when its window opens,
   so on one flat list the handler read state one action behind — silently, and only in production,
   because every test seeds the view model directly. Observers now have a `.state`/`.effects` tier.
2. **Middlewares saw modern actions.** Observers only received legacy ones, so the four
   `ToolbarModernAction` dispatch sites reached nothing: the address bar would have stopped
   minimising on scroll and stopped reacting to the keyboard hiding.

Neither was caught by a test. Both were found by asking what the chain did that a list does not.

### Two test-isolation bugs fixed on the way

- `ToolbarViewModel.instances` is a static registry, so a state one test seeded was read by the
  next. `StoreTestUtilityHelper.resetStore` clears it now.
- `SwipeUpTabPreviewGestureHandlerTests`' close-tab animation completes asynchronously and
  dispatches into whichever store is current — the *next* test's. That is the flake recorded in the
  Tabs checkpoint above; it asserts on actions dispatched after its own gesture now. Its
  "no toolbar state" test is gone: every window has a `ToolbarViewModel`, so the handler's
  `toolbarState` is non-optional and the four real position/direction cases replace it.

### Names

The six classes are `*ActionHandler` now, and `MockStoreForMiddleware` — which mocks the bus — is
`MockStore`. The `*MiddlewareAction` families keep their names; they are retained bus vocabulary and
renaming them is 230 references in files this branch does not otherwise touch (D-042).

### Counters

middlewares 0 (from 28), StoreSubscriber screens 0 (from 12), AppComponent cases 0 (from 10),
`import Redux` 106 (from 138), dispatch sites 201 (from 316), action families on the bus 21.

The last three are the D-016 budget rather than a burn-down: `import Redux` and the dispatch count
stay high because the bus is retained and every observer imports it. `burndown.sh` now groups them
that way and fails if the action families or the migration-introduced notifications grow.

## Phase 4 complete — the bus is all that is left

`BrowserKit/Sources/Redux` is four files: `Action`, `ActionObserving`, `ActionDispatching` and
`BrowserEventBus`. No state, no reducer, no subscriptions, nothing generic over an app state.

- **Item 19/20.** `AppState`, `ScreenState`, `Reducer`, `StateType`, `StoreSubscriber` and
  `Subscription` deleted. The five states that still reduce keep their bodies and expose
  `reduce(_:with:)`; what they needed from `StateType` is `ResettableState` (D-045).
- **Item 21.** `Store` → `BrowserEventBus`, `DispatchStore` → `ActionDispatching`,
  `DefaultDispatchStore` → `BrowserEventBusing`, the global `store` → `browserEventBus`,
  `MockStore` → `MockBrowserEventBus`, `StoreTestUtility` → `BusTestUtility`.
- **Item 22.** The two D-014 tracking-protection notifications are `GeneralBrowserAction` types.
  The notification budget is 1, and the one left is the legitimate one.
- **Item 23.** `ReduxTests` covers the retained surface: delivery order, tiering, queueing, modern
  actions, and one integration test for the command → service → announcement round trip. TestKit no
  longer depends on Redux.
- Three action families with no callers deleted (D-046).

### Counters

middleware plumbing 0, StoreSubscriber screens 0, AppComponent cases 0, action families 19,
migration-introduced notifications 1, `import Redux` 98, dispatch sites 201.

`import Redux` and the dispatch count stay where they are by design: the bus is retained, and every
sender and observer imports it. That was D-016's call and it has not changed.

### Known issue, not introduced here

`BrowserCoordinatorTests` crashes its test host once per run: `testShouldShowNewTabToast_returnsFalse`
calls `showShortcutsLibrary()`, and something on that path resolves `UserFeaturePreferring` out of
`AppContainer` after `DependencyHelperMock().reset()` has emptied it. The resolver is
`UserFeaturePreferenceProvider.userPreferences`, which `BrowserViewController` gets via
`SearchBarLocationProvider` — a default argument evaluated on a deferred layout pass rather than
inside the test. The runner restarts and the suite passes; it predates Phase 4 and is the same
shape as D-026.
