# FoldContinuity

**A fold is not a resize. It is the moment your app decides what the shopper gets to keep.**

iPhone Duo's inner display reports *regular* size classes in both dimensions; the outer display is
a normal compact-width iPhone. Every open, close, Split View drag and tabletop fold hands your scene
a new shape — and in most codebases the horizontal-size-class flip swaps the root container
(`NavigationStack` ↔ `NavigationSplitView`), which rebuilds the subtree and quietly discards the
draft text, focus, presented sheet, navigation path and scroll position the person was in the
middle of.

This package makes that loss **testable**:

- `Posture` / `DisplayShape` — posture as an *input*: the six shapes a Duo can hand you
  (669×951, 951×669, 466×678, 678×466, tabletop, Split View), each with its size classes.
- `ContinuityContract<State>` — a per-flow declaration of which fields **must survive** a posture
  change and which are legitimately **derived from posture**. One list, reviewable in a PR.
- `PostureFuzzer` — a seeded (SplitMix64) generator of posture sequences that replays any flow and
  reports every protected field that did not survive, with the step and the transition that lost it.
  Aspect ratio becomes a fuzzable test dimension instead of a device list.
- `CheckoutFlow` — a mid-checkout state and two adapters: `naive` (rebuild on horizontal flip) and
  `contracted` (posture only touches derived fields). Same layout output; only one keeps the work.

Article: (added after publish)

## What the fuzzer finds

Seed `2026`, 32 steps, starting closed: 21 of the 32 transitions change a size class and 16 flip the
horizontal one. The naive adapter loses `draftPromoCode`, `focusedField`, `presentedSheet`,
`navigationPath` and `scrollOffset` at **step 2** (`splitView → openPortrait`). The contracted
adapter reports zero violations on the identical sequence.

Across a 50-seed × 64-step campaign, 1,579 of 3,200 transitions flip the horizontal size class, all
50 naive runs fail, and the first loss lands between step 0 and step 6 (mean 0.8). Restrict the
posture set to `[.closedPortrait, .closedLandscape]` — every iPhone shipped before this one — and
the naive adapter passes every run. The bug was always there; the hardware just never triggered it.

## The contract

```swift
public enum CheckoutContract {
    public static let contract = ContinuityContract<CheckoutState>(
        flowName: "Checkout",
        fields: [
            ContinuityField("cartItemIDs", \.cartItemIDs),
            ContinuityField("selectedShippingOption", \.selectedShippingOption),
            ContinuityField("draftPromoCode", \.draftPromoCode),
            ContinuityField("focusedField", \.focusedField),
            ContinuityField("presentedSheet", \.presentedSheet),
            ContinuityField("navigationPath", \.navigationPath),
            ContinuityField("scrollOffset", \.scrollOffset),
            ContinuityField("layout", \.layout, rule: .derivedFromPosture)
        ]
    )
}
```

## The test that fails on a foldable and passes on a phone

```swift
func testNaiveCheckoutLosesWorkOnFirstSizeClassChange() {
    let report = PostureFuzzer().run(CheckoutAdapters.naive, seed: 2026, steps: 32)
    XCTAssertFalse(report.passed)
    let firstFlip = report.sequence.firstIndex(where: \.changesHorizontalSizeClass)
    XCTAssertEqual(report.firstFailingStep, firstFlip)
}

func testNaiveCheckoutPassesWhenPosturesNeverFlipSizeClass() {
    let phoneOnly = PostureFuzzer(postures: [.closedPortrait])
    XCTAssertTrue(phoneOnly.run(CheckoutAdapters.naive, seed: 5, steps: 32).passed)
}
```

## Run it

```bash
git clone https://github.com/rajatslakhina/fold-continuity-contract-article-demo.git
cd fold-continuity-contract-article-demo
swift test                 # 18 tests, no Xcode needed
open Demo.xcodeproj        # pick any iPhone Simulator, Build & Run
```

`Demo.xcodeproj` consumes the package through a local package reference, so one clone is the
whole thing. The demo screen (`ContinuityDemoView`) lets you pick a seed and step count, runs both
adapters through the same posture sequence, and lists the contract's verdict per field.

## Verification status

- `swift build`: 0 warnings, Swift 6.0.3 (Linux aarch64).
- `swift test`: 18/18 passing.
- **Simulator run: not performed.** This repo was produced by an unattended scheduled session in
  which the Xcode/Simulator grant cannot be approved; see `Demo/Screenshots/README.md`. The
  SwiftUI view was hand-reviewed, not compiled. No screenshot is embedded because none exists.

## Point sizes and size classes

Point sizes follow App Store Connect's iPhone Duo screenshot specification at 3x (inner 669×951,
outer 466×678, per Blake Crosley's arithmetic); size classes follow Apple's *Prepare your app for
iPhone Duo* Tech Talk. The Split View width (475) is the arithmetic half of the inner landscape
display — Apple has not published exact Split View widths for Duo. Treat all of them as fixtures,
not as a spec.

## License

MIT
