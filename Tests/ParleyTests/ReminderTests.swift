import Foundation
import Testing
@testable import Parley

/// PARLEY-8: when reminders fire (spec S8). Delivery itself is macOS's job (checked by hand).
@Suite struct ReminderTests {
    let cal = Calendar(identifier: .gregorian)
    func at(_ h: Int, _ m: Int, day: Int = 8) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))! }

    @Test func todayWhenBeforeTheTimeAndGoalOpen() {
        let d = Reminder.fireDates(now: at(9, 0), minutes: 20 * 60, metToday: false, days: 3, calendar: cal)
        #expect(d == [at(20, 0), at(20, 0, day: 9), at(20, 0, day: 10)])
    }

    @Test func skipsTodayWhenGoalMetOrTimePassed() {
        let met = Reminder.fireDates(now: at(9, 0), minutes: 20 * 60, metToday: true, days: 2, calendar: cal)
        #expect(met == [at(20, 0, day: 9), at(20, 0, day: 10)])
        let late = Reminder.fireDates(now: at(20, 0), minutes: 20 * 60, metToday: false, days: 2, calendar: cal) // boundary: exactly now
        #expect(late == [at(20, 0, day: 9), at(20, 0, day: 10)])
    }

    @Test func minutesAreClamped() {
        #expect(Reminder.fireDates(now: at(0, 0), minutes: -5, metToday: false, days: 1, calendar: cal) == [at(0, 0, day: 9)])
        #expect(Reminder.fireDates(now: at(0, 0), minutes: 9_999, metToday: false, days: 1, calendar: cal) == [at(23, 59)])
        #expect(Reminder.fireDates(now: at(0, 0), minutes: 600, metToday: false, calendar: cal).count == Reminder.days)
    }

    @Test func bodyMentionsWhatIsLeft() {
        #expect(Reminder.body(remaining: 20).contains("20 XP"))
        #expect(!Reminder.body(remaining: 0).contains("XP nữa") && !Reminder.body(remaining: nil).isEmpty)
    }
}

@MainActor @Suite struct GoalMetCallbackTests {
    @Test func firesOnceWhenTodayReachesTheGoal() {
        let a = ActivityStore(file: TestData.file("activity.json"))
        a.goal = 20
        var calls = 0
        a.onGoalMet = { calls += 1 }
        a.add(.grammar, xp: 10)
        #expect(calls == 0)
        a.add(.grammar, xp: 10)
        a.add(.grammar, xp: 10)
        #expect(calls == 1)
    }
}
