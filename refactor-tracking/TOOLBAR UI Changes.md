# Toolbar UI — change log

Running record of every change made to the address-bar / toolbar UI under this project.
Newest work at the bottom. One entry per landed commit.

Companion file: [TOOLBAR_UI_BEFORE_AFTER.md](TOOLBAR_UI_BEFORE_AFTER.md) — holds the
before/after shape of each thing we touch, so a reader can see what the code looked like
previously and what it became.

## Why this project exists

The address bar needs to host more than one UI. Today it can host exactly one. The goal of
Task A is to install the seam that lets a second UI (Liquid Glass — floating, interactive,
iOS 26+) be added later as a peer rather than a fork, with a feature flag deciding which one
runs, while the existing bar stays pixel-identical.

## Scope boundary

Task A is **pure refactor plus dormant flag**. No new UI, no visual change. If a user can see
a difference with the flag off, Task A has failed.

Task B (separate branch, later) builds the Liquid Glass variant.

## Invariants — must hold at every commit

1. **Shrink-on-scroll must keep working.** The address bar minimizes as the user scrolls.
   `isAddressBarMinimized`, `shouldBlur` and `backgroundAlpha` are runtime-dynamic values
   driven by scroll, not fixed properties of a design variant. They must not be folded into
   the new style type.
2. **Existing bar is byte-identical.** Firefox ships the `.experiment(...)` shape, not
   `.default(...)` — `.default(...)` is reachable only from SampleBrowser. So the new
   `.standard` style must reproduce `.experiment(...)` exactly and `.legacy` must reproduce
   `.default(...)` exactly, both asserted by test.
3. **One flag read.** The feature flag is read in exactly one place — the factory. No variant
   class asks whether it is enabled.
4. **Build green at every commit.** Production and tests in separate commits, production first.

## Changes

### Task A — the seam (branch `nbhasin2/FXIOS-16660-address-toolbar-seam`)

| # | Commit | Area | What changed |
| - | - | - | - |
| 1 | `f0444c5a16` | docs | This file and `TOOLBAR_UI_BEFORE_AFTER.md`, with the four invariants. |
| 2 | `7538b68cb2` | Client | `liquidGlassAddressBar` Nimbus flag, off by default, no effect yet. Five registration points plus the `debugKey` entry. |
| 3 | `ae2603e170` | BrowserKit | `AddressToolbarStyle` (`.standard` / `.legacy` / `.liquidGlass`) carrying the four style-fixed values; the four runtime values stay init parameters. Both factory signatures unchanged. |
| 4 | `2d7d0d9f69` | BrowserKit + Client | `AddressToolbar` widened to `: UIView, ThemeApplicable`; delegate retyped off the concrete class; container holds `any AddressToolbar`; construction moves behind `AddressToolbarFactory`. 79 insertions. |
| 5 | `0c66fda937` | tests | 11 characterization tests pinning all eight UX config fields for both factories, plus the flag debug-override test. |

### Verification

- ToolbarKit: `BrowserKit-Package` scheme, `-only-testing:ToolbarKitTests`, iPhone 16e / iOS 26.2 —
  11 tests in 1 suite passed.
- Client: `Fennec` scheme built for iPhone 16e / iOS 26.2.
- `swiftlint --strict` clean on every file touched.
- The five commits above were landed in dependency order and the tree was verified at the tip;
  they were not each built individually.

### What Task A deliberately did not do

- No new UI. The Liquid Glass toolbar does not exist yet.
- The flag cannot change what a user sees: `makeAddressToolbar()` returns the standard bar for
  either variant. Turning the flag on in the debug menu is a no-op by design.
- `theme.isNova` was left alone. It is a second, independent variant channel that also reaches
  address-bar colours, and collapsing it into `AddressToolbarStyle` is a separate decision.
- The two iPad skeleton bars still build the standard toolbar. What they should do under a
  floating UI is a Task B question.

### Open question for Task B

Floating breaks constraint ownership. The container owns `toolbarLeadingConstraint` /
`toolbarTrailingConstraint` and pins the bar edge-to-edge; the anchors are reachable through the
protocol, so a floating variant can be laid out, but nothing yet lets a variant *state* its own
insets. Either add `preferredEdgeInsets` to the protocol or let the variant install its own
constraints — decide once, in Task B, before any glass code is written.
