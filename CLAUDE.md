# Working in this repo with a coding agent

This package exists to make one thing checkable: whether a flow's state survives a posture
change on a foldable iPhone. When you are asked to verify fold behaviour, follow these rules.

## The fuzzer is the oracle, the simulator is the reproduction

- Run `swift test` first. `PostureFuzzerTests` is the source of truth for whether a flow keeps
  its contract. A green screenshot is not evidence; a draft field can be emptied without any
  pixel changing.
- When a fuzz run fails, the report gives you a seed, a step and a transition
  (for example seed `2026`, step 2, `splitView → openPortrait`). Reproduce *that* transition
  in Device Hub's resize mode (669×951, 951×669, 466×678) or the iPhone Duo simulator,
  then read the state, not the screen.
- Report which **named field** diverged (`draftPromoCode`, `presentedSheet`, …). "It looks
  fine" is not an answer this repo accepts.

## The contract is the spec

- `CheckoutContract.contract` lists every field that must survive and the one that is
  derived from posture. If you add state to `CheckoutState`, add it to the contract in the
  same change and say which rule it gets.
- Never make the fuzzer pass by moving a field from `.mustSurvive` to `.derivedFromPosture`.
  That is changing the requirement, not fixing the bug. Ask first.

## Boundaries

- `Sources/FoldContinuity` must build on Linux (`swift build`), so keep SwiftUI behind
  `#if canImport(SwiftUI)`.
- Do not add an `.executableTarget` to `Package.swift`; the runnable app is `Demo.xcodeproj`.
- Commit summaries under 50 characters.
