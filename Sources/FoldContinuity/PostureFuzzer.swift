import Foundation

/// A flow the fuzzer can drive: some state, and the function the app runs
/// when the scene's posture changes. The fuzzer never looks inside — it only
/// compares what came out against the contract.
public struct FuzzableFlow<State>: Sendable {
    public let contract: ContinuityContract<State>
    public let initial: State
    public let adapt: @Sendable (State, PostureTransition) -> State

    public init(
        contract: ContinuityContract<State>,
        initial: State,
        adapt: @escaping @Sendable (State, PostureTransition) -> State
    ) {
        self.contract = contract
        self.initial = initial
        self.adapt = adapt
    }
}

/// SplitMix64 — small, deterministic, and good enough to make a fuzz run
/// reproducible from a single seed you can paste into a bug report.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// The result of one fuzz run over one flow.
public struct FuzzReport: Sendable, Hashable {
    public let flowName: String
    public let seed: UInt64
    public let steps: Int
    public let sequence: [PostureTransition]
    public let violations: [ContinuityViolation]

    public var passed: Bool { violations.isEmpty }

    /// Steps whose transition changed at least one size class — the ones a
    /// `horizontalSizeClass` branch would react to.
    public var sizeClassChangingSteps: Int {
        sequence.filter(\.changesSizeClass).count
    }

    /// Steps whose transition flipped the horizontal size class specifically.
    public var horizontalFlips: Int {
        sequence.filter(\.changesHorizontalSizeClass).count
    }

    /// The first step at which any protected field was lost, if any.
    public var firstFailingStep: Int? { violations.map(\.step).min() }

    /// Violations grouped by field, so a report reads "draft lost 4 times"
    /// rather than 4 near-identical lines.
    public var violationsByField: [String: Int] {
        var counts: [String: Int] = [:]
        for violation in violations { counts[violation.fieldName, default: 0] += 1 }
        return counts
    }
}

/// Generates posture sequences and replays a flow through them. Aspect ratio
/// and size class become a *test dimension* rather than a device list: the
/// same flow is exercised across every shape the hardware can hand it.
public struct PostureFuzzer: Sendable {
    public let postures: [Posture]

    public init(postures: [Posture] = Posture.allCases) {
        self.postures = postures.isEmpty ? Posture.allCases : postures
    }

    /// Builds a deterministic sequence of `steps` transitions starting from
    /// `start`. Consecutive identical postures are allowed on purpose — a
    /// no-op resize is a real event and a flow must survive it too.
    public func sequence(seed: UInt64, steps: Int, from start: Posture) -> [PostureTransition] {
        guard steps > 0 else { return [] }
        var rng = SeededGenerator(seed: seed)
        var current = start
        var result: [PostureTransition] = []
        result.reserveCapacity(steps)
        for _ in 0..<steps {
            let index = Int(rng.next() % UInt64(postures.count))
            let next = postures[index]
            result.append(PostureTransition(from: current, to: next))
            current = next
        }
        return result
    }

    /// Runs one flow through one seeded sequence and reports every protected
    /// field that failed to survive.
    public func run<State>(
        _ flow: FuzzableFlow<State>,
        seed: UInt64,
        steps: Int = 32,
        from start: Posture = .closedPortrait
    ) -> FuzzReport {
        let sequence = self.sequence(seed: seed, steps: steps, from: start)
        var state = flow.initial
        var violations: [ContinuityViolation] = []
        for (step, transition) in sequence.enumerated() {
            let next = flow.adapt(state, transition)
            violations.append(contentsOf: flow.contract.violations(
                before: state, after: next, transition: transition, step: step
            ))
            state = next
        }
        return FuzzReport(
            flowName: flow.contract.flowName,
            seed: seed,
            steps: sequence.count,
            sequence: sequence,
            violations: violations
        )
    }

    /// Runs `seeds` independent sequences and returns each report. This is the
    /// CI shape: a flow passes only if every seed passes.
    public func campaign<State>(
        _ flow: FuzzableFlow<State>,
        seeds: [UInt64],
        steps: Int = 32,
        from start: Posture = .closedPortrait
    ) -> [FuzzReport] {
        seeds.map { run(flow, seed: $0, steps: steps, from: start) }
    }
}
