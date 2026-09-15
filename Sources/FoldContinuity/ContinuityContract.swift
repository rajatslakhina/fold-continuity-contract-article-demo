import Foundation

/// What a single piece of flow state is allowed to do across a posture change.
public enum ContinuityRule: String, Sendable, Codable, Hashable {
    /// The value must be identical before and after the transition.
    case mustSurvive
    /// The value is a function of posture and is expected to change; the
    /// contract records it but never flags it.
    case derivedFromPosture
}

/// One named field of a flow's state, with an equality probe. Key paths are
/// erased into a closure so the contract can hold heterogeneous fields.
public struct ContinuityField<State>: Sendable {
    public let name: String
    public let rule: ContinuityRule
    private let isEqual: @Sendable (State, State) -> Bool
    private let render: @Sendable (State) -> String

    public init<Value: Equatable>(
        _ name: String,
        _ keyPath: KeyPath<State, Value> & Sendable,
        rule: ContinuityRule = .mustSurvive
    ) {
        self.name = name
        self.rule = rule
        self.isEqual = { a, b in a[keyPath: keyPath] == b[keyPath: keyPath] }
        self.render = { state in String(describing: state[keyPath: keyPath]) }
    }

    func survived(from before: State, to after: State) -> Bool {
        isEqual(before, after)
    }

    func describe(_ state: State) -> String { render(state) }
}

/// A per-flow declaration of what must survive a fold. This is the artefact
/// a lead reviews: it says, in one place, which user work a posture change is
/// forbidden from destroying.
public struct ContinuityContract<State>: Sendable {
    public let flowName: String
    public let fields: [ContinuityField<State>]

    public init(flowName: String, fields: [ContinuityField<State>]) {
        self.flowName = flowName
        self.fields = fields
    }

    /// Names of every field that must survive.
    public var protectedFieldNames: [String] {
        fields.filter { $0.rule == .mustSurvive }.map(\.name)
    }

    /// Checks one transition. Returns every protected field whose value changed.
    public func violations(
        before: State,
        after: State,
        transition: PostureTransition,
        step: Int
    ) -> [ContinuityViolation] {
        fields.compactMap { field in
            guard field.rule == .mustSurvive, !field.survived(from: before, to: after) else {
                return nil
            }
            return ContinuityViolation(
                flowName: flowName,
                fieldName: field.name,
                step: step,
                transition: transition,
                before: field.describe(before),
                after: field.describe(after)
            )
        }
    }
}

/// A protected field that did not survive a specific transition.
public struct ContinuityViolation: Sendable, Hashable, CustomStringConvertible {
    public let flowName: String
    public let fieldName: String
    public let step: Int
    public let transition: PostureTransition
    public let before: String
    public let after: String

    public var description: String {
        "[\(flowName)] step \(step) \(transition): \(fieldName) \(before) → \(after)"
    }
}
