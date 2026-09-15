import XCTest
@testable import FoldContinuity

final class PostureTests: XCTestCase {
    func testInnerDisplayIsRegularBothWays() {
        XCTAssertEqual(Posture.openPortrait.shape.horizontal, .regular)
        XCTAssertEqual(Posture.openPortrait.shape.vertical, .regular)
        XCTAssertEqual(Posture.openLandscape.shape.width, 951)
        XCTAssertEqual(Posture.openPortrait.shape.width, 669)
    }

    func testOuterDisplayBehavesLikeAPhone() {
        XCTAssertEqual(Posture.closedPortrait.shape.horizontal, .compact)
        XCTAssertEqual(Posture.closedPortrait.shape.vertical, .regular)
        XCTAssertEqual(Posture.closedLandscape.shape.vertical, .compact)
    }

    func testBothDisplaysShareAnAspectRatioWithinTwoPercent() {
        let inner = Posture.openPortrait.shape.aspectRatio
        let outer = Posture.closedPortrait.shape.aspectRatio
        XCTAssertEqual(inner, 1.42, accuracy: 0.01)
        XCTAssertEqual(outer, 1.45, accuracy: 0.01)
        XCTAssertLessThan(abs(inner - outer) / inner, 0.03)
    }

    func testOnlySomeTransitionsChangeSizeClass() {
        XCTAssertTrue(PostureTransition(from: .closedPortrait, to: .openLandscape).changesSizeClass)
        XCTAssertFalse(PostureTransition(from: .openPortrait, to: .openLandscape).changesSizeClass)
        XCTAssertFalse(PostureTransition(from: .tabletop, to: .tabletop).changesSizeClass)
        XCTAssertTrue(PostureTransition(from: .openLandscape, to: .splitView).changesSizeClass)
    }

    func testRotatingTheOuterDisplayDoesNotFlipHorizontalClass() {
        let rotate = PostureTransition(from: .closedPortrait, to: .closedLandscape)
        XCTAssertTrue(rotate.changesSizeClass)
        XCTAssertFalse(rotate.changesHorizontalSizeClass)
        XCTAssertTrue(PostureTransition(from: .closedPortrait, to: .openPortrait).changesHorizontalSizeClass)
    }
}

final class ContinuityContractTests: XCTestCase {
    private let transition = PostureTransition(from: .closedPortrait, to: .openLandscape)

    func testIdenticalStatesProduceNoViolations() {
        let state = CheckoutState.midCheckout
        let violations = CheckoutContract.contract.violations(
            before: state, after: state, transition: transition, step: 0
        )
        XCTAssertTrue(violations.isEmpty)
    }

    func testDerivedFieldsAreNeverFlagged() {
        var after = CheckoutState.midCheckout
        after.layout = .twoColumn
        let violations = CheckoutContract.contract.violations(
            before: .midCheckout, after: after, transition: transition, step: 3
        )
        XCTAssertTrue(violations.isEmpty)
        XCTAssertFalse(CheckoutContract.contract.protectedFieldNames.contains("layout"))
        XCTAssertEqual(CheckoutContract.contract.protectedFieldNames.count, 7)
    }

    func testEveryLostFieldIsNamed() {
        var after = CheckoutState.midCheckout
        after.draftPromoCode = ""
        after.presentedSheet = nil
        let violations = CheckoutContract.contract.violations(
            before: .midCheckout, after: after, transition: transition, step: 5
        )
        XCTAssertEqual(Set(violations.map(\.fieldName)), ["draftPromoCode", "presentedSheet"])
        XCTAssertEqual(violations.first?.step, 5)
        XCTAssertEqual(violations.first?.transition, transition)
    }

    func testEmptyContractAlwaysPasses() {
        let empty = ContinuityContract<CheckoutState>(flowName: "Empty", fields: [])
        var after = CheckoutState.midCheckout
        after.cartItemIDs = []
        XCTAssertTrue(empty.violations(before: .midCheckout, after: after, transition: transition, step: 0).isEmpty)
    }
}

