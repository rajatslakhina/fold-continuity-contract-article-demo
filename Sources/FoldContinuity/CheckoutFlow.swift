import Foundation

/// A checkout screen's state, the way a real app carries it: some of it is
/// the user's work (cart, draft promo code, focused field, sheet, scroll),
/// some of it is layout that legitimately depends on posture.
public struct CheckoutState: Sendable, Hashable {
    public enum Field: String, Sendable, Hashable { case promoCode, giftMessage }
    public enum Sheet: String, Sendable, Hashable { case addressPicker, paymentPicker }
    public enum Layout: String, Sendable, Hashable { case singleColumn, twoColumn }

    public var cartItemIDs: [String]
    public var selectedShippingOption: String
    public var draftPromoCode: String
    public var focusedField: Field?
    public var presentedSheet: Sheet?
    public var navigationPath: [String]
    public var scrollOffset: Double
    public var layout: Layout

    public init(
        cartItemIDs: [String],
        selectedShippingOption: String,
        draftPromoCode: String,
        focusedField: Field?,
        presentedSheet: Sheet?,
        navigationPath: [String],
        scrollOffset: Double,
        layout: Layout
    ) {
        self.cartItemIDs = cartItemIDs
        self.selectedShippingOption = selectedShippingOption
        self.draftPromoCode = draftPromoCode
        self.focusedField = focusedField
        self.presentedSheet = presentedSheet
        self.navigationPath = navigationPath
        self.scrollOffset = scrollOffset
        self.layout = layout
    }

    /// A shopper three taps from paying: promo half-typed, address sheet up.
    public static let midCheckout = CheckoutState(
        cartItemIDs: ["sku-4471", "sku-0912"],
        selectedShippingOption: "express",
        draftPromoCode: "FOLD2",
        focusedField: .promoCode,
        presentedSheet: .addressPicker,
        navigationPath: ["cart", "checkout", "address"],
        scrollOffset: 412,
        layout: .singleColumn
    )

    /// The layout a shape should get. This is the only thing posture is
    /// allowed to decide.
    public static func layout(for shape: DisplayShape) -> Layout {
        shape.horizontal == .regular ? .twoColumn : .singleColumn
    }
}

/// The contract for checkout. Every field is named once; the fuzzer and the
/// code review both read this list.
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

/// Two ways to react to a posture change. Both produce the right layout.
/// Only one keeps the shopper's work.
public enum CheckoutAdapters {
    /// The shape most apps have today: the root view switches container when
    /// the horizontal size class flips (`NavigationStack` ↔
    /// `NavigationSplitView`), and the subtree is rebuilt. Rebuilt views come
    /// back with fresh `@State`: the draft is empty, focus is nil, the sheet
    /// is gone, the path is reset to the root, and the scroll position is 0.
    public static let naive: FuzzableFlow<CheckoutState> = FuzzableFlow(
        contract: CheckoutContract.contract,
        initial: .midCheckout
    ) { state, transition in
        var next = state
        next.layout = CheckoutState.layout(for: transition.to.shape)
        guard transition.changesHorizontalSizeClass else { return next }
        // Subtree identity changed; SwiftUI (or a UIKit re-parent) discards it.
        next.draftPromoCode = ""
        next.focusedField = nil
        next.presentedSheet = nil
        next.navigationPath = Array(state.navigationPath.prefix(1))
        next.scrollOffset = 0
        return next
    }

    /// The contracted shape: posture is an input, state lives above the
    /// container that changes, and the adapt step touches derived fields only.
    public static let contracted: FuzzableFlow<CheckoutState> = FuzzableFlow(
        contract: CheckoutContract.contract,
        initial: .midCheckout
    ) { state, transition in
        var next = state
        next.layout = CheckoutState.layout(for: transition.to.shape)
        return next
    }
}
