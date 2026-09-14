# Toolbar UI — before and after

For each thing this project touches: what the code was, what it became, and why.
Companion to [TOOLBAR UI Changes.md](TOOLBAR%20UI%20Changes.md), which is the commit-by-commit log.

Baseline for all "before" snapshots: `d3b213450b` on
`nbhasin2/FXIOS-16660-remove-redux-mvvm-combine`.

---

## 1. The container's dependency on the toolbar

**Before** — `firefox-ios/Client/Frontend/Browser/Toolbars/AddressToolbarContainer.swift:88`

```swift
private var toolbar: BrowserAddressToolbar {
    return regularToolbar
}

private lazy var regularToolbar: RegularBrowserAddressToolbar = .build()
```

An `AddressToolbar` protocol already existed but nothing used it. The container named the
concrete class, so a second UI could only arrive as a fork of `BrowserAddressToolbar`.

**After** — filled in when the change lands.

**Why.** A second address-bar UI has to be a peer of the first, selected at construction time.
That is only possible if the container's dependency is an abstraction.

---

## 2. The `AddressToolbar` protocol

**Before** — `BrowserKit/Sources/ToolbarKit/AddressToolbar/AddressToolbar.swift`

```swift
@MainActor
public protocol AddressToolbar {
    func configure(config: AddressToolbarConfiguration,
                   toolbarPosition: AddressToolbarPosition,
                   toolbarDelegate: AddressToolbarDelegate,
                   leadingSpace: CGFloat,
                   trailingSpace: CGFloat,
                   isUnifiedSearchEnabled: Bool,
                   animated: Bool)

    func setAutocompleteSuggestion(_ suggestion: String?)
}
```

Two members. The container needed far more than this — view geometry, theming, first-responder
control — which is why it could not adopt the protocol.

**After** — filled in when the change lands.

---

## 3. How UI variation was expressed

**Before** — `BrowserKit/Sources/ToolbarKit/AddressToolbar/AddressToolbarUXConfiguration.swift`

Eight fields, varied through two static factories (`.default(...)` and `.experiment(...)`),
with four of them also settable per call:

```swift
toolbarCornerRadius: CGFloat = if #available(iOS 26, *) { 22 } else { 12 }
browserActionsAddressBarDividerWidth: CGFloat
isLocationTextCentered: Bool
hasAlternativeLocationColor: Bool
locationTextFieldTrailingPadding: CGFloat
shouldBlur: Bool
backgroundAlpha: CGFloat
isAddressBarMinimized: Bool
```

Plus a parallel channel: `theme.isNova`, consulted inside
`locationContainerBackgroundColor(theme:)`.

The problem: these are two different kinds of thing wearing the same coat. Some are fixed
properties of a design variant; others change many times a second as the user scrolls. Nothing
in the type says which is which, so every new variant multiplies the nominal state space.

**After** — filled in when the change lands.

**Why.** Adding Liquid Glass as more booleans would take the nominal configuration space past
anything reviewable, and would put the scroll-driven values in the same bag as the static ones —
making it easy to break shrink-on-scroll by accident.

---

## 4. Feature flag

**Before.** No flag for address-bar UI variants. The nearest precedent is `novaDesign`, which
is read at 15+ call sites scattered across unrelated files (`ZoomPageBar`,
`UIAlertController+Extension`, `HistoryPanel`, `TabTrayViewController`).

**After** — filled in when the change lands.

**Why.** A diffuse flag is not a variant, it is a permanent conditional. One read at one factory
keeps the variant removable.