final class PostureFuzzerTests: XCTestCase {
    private let fuzzer = PostureFuzzer()

    func testSequencesAreDeterministicPerSeed() {
        let a = fuzzer.sequence(seed: 42, steps: 20, from: .closedPortrait)
        let b = fuzzer.sequence(seed: 42, steps: 20, from: .closedPortrait)
        let c = fuzzer.sequence(seed: 43, steps: 20, from: .closedPortrait)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertEqual(a.first?.from, .closedPortrait)
    }

    func testSequencesChain() {
        let seq = fuzzer.sequence(seed: 7, steps: 50, from: .openLandscape)
        for (previous, next) in zip(seq, seq.dropFirst()) {
            XCTAssertEqual(previous.to, next.from)
        }
    }

    func testZeroStepsIsAnEmptyRunThatPasses() {
        XCTAssertTrue(fuzzer.sequence(seed: 1, steps: 0, from: .tabletop).isEmpty)
        let report = fuzzer.run(CheckoutAdapters.naive, seed: 1, steps: 0)
        XCTAssertTrue(report.passed)
        XCTAssertEqual(report.steps, 0)
    }

    func testRestrictedPostureSetOnlyEmitsThosePostures() {
        let openOnly = PostureFuzzer(postures: [.openPortrait, .openLandscape])
        let seq = openOnly.sequence(seed: 99, steps: 40, from: .openPortrait)
        XCTAssertTrue(seq.allSatisfy { [.openPortrait, .openLandscape].contains($0.to) })
    }

    func testEmptyPostureListFallsBackToAllCases() {
        XCTAssertEqual(PostureFuzzer(postures: []).postures, Posture.allCases)
    }

    func testNaiveCheckoutLosesWorkOnFirstSizeClassChange() {
        let report = fuzzer.run(CheckoutAdapters.naive, seed: 2026, steps: 32)
        XCTAssertFalse(report.passed)
        let firstFlip = report.sequence.firstIndex(where: \.changesHorizontalSizeClass)
        XCTAssertEqual(report.firstFailingStep, firstFlip)
        // The first flip loses all five rebuilt fields at once.
        let atFirst = report.violations.filter { $0.step == report.firstFailingStep }
        XCTAssertEqual(
            Set(atFirst.map(\.fieldName)),
            ["draftPromoCode", "focusedField", "presentedSheet", "navigationPath", "scrollOffset"]
        )
        // Cart and shipping live in a store above the view; they survive.
        XCTAssertNil(report.violationsByField["cartItemIDs"])
        XCTAssertNil(report.violationsByField["selectedShippingOption"])
    }

    func testContractedCheckoutSurvivesEverySeed() {
        let seeds: [UInt64] = (1...50).map { UInt64($0) }
        let reports = fuzzer.campaign(CheckoutAdapters.contracted, seeds: seeds, steps: 64)
        XCTAssertEqual(reports.count, 50)
        XCTAssertTrue(reports.allSatisfy(\.passed))
        // And it still produced the right layout at the end of every run.
        XCTAssertTrue(reports.allSatisfy { $0.horizontalFlips > 0 })
    }

    func testNaiveCheckoutNeverSurvivesAFullCampaign() {
        let seeds: [UInt64] = (1...50).map { UInt64($0) }
        let reports = fuzzer.campaign(CheckoutAdapters.naive, seeds: seeds, steps: 64)
        XCTAssertTrue(reports.allSatisfy { !$0.passed })
    }

    func testNaiveCheckoutPassesWhenPosturesNeverFlipSizeClass() {
        // The bug is invisible on a device that never changes size class —
        // which is every iPhone shipped before this one.
        let phoneOnly = PostureFuzzer(postures: [.closedPortrait])
        let report = phoneOnly.run(CheckoutAdapters.naive, seed: 5, steps: 32, from: .closedPortrait)
        XCTAssertTrue(report.passed)
    }
}
