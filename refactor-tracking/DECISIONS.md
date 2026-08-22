# Architectural decisions — FXIOS-16660

Decisions are numbered and immutable; a superseded decision gets a new entry that references it.

---

## D-001 — Strangler-fig migration, not a big-bang rewrite

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
