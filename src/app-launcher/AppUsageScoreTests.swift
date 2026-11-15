import XCTest

final class AppUsageScoreTests: XCTestCase {
    private let day = AppUsageScore.day

    func testRawCountDoesNotDecayButRecentWeightHalvesDaily() {
        var usage = AppUsageScore()
        usage.record(at: day)
        usage.record(at: day)
        XCTAssertEqual(usage.totalCount, 2)
        XCTAssertEqual(usage.rates(at: day * 2).recent, log(2), accuracy: 0.000001)
        XCTAssertEqual(usage.rates(at: day * 8).baseline, log(2) / 7, accuracy: 0.000001)
        XCTAssertEqual(usage.totalCount, 2)
    }

    func testNewCanaryHabitOvertakesTwoYearsOfChromeWithinADay() {
        var chrome = AppUsageScore()
        var canary = AppUsageScore()
        for hour in 0..<(730 * 24) where hour % 4 == 0 { chrome.record(at: Double(hour) * day / 24) }
        for hour in stride(from: 0, to: 24, by: 4) { canary.record(at: 730 * day + Double(hour) * day / 24) }
        let now = 731 * day
        XCTAssertEqual(chrome.totalCount, 4_380)
        XCTAssertEqual(canary.totalCount, 6)
        XCTAssertLessThan(chrome.rates(at: now).trend, 0)
        XCTAssertGreaterThan(canary.rates(at: now).trend, 0)
        XCTAssertGreaterThan(canary.rankingScore(at: now), chrome.rankingScore(at: now))
    }

    func testSteadyUseDoesNotAccumulateAnEverGrowingRankingAdvantage() {
        var established = AppUsageScore()
        var newer = AppUsageScore()
        for hour in 0..<(730 * 24) {
            let now = Double(hour) * day / 24
            established.record(at: now)
            if hour >= 670 * 24 { newer.record(at: now) }
        }
        XCTAssertGreaterThan(established.totalCount, newer.totalCount * 10)
        XCTAssertEqual(established.rankingScore(at: 730 * day), newer.rankingScore(at: 730 * day), accuracy: 0.1)
    }

    func testEncodingAndReloadPreserveCountsAndDecayAcrossDowntime() throws {
        var usage = AppUsageScore()
        usage.record(at: day)
        usage.record(at: day * 2)
        let data = try PropertyListEncoder().encode(["/Applications/Chrome.app": usage])
        let restored = try PropertyListDecoder().decode([String: AppUsageScore].self, from: data)
        let actual = try XCTUnwrap(restored["/Applications/Chrome.app"])
        XCTAssertEqual(actual, usage)
        XCTAssertEqual(actual.totalCount, 2)
        XCTAssertEqual(actual.rankingScore(at: day * 10), usage.rankingScore(at: day * 10))
        XCTAssertLessThan(actual.rankingScore(at: day * 10), actual.rankingScore(at: day * 2))
    }

    func testClockMovingBackDoesNotInflateExistingWeights() {
        var usage = AppUsageScore()
        usage.record(at: day * 2)
        XCTAssertEqual(usage.rankingScore(at: day), usage.rankingScore(at: day * 2))
        usage.record(at: day)
        XCTAssertEqual(usage.totalCount, 2)
        XCTAssertEqual(usage.recentWeight, 2)
        XCTAssertEqual(usage.updatedAt, day * 2)
    }

    func testLongAbsenceRemovesRankingInfluenceButKeepsRawHistory() {
        var usage = AppUsageScore()
        usage.record(at: day)
        XCTAssertEqual(usage.rankingScore(at: day * 10_000), 0)
        XCTAssertEqual(usage.totalCount, 1)
        XCTAssertTrue(usage.isValid)
    }

    func testNegligibleFrequencyYieldsToRecency() {
        var usage = AppUsageScore()
        usage.record(at: day)
        XCTAssertGreaterThan(usage.rates(at: day * 9).recent, 0)
        XCTAssertEqual(usage.rankingScore(at: day * 9), 0)
        XCTAssertEqual(usage.totalCount, 1)
    }
}
