# Files to change — FXIOS-16660

Generated from `grep -rl "import Redux" --include='*.swift' firefox-ios BrowserKit` at baseline
`main` @ f2a42cbea7. **200 files** import Redux directly; a further 74 touch a Redux construct
(`store.dispatch`, `AppState`, `StoreSubscriber`) without importing the module — those are listed
under *Indirect consumers*.

Legend for the Migration column:

- **State → plain struct on view model** — drop `ScreenState`/`StateType` conformance, keep the struct
- **Action → delete** — replaced by intent methods on the view model
- **Middleware → async view-model effects** — body folded into the owning view model as `async` methods
- **Consumer → drop `import Redux`** — call sites that dispatch or subscribe
- **Test → port to view-model test** — see DECISIONS.md D-007

---

## Migration order

Modules are grouped by inbound coupling (how many *other* modules' middlewares consume their
actions). Zero-coupling modules move first.

### Action-coupling map (middleware ⇢ foreign actions consumed)

| Middleware | Foreign actions consumed | Phase |
| - | - | - |
| `WebCompatReporterMiddleware` | — | 1 (pilot) |
| `PasswordGeneratorMiddleware` | — | 1 |
| `NativeErrorPageMiddleware` | — | 1 |
| `SearchEngineSelectionMiddleware` | — | 1 |
| `TranslationSettingsMiddleware` | — | 1 |
| `StartAtHomeMiddleware` | — | 1 |
| `TrackingProtectionMiddleware` | — | 1 |
| `MicrosurveyMiddleware` | — | 1 |
| `ShortcutsLibraryMiddleware` | — (but `ShortcutsLibraryAction` is read by `TabManagerMiddleware`) | 2 |
| `MicrosurveyPromptMiddleware` | — (but `MicrosurveyPromptAction` is read by `ToolbarMiddleware`) | 3 |
| `FeltPrivacyMiddleware` | `PrivateModeAction` | 2 |
| `ThemeMiddleware` | `MainMenuAction`, `PrivateModeAction` | 2 |
| `QuickAnswersMiddleware` | `HomepageAction` | 2 |
| `SummarizeMiddleware` | `GeneralBrowserAction`, `NavigationBrowserAction`, `ToolbarAction` | 2 |
| `TranslationsMiddleware` | `ToolbarAction`, `ToolbarMiddlewareAction` | 2 |
| `TermsOfUseMiddleware` | `HomepageAction`, `HomepageMiddlewareAction` | 2 |
| `BookmarksMiddleware` | `HomepageAction` | 3 |
| `TrackerBlockerModuleMiddleware` | `HomepageAction` | 3 |
| `MerinoMiddleware` | `ContextMenuAction`, `HomepageAction` | 3 |
| `MessageCardMiddleware` | `HomepageAction` | 3 |
| `TopSitesMiddleware` | `ContextMenuAction`, `HomepageAction` | 3 |
| `WallpaperMiddleware` | `HomepageAction` | 3 |
| `HomepageMiddleware` | `NavigationBrowserAction` | 3 |
| `RemoteTabsPanelMiddleware` | `HomepageAction` | 3 |
| `MainMenuMiddleware` | — (but `MainMenuAction` is read by `TabManagerMiddleware`, `ThemeMiddleware`) | 2 |
| `TabManagerMiddleware` | `HomepageAction`, `JumpBackInAction`, `MainMenuAction`, `MainMenuMiddlewareAction`, `RemoteTabsPanelAction`, `ScreenshotAction`, `ShortcutsLibraryAction`, `TabPanelViewAction`, `TabPeekAction`, `TabTrayAction` | 3 |
| `ToolbarMiddleware` | `GeneralBrowserMiddlewareAction`, `MicrosurveyPromptAction`, `MicrosurveyPromptMiddlewareAction` | 3 |

`TabManagerMiddleware` (10 inbound edges) and `ToolbarMiddleware` are the hubs and migrate last,
immediately before `BrowserViewController`.

---

