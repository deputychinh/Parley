import Foundation
import Observation
import SwiftUI

// MARK: - Activity log (XP per skill per day)

/// What a learner practised; XP is logged per skill so the progress screen can show the balance.
enum Skill: String, Codable, CaseIterable, Identifiable {
    case vocabulary, grammar, listening, speaking, writing, reading
    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocabulary: "Từ vựng"
        case .grammar: "Ngữ pháp"
        case .listening: "Nghe"
        case .speaking: "Nói"
        case .writing: "Viết"
        case .reading: "Đọc"
        }
    }
    var symbol: String {
        switch self {
        case .vocabulary: "character.book.closed"
        case .grammar: "text.book.closed"
        case .listening: "ear"
        case .speaking: "waveform.and.mic"
        case .writing: "pencil.line"
        case .reading: "book"
        }
    }
    var color: Color {
        switch self {
        case .vocabulary: .parley
        case .grammar: .blue
        case .listening: .teal
        case .speaking: .orange
        case .writing: .pink
        case .reading: .green
        }
    }
}

/// XP rules (design.md): effort counts, correct answers count more.
enum XP {
    static let correct = 10
    static let attempt = 2
    static let newWord = 5
    static let turn = 15 // one conversation turn
    static func answer(_ ok: Bool) -> Int { ok ? correct : attempt }
}

/// Stored in `activity.json`: `{ "days": { "2026-11-08": { "grammar": 20 } }, "goal": 50, "met": ["2026-11-08"] }`.
struct ActivityData: Codable, Equatable {
    var days: [String: [String: Int]] = [:]   // yyyy-MM-dd (local) → skill rawValue → XP
    var goal = 50
    var met: [String] = []                    // days the goal was reached (kept even if the goal changes later)
}

@Observable @MainActor
final class ActivityStore {
    static let goalRange = 10...200
    private(set) var data = ActivityData()
    @ObservationIgnored private let url: URL

    init(file: URL = Model.dataDir.appending(path: "activity.json")) {
        url = file
        guard let raw = try? Data(contentsOf: url) else { return }
        do { data = try JSONDecoder().decode(ActivityData.self, from: raw) } catch {
            // Never overwrite a file we couldn't read.
            try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("unreadable.json"))
        }
    }

    var goal: Int {
        get { data.goal }
        set {
            data.goal = min(max(newValue, Self.goalRange.lowerBound), Self.goalRange.upperBound)
            markMet(StudyStore.day(.now))
            save()
        }
    }

    func add(_ skill: Skill, xp: Int, now: Date = .now) {
        guard xp > 0 else { return }
        let day = StudyStore.day(now)
        data.days[day, default: [:]][skill.rawValue, default: 0] += xp
        markMet(day)
        save()
    }

    func xp(on day: String) -> Int { Self.total(data.days[day]) }
    var todayXP: Int { xp(on: StudyStore.day(.now)) }
    var streak: Int { Self.streak(met: Set(data.met), today: .now) }

    private func markMet(_ day: String) {
        if xp(on: day) >= data.goal, !data.met.contains(day) { data.met.append(day) }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(data).write(to: url, options: .atomic)
    }

    // MARK: Pure aggregation (tested, benchmarked)

    nonisolated static func total(_ day: [String: Int]?) -> Int { day?.values.reduce(0, +) ?? 0 }

    /// Consecutive goal days ending today, or ending yesterday while today is still open.
    nonisolated static func streak(met: Set<String>, today: Date, calendar: Calendar = .current) -> Int {
        var date = today
        if !met.contains(StudyStore.day(date)) { date = calendar.date(byAdding: .day, value: -1, to: date)! }
        var n = 0
        while met.contains(StudyStore.day(date)) {
            n += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return n
    }

    struct Cell: Hashable { let day: String; let date: Date; let xp: Int; let future: Bool }

    /// `weeks` columns × 7 rows (Monday first); the last column holds today; days after today are marked `future`.
    nonisolated static func heatmap(_ days: [String: [String: Int]], weeks: Int, today: Date, calendar: Calendar = .current) -> [[Cell]] {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: today)!.start
        let first = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: start)!
        let todayStart = cal.startOfDay(for: today)
        return (0..<weeks).map { w in
            (0..<7).map { d in
                let date = cal.date(byAdding: .day, value: w * 7 + d, to: first)!
                let key = StudyStore.day(date)
                return Cell(day: key, date: date, xp: total(days[key]), future: date > todayStart)
            }
        }
    }

    /// XP per skill over the given days (all days when `since` is nil).
    nonisolated static func totals(_ days: [String: [String: Int]], since: String? = nil) -> [Skill: Int] {
        var out: [Skill: Int] = [:]
        for (day, skills) in days where since.map({ day >= $0 }) ?? true {
            for (k, v) in skills { if let s = Skill(rawValue: k) { out[s, default: 0] += v } }
        }
        return out
    }
}

// MARK: - "Tiến độ" screen

struct ProgressScreen: View {
    @Environment(ActivityStore.self) private var activity
    let vocab: VocabStore
    let study: StudyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if activity.data.days.isEmpty {
                    Card {
                        ContentUnavailableView {
                            Label("Chưa có buổi học nào", systemImage: "chart.bar.xaxis")
                        } description: {
                            Text("Làm bài ở Học tập, Ngữ pháp, Luyện nghe… — mỗi câu trả lời được tính điểm kinh nghiệm (XP) và hiện ở đây.")
                        }
                    }
                } else {
                    heatmapCard
                    skillsCard
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Tiến độ")
    }

