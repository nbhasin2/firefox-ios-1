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
