import Foundation

struct AppUsageScore: Codable, Equatable {
    static let day: TimeInterval = 86_400
    private(set) var totalCount = 0
    private(set) var recentWeight = 0.0
    private(set) var baselineWeight = 0.0
    private(set) var updatedAt: TimeInterval = 0

    mutating func record(at now: TimeInterval) {
        guard now.isFinite else { return }
        let weights = decayed(at: now)
        totalCount = min(totalCount, Int.max - 1) + 1
        recentWeight = weights.recent + 1
        baselineWeight = weights.baseline + 1
        updatedAt = max(updatedAt, now)
    }

    func rates(at now: TimeInterval) -> (recent: Double, baseline: Double, trend: Double) {
        let weights = decayed(at: now)
        // Multiplying by the decay rate puts both windows on the same uses-per-day scale.
        let recent = weights.recent * log(2)
        let baseline = weights.baseline * log(2) / 7
        return (recent, baseline, recent - baseline)
    }

    func rankingScore(at now: TimeInterval) -> Double {
        let rates = rates(at: now)
        let score = rates.recent + max(0, rates.trend)
        return score >= 0.01 ? score : 0
    }

    var isValid: Bool {
        totalCount >= 0 && recentWeight.isFinite && recentWeight >= 0
            && baselineWeight.isFinite && baselineWeight >= 0 && updatedAt.isFinite
    }

    private func decayed(at now: TimeInterval) -> (recent: Double, baseline: Double) {
        let days = now.isFinite ? max(0, now - updatedAt) / Self.day : 0
        return (recentWeight * pow(0.5, days), baselineWeight * pow(0.5, days / 7))
    }
}