    private var header: some View {
        let tiles = Group {
            StatTile(value: activity.streak, title: "ngày liên tiếp đạt mục tiêu", symbol: "flame.fill", color: .orange)
            StatTile(value: study.knownCount(vocab), title: "từ đã biết", symbol: "character.book.closed", color: .parley)
        }
        // Side by side when there is room; stacked in a narrow window.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                TodayRing(xp: activity.todayXP, goal: activity.goal).frame(minWidth: 380)
                VStack(spacing: 14) { tiles }.frame(minWidth: 260)
            }
            VStack(spacing: 14) {
                TodayRing(xp: activity.todayXP, goal: activity.goal)
                HStack(spacing: 14) { tiles }
            }
        }
    }

    private var heatmapCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("12 tuần gần đây").font(.headline)
                    Spacer()
                    HeatLegend(goal: activity.goal)
                }
                Heatmap(cells: ActivityStore.heatmap(activity.data.days, weeks: 12, today: .now), goal: activity.goal)
            }
        }
    }

    private var skillsCard: some View {
        let week = ActivityStore.totals(activity.data.days, since: StudyStore.day(.now.addingTimeInterval(-6 * 86_400)))
        let all = ActivityStore.totals(activity.data.days)
        let top = max(week.values.max() ?? 0, 1)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Kỹ năng — 7 ngày qua").font(.headline)
                    Spacer()
                    Text("Tổng: \(all.values.reduce(0, +)) XP").foregroundStyle(.secondary).monospacedDigit()
                }
                ForEach(Skill.allCases) { s in
                    SkillBar(skill: s, xp: week[s] ?? 0, total: all[s] ?? 0, fraction: Double(week[s] ?? 0) / Double(top))
                }
            }
        }
    }
}

struct TodayRing: View {
    @Environment(ActivityStore.self) private var activity
    let xp: Int
    let goal: Int

    var body: some View {
        let f = min(Double(xp) / Double(max(goal, 1)), 1)
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.parley.opacity(0.15), lineWidth: 12)
                Circle().trim(from: 0, to: f)
                    .stroke(f >= 1 ? Color.green.gradient : Color.parley.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: f)
                Image(systemName: f >= 1 ? "checkmark" : "bolt.fill")
                    .font(.title2.weight(.bold)).foregroundStyle(f >= 1 ? Color.green : Color.parley)
            }
            .frame(width: 92, height: 92)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Hôm nay").font(.callout).foregroundStyle(.secondary)
                Text("\(xp)/\(goal) XP").font(.title.weight(.bold)).monospacedDigit().contentTransition(.numericText())
                Text(f >= 1 ? "Đã đạt mục tiêu 🎉" : "Còn \(goal - xp) XP nữa").font(.callout).foregroundStyle(.secondary)
                Stepper("Mục tiêu: \(goal) XP/ngày", value: Binding(get: { activity.goal }, set: { activity.goal = $0 }),
                        in: ActivityStore.goalRange, step: 10)
                    .font(.callout)
                    .help("Đổi mục tiêu XP mỗi ngày (10–200)")
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct Heatmap: View {
    let cells: [[ActivityStore.Cell]]
    let goal: Int
    private let labels = ["T2", "", "T4", "", "T6", "", "CN"]

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 4) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i]).font(.caption2).foregroundStyle(.secondary).frame(width: 22, height: 18, alignment: .leading)
                }
            }
            .accessibilityHidden(true)
            ForEach(cells.indices, id: \.self) { w in
                VStack(spacing: 4) {
                    ForEach(cells[w], id: \.self) { c in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(c.future ? Color.clear : Heatmap.color(xp: c.xp, goal: goal))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.primary.opacity(c.future ? 0 : 0.06)))
                            .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)
                            .help(c.future ? "" : "\(c.date.formatted(date: .abbreviated, time: .omitted)): \(c.xp) XP")
                            .accessibilityHidden(c.future)
                            .accessibilityLabel("\(c.date.formatted(date: .abbreviated, time: .omitted)), \(c.xp) XP")
                    }
                }
            }
        }
    }

    static func color(xp: Int, goal: Int) -> Color {
        guard xp > 0 else { return Color.primary.opacity(0.06) }
        let f = Double(xp) / Double(max(goal, 1))
        return Color.parley.opacity(f >= 1 ? 1 : f >= 0.5 ? 0.6 : 0.3)
    }
}

struct HeatLegend: View {
    let goal: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("Ít").font(.caption).foregroundStyle(.secondary)
            ForEach([0, max(goal / 3, 1), goal * 2 / 3, goal], id: \.self) { xp in
                RoundedRectangle(cornerRadius: 3).fill(Heatmap.color(xp: xp, goal: goal)).frame(width: 12, height: 12)
            }
            Text("Đạt mục tiêu").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

struct SkillBar: View {
    let skill: Skill
    let xp: Int
    let total: Int
    let fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            Label(skill.title, systemImage: skill.symbol).foregroundStyle(skill.color).frame(width: 120, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(skill.color.gradient).frame(width: max(fraction * g.size.width, xp > 0 ? 6 : 0))
                }
            }
            .frame(height: 10)
            Text("\(xp) XP").monospacedDigit().frame(width: 64, alignment: .trailing)
            Text("tổng \(total)").font(.callout).foregroundStyle(.secondary).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(skill.title): \(xp) XP trong 7 ngày, tổng \(total)")
    }
}

/// Sidebar icon: today's progress as a small ring.
struct MiniRing: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2.5)
            Circle().trim(from: 0, to: min(fraction, 1))
                .stroke(fraction >= 1 ? Color.green : Color.parley, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}
