#if canImport(SwiftUI)
import SwiftUI

/// Interactive demo: pick a seed, run both checkout adapters through the same
/// posture sequence, and read the contract's verdict. Every number on screen
/// comes from `PostureFuzzer`, not from a hard-coded table.
@available(iOS 17, macOS 14, *)
public struct ContinuityDemoView: View {
    @State private var seed: UInt64 = 2026
    @State private var steps: Double = 24
    @State private var naiveReport: FuzzReport?
    @State private var contractedReport: FuzzReport?

    public init() {}

    private let fuzzer = PostureFuzzer()

    public var body: some View {
        NavigationStack {
            List {
                Section("Posture sequence") {
                    Stepper("Seed \(seed)", value: Binding(
                        get: { Int(seed) }, set: { seed = UInt64(max(0, $0)) }
                    ))
                    HStack {
                        Text("Steps \(Int(steps))")
                        Slider(value: $steps, in: 4...64, step: 1)
                    }
                    Button("Run fuzzer", action: run)
                        .buttonStyle(.borderedProminent)
                }

                if let naiveReport, let contractedReport {
                    reportSection(title: "Naive adapter (rebuild on size-class flip)", report: naiveReport)
                    reportSection(title: "Contracted adapter (posture is an input)", report: contractedReport)
                    Section("Sequence") {
                        ForEach(Array(contractedReport.sequence.enumerated()), id: \.offset) { index, transition in
                            HStack {
                                Text("\(index)").monospacedDigit().foregroundStyle(.secondary)
                                Text(transition.description)
                                Spacer()
                                if transition.changesSizeClass {
                                    Image(systemName: "arrow.left.and.right.square")
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("Size class changes")
                                }
                            }
                            .font(.caption.monospaced())
                        }
                    }
                }

                Section("Contract: Checkout") {
                    ForEach(CheckoutContract.contract.fields, id: \.name) { field in
                        HStack {
                            Text(field.name).font(.caption.monospaced())
                            Spacer()
                            Text(field.rule == .mustSurvive ? "must survive" : "derived")
                                .font(.caption2)
                                .foregroundStyle(field.rule == .mustSurvive ? .primary : .secondary)
                        }
                    }
                }
            }
            .navigationTitle("Fold Continuity")
            .onAppear(perform: run)
        }
    }

    private func run() {
        naiveReport = fuzzer.run(CheckoutAdapters.naive, seed: seed, steps: Int(steps))
        contractedReport = fuzzer.run(CheckoutAdapters.contracted, seed: seed, steps: Int(steps))
    }

    @ViewBuilder
    private func reportSection(title: String, report: FuzzReport) -> some View {
        Section(title) {
            HStack {
                Image(systemName: report.passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(report.passed ? .green : .red)
                Text(report.passed ? "PASS" : "FAIL — \(report.violations.count) violations")
                    .bold()
                Spacer()
                Text("\(report.sizeClassChangingSteps) size-class flips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let first = report.firstFailingStep {
                Text("First loss at step \(first): \(report.sequence[first].description)")
                    .font(.caption)
            }
            ForEach(report.violationsByField.sorted(by: { $0.key < $1.key }), id: \.key) { name, count in
                HStack {
                    Text(name).font(.caption.monospaced())
                    Spacer()
                    Text("lost \(count)×").font(.caption).foregroundStyle(.red)
                }
            }
        }
    }
}
#endif
