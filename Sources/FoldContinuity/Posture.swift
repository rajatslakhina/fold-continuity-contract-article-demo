import Foundation

/// A size class, mirroring `UIUserInterfaceSizeClass` without importing UIKit
/// so the core builds and tests on any platform.
public enum SizeClass: String, Sendable, Codable, Hashable {
    case compact, regular
}

/// The shape the system hands your scene. This is the *input* to layout —
/// never something a flow should branch on to decide what state to keep.
public struct DisplayShape: Sendable, Codable, Hashable {
    public var width: Double
    public var height: Double
    public var horizontal: SizeClass
    public var vertical: SizeClass

    public init(width: Double, height: Double, horizontal: SizeClass, vertical: SizeClass) {
        self.width = width
        self.height = height
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public var aspectRatio: Double {
        guard width > 0 else { return 0 }
        return max(width, height) / min(width, height)
    }
}

/// The physical posture of a foldable/resizable iPhone. Point sizes follow
/// App Store Connect's iPhone Duo screenshot specification at 3x
/// (inner 669×951, outer 466×678); size classes follow Apple's
/// "Prepare your app for iPhone Duo" Tech Talk (inner display is regular
/// in both dimensions, outer behaves like every other iPhone).
public enum Posture: Sendable, Codable, Hashable, CaseIterable {
    /// Closed — outer display, portrait.
    case closedPortrait
    /// Closed — outer display, landscape.
    case closedLandscape
    /// Fully open — inner display, portrait (669 wide).
    case openPortrait
    /// Fully open — inner display, landscape (951 wide) — the natural hold.
    case openLandscape
    /// Partially folded on a surface (tabletop). Same size classes as open;
    /// the fold reserves the middle of the display.
    case tabletop
    /// Open, but sharing the inner display with another app in Split View.
    case splitView

    public var shape: DisplayShape {
        switch self {
        case .closedPortrait:
            return DisplayShape(width: 466, height: 678, horizontal: .compact, vertical: .regular)
        case .closedLandscape:
            return DisplayShape(width: 678, height: 466, horizontal: .compact, vertical: .compact)
        case .openPortrait:
            return DisplayShape(width: 669, height: 951, horizontal: .regular, vertical: .regular)
        case .openLandscape, .tabletop:
            return DisplayShape(width: 951, height: 669, horizontal: .regular, vertical: .regular)
        case .splitView:
            // Half of the inner display in landscape. Apple has not published
            // exact Split View widths for Duo; 475 is the arithmetic half.
            return DisplayShape(width: 475, height: 669, horizontal: .compact, vertical: .regular)
        }
    }

    /// True when the fold reserves a region in the middle of the display.
    public var hasFoldRegion: Bool { self == .tabletop }
}

/// One posture change as the fuzzer will deliver it to a flow.
public struct PostureTransition: Sendable, Hashable, CustomStringConvertible {
    public var from: Posture
    public var to: Posture

    public init(from: Posture, to: Posture) {
        self.from = from
        self.to = to
    }

    /// The transitions that actually change something a layout can see.
    public var changesSizeClass: Bool {
        from.shape.horizontal != to.shape.horizontal || from.shape.vertical != to.shape.vertical
    }

    /// The flip a `horizontalSizeClass` branch reacts to — the one that swaps
    /// `NavigationStack` for `NavigationSplitView` in most codebases.
    public var changesHorizontalSizeClass: Bool {
        from.shape.horizontal != to.shape.horizontal
    }

    public var description: String { "\(from) → \(to)" }
}
