import Foundation
import Testing
@testable import Parley

/// PARLEY-2: activity log, streak, heatmap, skill totals (spec S2).
@MainActor @Suite struct ActivityStoreTests {
    let cal = Calendar(identifier: .gregorian)
    func day(_ offset: Int, from d: Date = .now) -> Date { cal.date(byAdding: .day, value: offset, to: d)! }

    @Test func addsXPPerSkillAndDayAndPersists() {
        let url = TestData.file("activity.json")
        let s = ActivityStore(file: url)
        s.add(.grammar, xp: 10)
        s.add(.grammar, xp: 2)
        s.add(.listening, xp: 10)
        s.add(.reading, xp: 0)   // nothing to log
        s.add(.reading, xp: -5)  // never subtracts
        #expect(s.todayXP == 22)
        #expect(s.data.days[StudyStore.day(.now)] == ["grammar": 12, "listening": 10])
        #expect(ActivityStore(file: url).data == s.data) // AC2.1 survives a restart
    }

    @Test func goalIsClampedAndMetDaysAreKept() {
        let s = ActivityStore(file: TestData.file("activity.json"))
        s.goal = 5
        #expect(s.goal == 10)
        s.goal = 1_000
        #expect(s.goal == 200)
        s.goal = 20
        s.add(.vocabulary, xp: 20)
        #expect(s.data.met == [StudyStore.day(.now)] && s.streak == 1)
        s.goal = 100 // raising the goal later does not erase a day already earned
        #expect(s.streak == 1)
        s.goal = 10
        #expect(s.data.met.count == 1) // no duplicate entry
    }

    @Test(arguments: [
        ([0, -1, -2], 3),       // today, yesterday, day before
        ([-1, -2], 2),          // today still open → streak continues from yesterday
        ([0, -2, -3], 1),       // gap yesterday → only today counts
        ([-2, -3], 0),          // missed yesterday and today not yet → broken
        ([Int](), 0),
    ])
    func streak(offsets: [Int], expected: Int) {
        let today = Date()
        let met = Set(offsets.map { StudyStore.day(day($0, from: today)) })
        #expect(ActivityStore.streak(met: met, today: today, calendar: cal) == expected)
    }

    @Test func heatmapIsTwelveMondayFirstWeeksEndingThisWeek() {
        // Wednesday 2026-11-04 local noon
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        let days = [StudyStore.day(today): ["grammar": 30], "2026-11-02": ["listening": 5], "2020-01-01": ["grammar": 99]]
        let grid = ActivityStore.heatmap(days, weeks: 12, today: today, calendar: cal)
        #expect(grid.count == 12 && grid.allSatisfy { $0.count == 7 })
        #expect(grid[11][0].day == "2026-11-02")            // Monday of this week
        #expect(grid[11][0].xp == 5 && grid[11][2].xp == 30) // Wednesday = today
        #expect(!grid[11][2].future && grid[11][3].future && grid[11][6].future)
        #expect(grid[0][0].day == "2026-08-17")             // 11 weeks earlier
        #expect(grid.joined().allSatisfy { $0.day != "2020-01-01" })
    }

    @Test func totalsPerSkillWithOptionalWindow() {
        let days = ["2026-11-01": ["grammar": 10, "bogus": 50], "2026-11-07": ["grammar": 5, "speaking": 20]]
        #expect(ActivityStore.totals(days) == [.grammar: 15, .speaking: 20])
        #expect(ActivityStore.totals(days, since: "2026-11-02") == [.grammar: 5, .speaking: 20])
        #expect(ActivityStore.totals([:]).isEmpty)
    }

    @Test func unreadableFileIsMovedAsideNotOverwritten() throws {
        let url = TestData.file("activity.json")
        try Data("{ broken".utf8).write(to: url)
        let s = ActivityStore(file: url)
        #expect(s.data == ActivityData())
        #expect(TestData.asideFiles(of: url).count == 1)
    }

    @Test func loweringTheGoalBelowTodaysXPMeetsToday() {
        let s = ActivityStore(file: TestData.file("activity.json"))
        s.add(.grammar, xp: 30)               // goal 50: not met
        #expect(!s.metToday)
        s.goal = 30
        #expect(s.metToday && s.streak == 1)  // met at once, no extra XP needed
    }

    @Test func xpRules() {
        #expect(XP.answer(true) == 10 && XP.answer(false) == 2)
    }
}

/// benchmarks/plan.md W1: progress aggregation over 3 years of daily logs < 20 ms.
@Suite struct BenchProgress {
    @Test func threeYearsAggregateUnder20ms() {
        var days: [String: [String: Int]] = [:]
        var met = Set<String>()
        let now = Date()
        for i in 0..<1_095 {
            let d = StudyStore.day(now.addingTimeInterval(Double(-i) * 86_400))
            days[d] = Dictionary(uniqueKeysWithValues: Skill.allCases.map { ($0.rawValue, i % 60) })
            met.insert(d)
        }
        let clock = ContinuousClock()
        // best of 3: a busy machine (parallel builds, other tests) must not fail the guard by noise
        let elapsed = (0..<3).map { _ in
            clock.measure {
                _ = ActivityStore.streak(met: met, today: now)
                _ = ActivityStore.heatmap(days, weeks: 12, today: now)
                _ = ActivityStore.totals(days)
                _ = ActivityStore.totals(days, since: StudyStore.day(now.addingTimeInterval(-6 * 86_400)))
            }
        }.min()!
        print("BenchProgress: \(elapsed)")
        #expect(elapsed < .milliseconds(20))
    }
}

@MainActor @Suite struct SeedActivityTests {
    @Test func sampleShowsAStreakAndTodayInProgress() {
        let a = Seed.sampleActivity(now: .now)
        #expect(ActivityStore.total(a.days[StudyStore.day(.now)]) == 30)
        #expect(ActivityStore.streak(met: Set(a.met), today: .now) == 6)
    }
}
