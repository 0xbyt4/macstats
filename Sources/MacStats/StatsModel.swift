import Foundation
import Observation
import StatsKit

@MainActor
@Observable
final class StatsModel {
    static let interval: Duration = .seconds(2)

    /// The longest title `menuBarTitle` can return. The menu bar item uses its width.
    static let widestMenuBarTitle = "CPU 100%  GPU 100%  100°"

    private(set) var snapshot: Snapshot?
    /// Called on the main actor after each new snapshot.
    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored private let sampler = SystemSampler()
    @ObservationIgnored private var task: Task<Void, Never>?

    init() {
        task = Task { [weak self] in
            // The first sample only sets the baseline for CPU, disk and network rates.
            _ = self?.sampler.sample()
            try? await Task.sleep(for: .seconds(1))
            while !Task.isCancelled {
                guard let self else { return }
                self.snapshot = self.sampler.sample()
                self.onUpdate?()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    var menuBarTitle: String {
        let cpu = snapshot?.cpu.map { padded(Int(($0.total * 100).rounded())) + "%" } ?? "--"
        let gpu = snapshot?.gpu.map { padded(Int(($0.device * 100).rounded())) + "%" } ?? "--"
        var title = "CPU \(cpu)  GPU \(gpu)"
        if let temp = snapshot?.temperatures.cpuAverage {
            title += "  " + padded(Int(temp.rounded())) + "°"
        }
        return title
    }

    /// Pads a number to 3 characters with figure spaces, which are as wide as a digit.
    private func padded(_ value: Int) -> String {
        let text = String(value)
        return String(repeating: "\u{2007}", count: max(0, 3 - text.count)) + text
    }
}