## Global files (Phase 4 — deleted last)

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Redux/GlobalState/AppState.swift` | 122 | Delete — replaced by per-screen view models |
| `firefox-ios/Client/Redux/GlobalState/PresentedComponentsState.swift` | 244 | Delete |
| `firefox-ios/Client/Redux/GlobalState/ScreenState.swift` | 15 | Delete |
| `firefox-ios/Client/Redux/GlobalState/AppComponent.swift` | 25 | Delete |
| `firefox-ios/Client/Redux/GlobalState/ComponentAction.swift` | 18 | Delete |
| `BrowserKit/Sources/Redux/*` | 412 | Delete module; drop product from `Package.swift` |
| `BrowserKit/Tests/ReduxTests/*` | — | Delete |
| `BrowserKit/Sources/TestKit` | — | Remove `Redux` dependency |

Each screen's case must be removed from `ComponentState`, `AppComponent`, and
`AppState.componentState(_:for:window:)` as that screen migrates — three edits per module.

---

## Full inventory by module

### Client/ContentBlocker  
*1 files, 59 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/ContentBlocker/TabContentBlocker+ContentScript.swift` | 59 | Consumer → drop `import Redux` |

### Client/Coordinators  
*2 files, 2152 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Coordinators/Browser/BrowserCoordinator.swift` | 1545 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Coordinators/SettingsCoordinator.swift` | 607 | Consumer → drop `import Redux` |

### Client/Redux  
*4 files, 399 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Redux/GlobalState/AppState.swift` | 122 | State → plain struct on view model |
| `firefox-ios/Client/Redux/GlobalState/ComponentAction.swift` | 18 | Action → delete (intent methods) |
| `firefox-ios/Client/Redux/GlobalState/PresentedComponentsState.swift` | 244 | State → plain struct on view model |
| `firefox-ios/Client/Redux/GlobalState/ScreenState.swift` | 15 | State → plain struct on view model |

### Frontend/Browser  
*1 files, 72 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/ToastType.swift` | 72 | Consumer → drop `import Redux` |

### Frontend/Browser/BrowserViewController  
*4 files, 6143 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/BrowserViewController/Actions/GeneralBrowserAction.swift` | 117 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/BrowserViewController/Actions/NavigationBrowserAction.swift` | 47 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/BrowserViewController/State/BrowserViewControllerState.swift` | 768 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/BrowserViewController/Views/BrowserViewController.swift` | 5211 | Consumer → drop `import Redux` |

### Frontend/Browser/MainMenu  
*4 files, 1331 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/MainMenu/Redux/MainMenuAction.swift` | 81 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/MainMenu/Redux/MainMenuMiddleware.swift` | 238 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Browser/MainMenu/Redux/MainMenuState.swift` | 361 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/MainMenu/Views/MainMenuViewController.swift` | 651 | Consumer → drop `import Redux` |

### Frontend/Browser/SearchEngines  
*4 files, 390 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/SearchEngines/Redux/SearchEngineSelectionAction.swift` | 36 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/SearchEngines/Redux/SearchEngineSelectionMiddleware.swift` | 63 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Browser/SearchEngines/Redux/SearchEngineSelectionState.swift` | 96 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/SearchEngines/Views/SearchEngineSelectionViewController.swift` | 195 | Consumer → drop `import Redux` |

### Frontend/Browser/StartAtHome  
*2 files, 145 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/StartAtHome/StartAtHomeAction.swift` | 30 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/StartAtHome/StartAtHomeMiddleware.swift` | 115 | Middleware → async view-model effects |

### Frontend/Browser/Tabs  
*18 files, 4751 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/Tabs/Action/RemoteTabsManagerAction.swift` | 38 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/Tabs/Action/RemoteTabsPanelAction.swift` | 50 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/Tabs/Action/TabManagerAction.swift` | 26 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/Tabs/Action/TabPanelAction.swift` | 110 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/Tabs/Action/TabPeekAction.swift` | 35 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/Tabs/Action/TabTrayAction.swift` | 39 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/Tabs/Action/TopTabsAction.swift` | 17 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/Tabs/Middleware/RemoteTabsPanelMiddleware.swift` | 211 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Browser/Tabs/Middleware/TabManagerMiddleware.swift` | 1103 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Browser/Tabs/State/RemoteTabsPanelState.swift` | 181 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/Tabs/State/TabPeekState.swift` | 112 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/Tabs/State/TabTrayState.swift` | 227 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/Tabs/State/TabsPanelState.swift` | 168 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/Tabs/Views/RemoteTabsPanel.swift` | 299 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/Tabs/Views/TabDisplayPanelViewController.swift` | 383 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/Tabs/Views/TabDisplayView.swift` | 411 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/Tabs/Views/TabPeekViewController.swift` | 145 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/Tabs/Views/TabTrayViewController.swift` | 1196 | Consumer → drop `import Redux` |

### Frontend/Browser/TermsOfUse  
*5 files, 805 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/TermsOfUse/TermsOfUseAction.swift` | 24 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/TermsOfUse/TermsOfUseMiddleware.swift` | 115 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Browser/TermsOfUse/TermsOfUseState.swift` | 103 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/TermsOfUse/View/TermsOfUseLinkViewController.swift` | 170 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/TermsOfUse/View/TermsOfUseViewController.swift` | 393 | Consumer → drop `import Redux` |

### Frontend/Browser/Toolbars  
*10 files, 4407 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/Toolbars/AddressToolbarContainer.swift` | 739 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/Toolbars/NavigationToolbarContainer.swift` | 140 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/AddressBarState.swift` | 1181 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/NavigationBarState.swift` | 358 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarAction.swift` | 199 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarMiddleware.swift` | 616 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/ToolbarState.swift` | 398 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Browser/Toolbars/Redux/TranslationsConfiguration.swift` | 113 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/Toolbars/SwipeUpTabPreviewGestureHandler.swift` | 302 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Browser/Toolbars/TabSwipeGestureHandler.swift` | 361 | Consumer → drop `import Redux` |

### Frontend/Browser/WebCompat  
*1 files, 431 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Browser/WebCompat/WebCompatReportViewController.swift` | 431 | Consumer → drop `import Redux` |

### Frontend/FeltPrivacy  
*2 files, 69 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/FeltPrivacy/FeltPrivacyMiddleware.swift` | 43 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/FeltPrivacy/PrivateModeAction.swift` | 26 | Action → delete (intent methods) |

### Frontend/Home/Homepage  
*29 files, 4568 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Home/Homepage/Bookmark/BookmarksAction.swift` | 37 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/Bookmark/BookmarksMiddleware.swift` | 57 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Home/Homepage/Bookmark/BookmarksSectionState.swift` | 104 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/ContextMenu/ContextMenuAction.swift` | 37 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/ContextMenu/ContextMenuState.swift` | 443 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/Header/HeaderState.swift` | 88 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/HomepageViewController.swift` | 1512 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Home/Homepage/JumpBackIn/JumpBackInAction.swift` | 30 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/JumpBackIn/JumpBackInSectionState.swift` | 142 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/Merino/MerinoAction.swift` | 44 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/Merino/MerinoMiddleware.swift` | 85 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Home/Homepage/Merino/MerinoState.swift` | 134 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/MessageCard/MessageCardAction.swift` | 31 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/MessageCard/MessageCardMiddleware.swift` | 76 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Home/Homepage/MessageCard/MessageCardState.swift` | 77 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/Redux/HomepageAction.swift` | 74 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/Redux/HomepageMiddleware.swift` | 217 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Home/Homepage/Redux/HomepageState.swift` | 250 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/Redux/HomepageTelemetryState.swift` | 91 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/SearchBar/SearchBarState.swift` | 82 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/TopSites/TopSitesAction.swift` | 60 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/TopSites/TopSitesMiddleware.swift` | 266 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Home/Homepage/TopSites/TopSitesSectionState.swift` | 192 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/TrackerBlockerModule/TrackerBlockerModuleAction.swift` | 33 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/TrackerBlockerModule/TrackerBlockerModuleMiddleware.swift` | 82 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Home/Homepage/TrackerBlockerModule/TrackerBlockerModuleState.swift` | 101 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Home/Homepage/Wallpapers/Redux/WallpaperAction.swift` | 31 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Home/Homepage/Wallpapers/Redux/WallpaperMiddleware.swift` | 60 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Home/Homepage/Wallpapers/Redux/WallpaperState.swift` | 132 | State → plain struct on view model |

### Frontend/Microsurvey/Prompt  
*4 files, 415 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Microsurvey/Prompt/MicrosurveyPromptAction.swift` | 34 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Microsurvey/Prompt/MicrosurveyPromptMiddleware.swift` | 64 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Microsurvey/Prompt/MicrosurveyPromptState.swift` | 88 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Microsurvey/Prompt/MicrosurveyPromptView.swift` | 229 | Consumer → drop `import Redux` |

### Frontend/Microsurvey/Survey  
*4 files, 610 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Microsurvey/Survey/MicrosurveyAction.swift` | 29 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Microsurvey/Survey/MicrosurveyMiddleware.swift` | 65 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Microsurvey/Survey/MicrosurveyState.swift` | 82 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Microsurvey/Survey/View/MicrosurveyViewController.swift` | 434 | Consumer → drop `import Redux` |

### Frontend/NativeErrorPage  
*4 files, 752 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/NativeErrorPage/NativeErrorPageAction.swift` | 35 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/NativeErrorPage/NativeErrorPageMiddleware.swift` | 90 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/NativeErrorPage/NativeErrorPageState.swift` | 68 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/NativeErrorPage/NativeErrorPageViewController.swift` | 559 | Consumer → drop `import Redux` |

### Frontend/PasswordGenerator  
*4 files, 592 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/PasswordGenerator/PasswordGeneratorAction.swift` | 58 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/PasswordGenerator/PasswordGeneratorMiddleware.swift` | 169 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/PasswordGenerator/PasswordGeneratorState.swift` | 87 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/PasswordGenerator/PasswordGeneratorViewController.swift` | 278 | Consumer → drop `import Redux` |

### Frontend/QuickAnswers  
*2 files, 116 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/QuickAnswers/QuickAnswersAction.swift` | 44 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/QuickAnswers/QuickAnswersMiddleware.swift` | 72 | Middleware → async view-model effects |

### Frontend/Settings/ThemeSettings  
*1 files, 62 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Settings/ThemeSettings/ThemeMiddleware.swift` | 62 | Middleware → async view-model effects |

### Frontend/Settings/Translation  
*5 files, 1032 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Settings/Translation/TranslationLanguagePickerViewController.swift` | 164 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Settings/Translation/TranslationPickerSettingsViewController.swift` | 429 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Settings/Translation/TranslationSettingsAction.swift` | 76 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Settings/Translation/TranslationSettingsMiddleware.swift` | 188 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/Settings/Translation/TranslationSettingsState.swift` | 175 | State → plain struct on view model |

### Frontend/ShortcutsLibrary  
*4 files, 627 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/ShortcutsLibrary/Redux/ShortcutsLibraryAction.swift` | 37 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/ShortcutsLibrary/Redux/ShortcutsLibraryMiddleware.swift` | 53 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/ShortcutsLibrary/Redux/ShortcutsLibraryState.swift` | 112 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/ShortcutsLibrary/ShortcutsLibraryViewController.swift` | 425 | Consumer → drop `import Redux` |

### Frontend/Summarizer  
*2 files, 243 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Summarizer/SummarizeAction.swift` | 18 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Summarizer/SummarizeMiddleware.swift` | 225 | Middleware → async view-model effects |

### Frontend/TrackingProtection  
*5 files, 1398 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/TrackingProtection/TrackigProtectionRedux/TrackingProtectionAction.swift` | 39 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/TrackingProtection/TrackigProtectionRedux/TrackingProtectionMiddleware.swift` | 102 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/TrackingProtection/TrackigProtectionRedux/TrackingProtectionModel.swift` | 244 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/TrackingProtection/TrackigProtectionRedux/TrackingProtectionState.swift` | 215 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/TrackingProtection/TrackingProtectionViewController.swift` | 798 | Consumer → drop `import Redux` |

### Frontend/Translations  
*4 files, 1037 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/Translations/AutoTranslatePromptState.swift` | 50 | State → plain struct on view model |
| `firefox-ios/Client/Frontend/Translations/AutoTranslatePromptView.swift` | 169 | Consumer → drop `import Redux` |
| `firefox-ios/Client/Frontend/Translations/TranslationsAction.swift` | 56 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/Translations/TranslationsMiddleware.swift` | 762 | Middleware → async view-model effects |

### Frontend/WebCompatReporter  
*3 files, 383 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/Client/Frontend/WebCompatReporter/Redux/WebCompatReporterAction.swift` | 72 | Action → delete (intent methods) |
| `firefox-ios/Client/Frontend/WebCompatReporter/Redux/WebCompatReporterMiddleware.swift` | 113 | Middleware → async view-model effects |
| `firefox-ios/Client/Frontend/WebCompatReporter/Redux/WebCompatReporterState.swift` | 198 | State → plain struct on view model |

### Tests  
*60 files, 20346 LOC*

| File | LOC | Migration |
| - | - | - |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/BrowserViewController/BrowserViewControllerStateTests.swift` | 714 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Coordinators/BrowserCoordinatorTests.swift` | 1729 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Coordinators/Mocks/MockStoreForMiddleware.swift` | 73 | Middleware → async view-model effects |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Browser/SearchEngines/SearchEngineSelectionMiddlewareTests.swift` | 103 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Browser/SearchEngines/SearchEngineSelectionStateTests.swift` | 84 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/BookmarksMiddlewareTests.swift` | 103 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/BookmarksSectionStateTests.swift` | 196 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/HeaderStateTests.swift` | 133 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/HomepageMiddlewareTests.swift` | 654 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/HomepageStateTests.swift` | 179 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/HomepageTelemetryStateTests.swift` | 143 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/JumpBackInSectionStateTests.swift` | 223 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/MerinoMiddlewareTests.swift` | 257 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/MerinoStateTests.swift` | 348 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/MessageCardMiddlewareTests.swift` | 160 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/MessageCardStateTests.swift` | 94 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/SearchBarStateTests.swift` | 97 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/TopSitesMiddlewareTests.swift` | 713 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/TopSitesSectionStateTests.swift` | 335 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Redux/TrackerBlockerModuleMiddlewareTests.swift` | 225 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Wallpaper/WallpaperMiddlewareTests.swift` | 74 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Homepage/Wallpaper/WallpaperStateTests.swift` | 169 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/ShortcutsLibrary/Redux/ShortcutsLibraryMiddlewareTests.swift` | 151 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/ShortcutsLibrary/Redux/ShortcutsLibraryStateTests.swift` | 130 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Frontend/Summarizer/SummarizerMiddlewareTests.swift` | 512 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Helpers/ModifiedCopyMacroTests.swift` | 230 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/MainMenu/MainMenuMiddlewareTests.swift` | 737 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/MainMenu/MainMenuStateTests.swift` | 197 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/MainMenu/WebCompatReportViewControllerTests.swift` | 384 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Microsurvey/MicrosurveyMiddlewareTests.swift` | 141 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Microsurvey/MicrosurveyPromptStateTests.swift` | 106 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Microsurvey/MicrosurveyStateTests.swift` | 61 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Microsurvey/Mock/MicrosurveyPromptMiddlewareTests.swift` | 126 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/NativeErrorPage/NativeErrorPageMiddlewareTests.swift` | 99 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/NativeErrorPage/NativeErrorPageStateTests.swift` | 117 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/PasswordGenerator/PasswordGeneratorStateTests.swift` | 45 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/QuickAnswers/QuickAnswersMiddlewareTests.swift` | 195 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Settings/TranslationPickerSettingsViewControllerTests.swift` | 94 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Settings/TranslationSettingsMiddlewareTests.swift` | 512 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Settings/TranslationSettingsStateTests.swift` | 358 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/StartAtHome/StartAtHomeMiddlewareTests.swift` | 166 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TabManagement/TabManagerRestoreScreenshotTests.swift` | 85 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TabTray/Redux/RemoteTabPanelStateTests.swift` | 162 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TabTray/Redux/TabPeekStateTests.swift` | 146 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TabTray/Redux/TabTrayStateTests.swift` | 325 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TabTray/Redux/TabsPanelStateTests.swift` | 220 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TabTray/RemoteTabsMiddlewareTests.swift` | 217 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TabTray/TabManagerMiddlewareTests.swift` | 885 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TabTray/TabTrayStateTests.swift` | 269 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TermsOfUse/TermsOfUseStateTests.swift` | 120 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Toolbar/AddressBarStateTests.swift` | 1360 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Toolbar/NavigationBarStateTests.swift` | 299 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Toolbar/ToolbarMiddlewareTests.swift` | 1456 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Toolbar/ToolbarStateTests.swift` | 652 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TrackingProtectionTests/TrackingProtectionStateTests.swift` | 152 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TranslationsTests/AutoTranslatePromptStateTests.swift` | 95 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/TranslationsTests/TranslationsMiddlewareTests.swift` | 1901 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/Utils/StoreTestUtility.swift` | 47 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/WebCompatReporter/WebCompatReporterMiddlewareTests.swift` | 377 | Test → port to view-model test |
| `firefox-ios/firefox-ios-tests/Tests/ClientTests/WebCompatReporter/WebCompatReporterStateTests.swift` | 411 | Test → port to view-model test |

### Redux core (BrowserKit)  
*11 files, 882 LOC*

| File | LOC | Migration |
| - | - | - |
| `BrowserKit/Sources/TestKit/EmptyMiddlewareProviderFactory.swift` | 31 | Consumer → drop `import Redux` |
| `BrowserKit/Tests/ReduxTests/ActionTests.swift` | 156 | Test → port to view-model test |
| `BrowserKit/Tests/ReduxTests/Mocks/MockState.swift` | 44 | State → plain struct on view model |
| `BrowserKit/Tests/ReduxTests/ReduxIntegrationTests.swift` | 108 | Test → port to view-model test |
| `BrowserKit/Tests/ReduxTests/StoreModernActionTests.swift` | 97 | Test → port to view-model test |
| `BrowserKit/Tests/ReduxTests/StoreTests.swift` | 142 | Test → port to view-model test |
| `BrowserKit/Tests/ReduxTests/Utilities/FakeReduxAction.swift` | 38 | Action → delete (intent methods) |
| `BrowserKit/Tests/ReduxTests/Utilities/FakeReduxMiddleware.swift` | 88 | Middleware → async view-model effects |
| `BrowserKit/Tests/ReduxTests/Utilities/FakeReduxModernAction.swift` | 44 | Action → delete (intent methods) |
| `BrowserKit/Tests/ReduxTests/Utilities/FakeReduxState.swift` | 57 | State → plain struct on view model |
| `BrowserKit/Tests/ReduxTests/Utilities/FakeReduxViewController.swift` | 77 | Consumer → drop `import Redux` |


---

## Indirect consumers

74 further files reference `store.dispatch`, `AppState`, or `StoreSubscriber` without an
`import Redux` of their own (they get it transitively). They are found with:

```bash
grep -rlE "store\.dispatch|store\.subscribe|StoreSubscriber|AppState" \
  --include='*.swift' firefox-ios BrowserKit | grep -v '\.build'
```

These are almost entirely call sites — coordinators, cells, and gesture handlers that dispatch a
single action. They are fixed by the compiler as each module's action type is deleted, so they are
not enumerated per-module here; the 451 `dispatch` call sites are the true edit count.
