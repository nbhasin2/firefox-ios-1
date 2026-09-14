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
2. **Existing bar is byte-identical.** The `.classic` style must yield the same field values
   that `AddressToolbarUXConfiguration.default()` yields today, asserted by test.
3. **One flag read.** The feature flag is read in exactly one place — the factory. No variant
   class asks whether it is enabled.
4. **Build green at every commit.** Production and tests in separate commits, production first.

## Changes

| # | Commit | Area | What changed |
| - | - | - | - |
