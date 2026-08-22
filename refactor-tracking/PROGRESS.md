# Progress — FXIOS-16660

Branch: `nbhasin2/FXIOS-16660-remove-redux-mvvm-combine`
Baseline: `main` @ f2a42cbea7

## Burn-down

| Metric | Baseline | Current | Target |
| - | - | - | - |
| Files with `import Redux` | 200 | 177 | 0 |
| `store.dispatch` call sites | 451 | 408 | 0 |
| `Action` conforming types | 47 | 42 | 0 |
| Registered middlewares | 28 | 24 | 0 |
| `StoreSubscriber` screens | 20 | 16 | 0 |
| Screens in `AppComponent` | 17 | 13 | 0 |

Refresh with `refactor-tracking/burndown.sh`.

## Phase status

| Phase | Scope | Status |
| - | - | - |
| 0 — Analysis & scaffolding | Inventory, both coupling maps, tracking docs, branch | **Done** |
| 1 — Isolated leaf screens | 5 modules (was 8; see D-012) | 4 of 5 done |
| 2 — Single-coupling screens | 5 modules | Not started |
| 3 — Hub modules | Homepage, Tabs, Toolbar, BVC | Not started |
| 4 — Global teardown | Delete Redux core + AppState | Not started |

## Module status

Legend: ⬜ not started · 🟡 in progress · ✅ done

### Phase 1 — isolated leaves

| # | Module | LOC | Status | Notes |
| - | - | - | - | - |
| 1 | WebCompatReporter | 433 | ✅ | Fully Redux-free; app builds, 76 tests pass |
| 2 | PasswordGenerator | 942 | ✅ | Fully Redux-free; removed `nonisolated(unsafe)` rules cache (FXIOS-12590) |
| 3 | NativeErrorPage | 1,993 | ✅ | Fixed per-window error bleed; keeps browser-level dispatches (D-011) |
| 4 | TrackingProtection | 4,349 | ⬜ | |
| 5 | Microsurvey (survey) | ~800 | ✅ | Screen now holds no state; Prompt half stays until Toolbar |

Moved out of Phase 1 by D-012 (reducer-level coupling): SearchEngineSelection → Phase 3 (Toolbar),
ShortcutsLibrary → Phase 3 (Homepage/Tabs), StartAtHome → Phase 3 (BVC),
TranslationSettings → Phase 2 (pairs with Translations).

### Phase 2 — single inbound coupling

| # | Module | LOC | Status | Commit |
| - | - | - | - | - |
| 9 | ShortcutsLibrary | 686 | ⬜ | — |
| 10 | TermsOfUse | 1,481 | ⬜ | — |
| 11 | QuickAnswers + Summarizer | ~900 | ⬜ | — |
| 12 | Translations (runtime) | ~700 | ⬜ | — |
| 13 | MainMenu | 2,369 | ⬜ | — |
| 14 | FeltPrivacy + ThemeSettings | ~400 | ⬜ | — |

### Phase 3 — hubs

| # | Module | LOC | Status | Commit |
| - | - | - | - | - |
| 15 | Homepage — TopSites | — | ⬜ | — |
| 16 | Homepage — Merino | — | ⬜ | — |
| 17 | Homepage — MessageCard | — | ⬜ | — |
| 18 | Homepage — Bookmarks / JumpBackIn | — | ⬜ | — |
| 19 | Homepage — Wallpaper | — | ⬜ | — |
| 20 | Homepage — TrackerBlockerModule | — | ⬜ | — |
| 21 | Homepage — shell + HomepageState | — | ⬜ | — |
| 22 | Tabs — TabsPanel | — | ⬜ | — |
| 23 | Tabs — TabTray | — | ⬜ | — |
| 24 | Tabs — RemoteTabsPanel | — | ⬜ | — |
| 25 | Tabs — TabPeek | — | ⬜ | — |
| 26 | Tabs — TabManagerMiddleware teardown | — | ⬜ | — |
| 27 | Toolbar — AddressBar | — | ⬜ | — |
| 28 | Toolbar — NavigationBar | — | ⬜ | — |
| 29 | Toolbar — ToolbarMiddleware teardown | — | ⬜ | — |
| 30 | MicrosurveyPrompt | — | ⬜ | — |
| 31 | BrowserViewController | — | ⬜ | — |

### Phase 4 — teardown

| # | Item | Status | Commit |
| - | - | - | - |
| 32 | Delete `Client/Redux/GlobalState/` | ⬜ | — |
| 33 | Delete `BrowserKit/Sources/Redux` + tests | ⬜ | — |
| 34 | Drop `Redux` product from `Package.swift` / TestKit | ⬜ | — |
| 35 | Final lint + `fxios test` + simulator build | ⬜ | — |

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

## Notes / blockers

- **Phase 1 is smaller than first planned.** The original ordering used a middleware-only
  coupling map. Reducers consume foreign actions too (D-012), which moved three modules to
  later phases.
- **`import Redux` will not fall linearly.** 31 files across 14 modules dispatch browser-level
  actions that cannot be converted until `BrowserViewController` migrates (D-011).
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
