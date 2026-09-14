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
private lazy var leftSkeletonAddressBar: RegularBrowserAddressToolbar = .build()
private lazy var rightSkeletonAddressBar: RegularBrowserAddressToolbar = .build()
```

An `AddressToolbar` protocol already existed but nothing used it. Of roughly 25 distinct member
accesses the container made on these three properties, only two came from that protocol —
`configure(...)` and `setAutocompleteSuggestion(_:)`. Everything else came from `UIView`,
`ThemeApplicable`, or `BrowserAddressToolbar` itself. So a second UI could only arrive as a fork.

**After**

```swift
private var toolbar: any AddressToolbar {
    return regularToolbar
}

private lazy var toolbarFactory: AddressToolbarFactory = DefaultAddressToolbarFactory()
private lazy var regularToolbar: any AddressToolbar = toolbarFactory.makeAddressToolbar()
private lazy var leftSkeletonAddressBar: any AddressToolbar = toolbarFactory.makeAddressToolbar()
private lazy var rightSkeletonAddressBar: any AddressToolbar = toolbarFactory.makeAddressToolbar()
```

The container no longer names a concrete toolbar type anywhere.

**Why.** A second address-bar UI has to be a peer of the first, selected at construction time.
That is only possible if the container's dependency is an abstraction.

---

## 2. The `AddressToolbar` protocol

**Before** — `BrowserKit/Sources/ToolbarKit/AddressToolbar/AddressToolbar.swift`

```swift
@MainActor
public protocol AddressToolbar {
    func configure(config: AddressToolbarConfiguration, ...)
    func setAutocompleteSuggestion(_ suggestion: String?)
}
```

Two members, not class-constrained. The container needed view geometry, theming and
first-responder control, none of which this offered — which is why it could not adopt it.

**After**

```swift
@MainActor
public protocol AddressToolbar: UIView, ThemeApplicable {
    var isUnifiedSearchEnabled: Bool { get set }
    func configure(config: AddressToolbarConfiguration, ...)
    func configureNonInteractive(config: AddressToolbarConfiguration,
                                 leadingSpace: CGFloat,
                                 trailingSpace: CGFloat)
    func setAutocompleteSuggestion(_ suggestion: String?)
}
```

Inheriting `UIView` is what makes this work. Swift permits a protocol to require a superclass,
and `any AddressToolbar` then exposes every `UIView` member the container uses — the layout
anchors, `alpha`, `transform`, `isHidden`, `superview`, `accessibilityIdentifier`,
`removeFromSuperview()`, `becomeFirstResponder()`, `resignFirstResponder()`, and passing the
toolbar to `addSubview`/`insertSubview`. It also makes the existential class-constrained, so
`===` works. This was verified with a standalone compile probe before the design was committed
to; the only two members that genuinely had to be hoisted were `isUnifiedSearchEnabled` and
`configureNonInteractive`.

One consequence worth knowing: `UIView.build()` is generic over `T: UIView` and cannot infer
`T` from an existential target, so construction must bind a concrete type first. The factory
does that in one place.

---

## 3. How UI variation was expressed

**Before** — `BrowserKit/Sources/ToolbarKit/AddressToolbar/AddressToolbarUXConfiguration.swift`

Eight fields varied through two static factories, `.default(...)` and `.experiment(...)`.

The decisive detail, which was not obvious until the call sites were traced: **both factories
accept only four parameters** — `backgroundAlpha`, `isAddressBarMinimized`, `shouldBlur`,
`hasAlternativeLocationColor` — and bake the other four. The type gave no hint that these two
groups are different kinds of thing.

There are only three call sites repo-wide. The Firefox app always uses `.experiment(...)`
(twice, in `AddressToolbarContainerModel`); `.default(...)` is reachable only from SampleBrowser.
Nothing chose between them at runtime — the "experiment" name is vestigial.

**After** — new `AddressToolbarStyle` carries exactly the four baked values:

```swift
public enum AddressToolbarStyle {
    case standard      // reproduces today's .experiment(...)
    case legacy        // reproduces today's .default(...)
    case liquidGlass   // resolves to .standard for now
}
```

`AddressToolbarUXConfiguration` stores the style, derives those four fields from it, and keeps
the other four as init parameters. `.experiment(...)` and `.default(...)` survive with
byte-identical signatures as thin wrappers over a new `make(style:...)`, so not one of the three
call sites had to move.

**The four dynamic values and why they stay parameters:**

| Field | Driver | Changes at runtime |
| - | - | - |
| `isAddressBarMinimized` | scroll alpha reaching zero, keyboard accessory, keyboard hide | **yes — this is shrink-on-scroll** |
| `hasAlternativeLocationColor` | toolbar position + nav toolbar + top tabs | yes, on rotation / size class |
| `shouldBlur` | `!UIAccessibility.isReduceTransparencyEnabled` | yes, on accessibility change |
| `backgroundAlpha` | `shouldBlur` plus OS version | yes, on accessibility change |

Folding any of these into the style would have broken shrink-on-scroll, because the minimize
signal would stop being able to vary independently of the chosen UI.

**Why.** Adding Liquid Glass as more booleans would put the scroll-driven values in the same bag
as the static ones, making it easy to break the minimize behaviour by accident, and would take
the nominal configuration space past anything reviewable.

---

## 4. The shrink-on-scroll path (unchanged, but now pinned)

Not modified by this work — recorded because it constrains everything above.

A scroll gesture translates the header/bottom container but does **not** minimize the address
bar mid-drag. On drag end, if the movement passed a 20pt threshold, `ToolbarAnimator` drives the
toolbar alpha to 0 or 1 and calls `dispatchScrollAlphaChange(alpha:)`. That derives
`minimizeAddressBar = alpha.isZero`, which reaches `ToolbarState`, then
`AddressToolbarContainerModel`, then `isAddressBarMinimized` on the config. The visible shrink is
a 0.7 scale transform plus a vertical offset applied to `LocationView`, with the action stacks
hidden and the location container background set to clear.

Both the current `TabScrollHandler` and `LegacyTabScrollController` paths feed this, and both are
preserved. The two iPad skeleton bars deliberately pass neither `isAddressBarMinimized` nor
`hasAlternativeLocationColor`, so they stay pinned to `false` — easy to lose in a refactor, so
it is called out here.

---

## 5. Feature flag

**Before.** No flag for address-bar UI variants. The nearest precedent is `novaDesign`, read at
15+ call sites scattered across unrelated files (`ZoomPageBar`, `UIAlertController+Extension`,
`HistoryPanel`, `TabTrayViewController`).

**After.** `liquidGlassAddressBar`, defaulted off, registered across the five places the Nimbus
recipe requires — the feature YAML, the FML include list, `FeatureFlagID` (both the enum case
and the `debugKey` list), `NimbusFeatureFlagLayer` (switch case plus check method), and a
`FeatureFlagsBoolSetting` in the debug menu so it can be toggled at runtime.

It is read in exactly one place, `DefaultAddressToolbarFactory.variant`, gated on both the flag
and `#available(iOS 26.0, *)`. The flag is inert in effect: both variants currently build the
standard bar, because the Liquid Glass implementation does not exist yet. Adding it is one new
case in `makeAddressToolbar()`; nothing above that function changes.

**Why.** A diffuse flag is not a variant, it is a permanent conditional. One read at one factory
keeps the variant removable, and means no toolbar implementation ever asks whether it is the
selected one.
