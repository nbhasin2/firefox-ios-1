# Progress — FXIOS-16660

Branch: `nbhasin2/FXIOS-16660-remove-redux-mvvm-combine`
Baseline: `main` @ f2a42cbea7

## Burn-down

| Metric | Baseline | Current | Target |
| - | - | - | - |
| Files with `import Redux` | 200 | 200 | 0 |
| `store.dispatch` call sites | 451 | 451 | 0 |
| `Action` conforming types | 47 | 47 | 0 |
| Registered middlewares | 28 | 28 | 0 |
| `StoreSubscriber` screens | 20 | 20 | 0 |
| Screens in `AppComponent` | 17 | 17 | 0 |

Refresh with `refactor-tracking/burndown.sh`.

## Phase status

| Phase | Scope | Status |
| - | - | - |
| 0 — Analysis & scaffolding | Inventory, coupling map, tracking docs, branch | **Done** |
| 1 — Isolated leaf screens | 8 modules, no inbound coupling | In progress |
| 2 — Single-coupling screens | 5 modules | Not started |
| 3 — Hub modules | Homepage, Tabs, Toolbar, BVC | Not started |
| 4 — Global teardown | Delete Redux core + AppState | Not started |

## Module status

Legend: ⬜ not started · 🟡 in progress · ✅ done

### Phase 1 — isolated leaves

| # | Module | LOC | Status | Commit |
| - | - | - | - | - |
| 1 | WebCompatReporter | 433 | 🟡 pilot | — |
| 2 | PasswordGenerator | 942 | ⬜ | — |
| 3 | NativeErrorPage | 1,993 | ⬜ | — |
| 4 | SearchEngineSelection | 1,351 | ⬜ | — |
| 5 | TranslationSettings | ~600 | ⬜ | — |
| 6 | StartAtHome | ~200 | ⬜ | — |
| 7 | TrackingProtection | 4,349 | ⬜ | — |
| 8 | Microsurvey (survey) | ~800 | ⬜ | — |

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
| 2026-08-21 | Baseline Fennec simulator build | Running |

## Notes / blockers

- Nothing blocked yet.
