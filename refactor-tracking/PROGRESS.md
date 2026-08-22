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
