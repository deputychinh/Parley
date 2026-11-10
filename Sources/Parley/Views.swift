import AppKit
import AVKit
import SwiftUI
import Translation

// MARK: - Theme

extension Color {
    static let parley = Color(red: 0.48, green: 0.32, blue: 0.96) // matches the app icon
}

extension Source {
    var color: Color { self == .mic ? .orange : .parley }
    var nsColor: NSColor { NSColor(color) }
}

enum Route: Hashable {
    static func showsInterpreter(_ r: Route, running: Bool) -> Bool {
        if running { return true }
        if case .session = r { return true }
        return r == .live
    }
 case live, translate, progress, daily, topics, grammar, vocabulary, practice, listening, conversation, writing, reading, pronunciation, session(URL) }

/// Soft tinted canvas behind the cards (content stays opaque; glass is reserved for toolbar controls per HIG).
struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [Color.parley.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Window

struct ContentView: View {
    @Bindable var model: Model
    let vocab: VocabStore
    let study: StudyStore
    let writing: WritingStore
    let reading: ReadingStore
    @State private var route: Route? = .live
    @State private var translatePad = TranslatePad() // kept while switching screens
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var compact = false // toolbar too narrow for full language names → codes
    @State private var fold = false    // toolbar very narrow → secondary controls go into one ⋯ menu
    @AppStorage("includeMic", store: AppDefaults.store) private var includeMic = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(model: model, vocab: vocab, study: study, route: $route)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            Group {
                switch route ?? .live {
                case .live: LiveView(model: model, vocab: vocab)
                case .translate: TranslateScreen(pad: translatePad)
                case .progress: ProgressScreen(vocab: vocab, study: study)
                case .daily: DailyView(study: study, vocab: vocab)
                case .topics: TopicsView(study: study, vocab: vocab)
                case .grammar: GrammarView(study: study)
                case .vocabulary: VocabularyView(store: vocab)
                case .practice: PracticeView(store: vocab)
                case .listening: ListeningView()
                case .conversation: ConversationView(vocab: vocab)
                case .writing: WritingView(store: writing)
                case .reading: ReadingView(store: reading, vocab: vocab)
                case .pronunciation: PronunciationView(store: model.pronunciation, vocab: vocab, target: model.target)
                case .session(let url): SessionView(url: url, vocab: vocab).id(url)
                }
            }
            .background(Backdrop())
        }
        .navigationSubtitle(showsInterpreter ? model.status : "")
        .modifier(CheckInAlert(model: model))
        .onChange(of: route) { if route == nil { route = .live } }
        .toolbar { if showsInterpreter { toolbar } } // learning screens have their own controls
        // Narrow window → hide the sidebar and shorten toolbar labels (only when crossing the threshold).
        .onGeometryChange(for: Bool.self) { $0.size.width < 820 } action: { narrow in
            withAnimation(.smooth) { columns = narrow ? .detailOnly : .all }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 1080 } action: { compact = $0 }
        .onGeometryChange(for: Bool.self) { $0.size.width < 640 } action: { fold = $0 }
        .tint(.parley)
        .task { await model.loadLanguages() }
        .task { // debug: `open … --args --autostart [--record-screen] | --open-video | --route <translate|daily|topics|grammar|vocabulary|practice|pronunciation|history>`
            let args = CommandLine.arguments
            if let size = DebugArgs.value("--window-size")?.split(separator: ",").compactMap({ Double($0) }), size.count == 2 {
                try? await Task.sleep(for: .milliseconds(300))
                NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?
                    .setContentSize(NSSize(width: size[0], height: size[1])) // debug: narrow-layout screenshots
            }
            if DebugArgs.has("--settings") { // screenshots of the Settings window alone
                try? await Task.sleep(for: .seconds(1))
                openSettings()
                dismissWindow(id: "main")
            }
            if DebugArgs.has("--mini") {
                try? await Task.sleep(for: .seconds(1)) // scenes aren't ready on the very first frame
                openWindow(id: "mini")
                if DebugArgs.has("--mini-sample") { // screenshots: a long session in a small Mini window
                    model.lines = MiniView.sample
                    dismissWindow(id: "main")
                    if let size = DebugArgs.value("--mini-size")?.split(separator: ",").compactMap({ Double($0) }), size.count == 2 {
                        try? await Task.sleep(for: .milliseconds(300))
                        let mini = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("mini") == true }
                        mini?.setContentSize(NSSize(width: size[0], height: size[1]))
                        mini?.center() // away from the owner's own Mini window in the corner
                    }
                    // `--mini-scroll top` or `top-bottom`: scroll the way a user would, to check every line is reachable
                    if let plan = DebugArgs.value("--mini-scroll"), let mini = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("mini") == true }),
                       let scroll = mini.contentView.flatMap(Self.scrollView(in:)) {
                        for step in plan.split(separator: "-") {
                            try? await Task.sleep(for: .seconds(1))
                            scroll.contentView.scroll(to: Self.edge(of: scroll, top: step == "top"))
                            scroll.reflectScrolledClipView(scroll.contentView)
                        }
                    }
                }
            }
            if let i = args.firstIndex(of: "--route"), args.indices.contains(i + 1) {
                let routes: [String: Route] = ["translate": .translate, "progress": .progress, "listening": .listening, "conversation": .conversation, "writing": .writing, "reading": .reading, "daily": .daily, "topics": .topics, "grammar": .grammar,
                                               "vocabulary": .vocabulary, "practice": .practice, "pronunciation": .pronunciation]
                route = routes[args[i + 1]] ?? .live
                if args[i + 1] == "history", let url = Model.history().first { route = .session(url) }
            }
            if CommandLine.arguments.contains("--open-video"),
               let url = Model.history().first(where: { FileManager.default.fileExists(atPath: Model.media($0, "screen.mov").path) }) {
                route = .session(url)
            }
            guard CommandLine.arguments.contains("--autostart") else { return }
            model.recordScreen = CommandLine.arguments.contains("--record-screen")
            await model.start()
        }
        .translationTask(model.prepareConfig) { session in
            do {
                try await session.prepareTranslation()
                await model.translationPrepared()
            } catch {
                print("start: translation download failed:", error)
                model.packStillMissing()
            }
        }
    }

    /// The interpreter's language bar, mic, screen toggle and Start/Stop belong to the live and history screens; while
    /// recording they stay everywhere so the session can always be stopped.
    /// Debug: the first scroll view under `view` (the Mini window's transcript).
    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let s = view as? NSScrollView { return s }
        for sub in view.subviews { if let s = scrollView(in: sub) { return s } }
        return nil
    }

    /// Debug: the clip-view origin that shows the top or the bottom of the document.
    private static func edge(of scroll: NSScrollView, top: Bool) -> NSPoint {
        let doc = scroll.documentView?.frame.height ?? 0, visible = scroll.contentView.bounds.height
        let flipped = scroll.documentView?.isFlipped ?? true
        let topY = flipped ? 0 : max(0, doc - visible), bottomY = flipped ? max(0, doc - visible) : 0
        return NSPoint(x: 0, y: top ? topY : bottomY)
    }

    private var showsInterpreter: Bool { Route.showsInterpreter(route ?? .live, running: model.running) }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // Running: locked settings collapse into one read-only status strip (no glass for non-interactive items, per HIG).
        if model.running, let since = model.startedAt {
            ToolbarItem(placement: .principal) {
                RecordingPill(since: since, screen: model.recordScreen, mic: includeMic,
                              languages: "\(Model.code(model.source)) → \(Model.code(model.target))")
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { LanguageBar(model: model, compact: compact) }
        }
        // Narrow toolbar: fold secondary controls into one menu so Start/Stop never ends up in the » overflow.
        if fold {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Nghe micro", systemImage: "mic", isOn: $includeMic).disabled(model.running)
                    Toggle("Quay màn hình", systemImage: "record.circle", isOn: $model.recordScreen).disabled(model.running)
                    Divider()
                    Button("Cửa sổ mini", systemImage: "pip.enter") { openWindow(id: "mini"); dismissWindow(id: "main") }
                } label: {
                    Label("Tuỳ chọn", systemImage: "ellipsis")
                }
                .menuIndicator(.hidden)
                .help("Micro, quay màn hình, cửa sổ mini")
            }
        } else {
            if !model.running {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $includeMic) { Label("Micro", systemImage: includeMic ? "mic.fill" : "mic.slash") }
                        .help(includeMic ? "Nghe cả giọng của bạn: bật" : "Nghe cả giọng của bạn: tắt")
                    Toggle(isOn: $model.recordScreen) { Label("Quay màn hình", systemImage: "record.circle") }
                        .help("Quay cả màn hình kèm âm thanh trong phiên tới")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { openWindow(id: "mini"); dismissWindow(id: "main") } label: { Label("Cửa sổ mini", systemImage: "pip.enter") }
                    .help("Thu nhỏ thành cửa sổ mini luôn nổi trên cùng (⌘⇧P)")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { Task { await model.toggle() } } label: {
                Label(model.running ? "Dừng" : "Bắt đầu", systemImage: model.running ? "stop.fill" : "play.fill")
                    .labelStyle(.titleAndIcon)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glassProminent)
            .tint(model.running ? .red : .parley)
            .help(model.running ? "Dừng và lưu phiên (⌘R)" : "Bắt đầu nghe và dịch (⌘R)")
        }
    }
}

struct LanguageBar: View {
    let model: Model
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Picker("Ngôn ngữ đang nghe", selection: Binding(get: { model.sourceLocale.identifier },
                                                                set: { model.sourceLocale = Locale(identifier: $0) })) {
                    ForEach(model.sourceOptions, id: \.identifier) { Text(Model.name($0)).tag($0.identifier) }
                }
                .pickerStyle(.inline)
            } label: {
                if compact { Text(Model.code(model.source)) } else { Label(Model.shortName(model.sourceLocale), systemImage: "ear") }
            }
            .help("Ngôn ngữ đang nghe")

            Button {
                withAnimation(.snappy) { model.swapLanguages() }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .disabled(!model.canSwap)
            .help("Đổi chiều dịch")

            Menu {
                Picker("Dịch sang", selection: Binding(get: { model.target.minimalIdentifier },
                                                       set: { model.target = Locale.Language(identifier: $0) })) {
                    ForEach(model.targetOptions, id: \.minimalIdentifier) { Text(Model.name($0)).tag($0.minimalIdentifier) }
                }
                .pickerStyle(.inline)
            } label: {
                if compact { Text(Model.code(model.target)) } else { Label(Model.name(model.target), systemImage: "character.bubble") }
            }
            .help("Dịch sang")
        }
        .labelStyle(.titleAndIcon)
        .disabled(model.running)
    }
}

struct RecordingPill: View {
    let since: Date
    let screen: Bool
    var mic = false
    var languages: String? // e.g. "EN → VI"; nil in the mini window
    @State private var on = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 8, height: 8)
                .opacity(on ? 1 : 0.25)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: on)
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .font(.callout.weight(.semibold))
            if mic || screen || languages != nil {
                Rectangle().fill(.secondary.opacity(0.4)).frame(width: 1, height: 14)
            }
            if mic { Image(systemName: "mic.fill").foregroundStyle(.orange).help("Đang nghe micro") }
            if screen { Image(systemName: "record.circle.fill").foregroundStyle(.red).help("Đang quay màn hình") }
            if let languages { Text(languages).font(.callout.weight(.medium)).foregroundStyle(.secondary) }
        }
        .font(.callout)
        .padding(.horizontal, languages == nil ? 8 : 14)
        .padding(.vertical, languages == nil ? 0 : 6)
        .background { if languages != nil { Capsule().fill(Color.red.opacity(0.10)) } }
        .overlay { if languages != nil { Capsule().strokeBorder(Color.red.opacity(0.25)) } }
        .onAppear { on = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Đang ghi")
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    let model: Model
    let vocab: VocabStore
    let study: StudyStore
    @Binding var route: Route?
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        let _ = model.historyVersion
        let sessions = Model.history()
        List(selection: $route) {
            Section {
                // Plain tags (List selection is Binding<Route?>, rows are tagged with Route); NavigationLink(value:) rows lost selection with .badge.
                Label {
                    Text("Phiên dịch trực tiếp")
                } icon: {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: model.running)
                }
                .tag(Route.live)
                Label("Dịch văn bản & ảnh", systemImage: "character.bubble")
                    .tag(Route.translate)
            }
            Section("Học") {
                Label {
                    Text("Tiến độ")
                } icon: {
                    MiniRing(fraction: activity.metToday ? 1 : Double(activity.todayXP) / Double(max(activity.goal, 1)))
                }
                .badge(Text(activity.streak > 0 ? "🔥 \(activity.streak)" : "\(activity.todayXP)/\(activity.goal)"))
                .help("Hôm nay \(activity.todayXP)/\(activity.goal) XP · chuỗi \(activity.streak) ngày")
                .tag(Route.progress)
                Label("Mỗi ngày", systemImage: "calendar.badge.plus")
                    .badge(study.data.day == StudyStore.day(.now) ? study.remainingToday : study.goal)
                    .tag(Route.daily)
                Label("Chủ đề", systemImage: "square.grid.2x2")
                    .tag(Route.topics)
                Label("Ngữ pháp", systemImage: "text.book.closed")
                    .tag(Route.grammar)
                Label("Từ vựng của tôi", systemImage: "character.book.closed")
                    .badge(vocab.learning)
                    .tag(Route.vocabulary)
                Label("Học tập", systemImage: "graduationcap")
                    .badge(vocab.dueCount)
                    .tag(Route.practice)
                Label("Luyện nghe", systemImage: "headphones")
                    .tag(Route.listening)
                Label("Hội thoại AI", systemImage: "bubble.left.and.text.bubble.right")
                    .tag(Route.conversation)
                Label("Luyện viết", systemImage: "square.and.pencil")
                    .tag(Route.writing)
                Label("Đọc hiểu", systemImage: "book.pages")
                    .tag(Route.reading)
                Label("Phát âm của tôi", systemImage: "waveform.badge.mic")
                    .badge(model.pronunciation.needsWork.count)
                    .tag(Route.pronunciation)
            }
            Section("Lịch sử") {
                ForEach(sessions, id: \.self) { url in
                    let live = model.running && url.deletingPathExtension().lastPathComponent == model.stamp
                    SessionRow(url: url, live: live)
                        .tag(Route.session(url))
                        .contextMenu {
                            Button("Hiện trong Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Divider()
                            Button("Chuyển vào Thùng rác", systemImage: "trash", role: .destructive) {
                                if route == .session(url) { route = .live }
                                model.trash(url)
                            }
                            .disabled(live)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .animation(.default, value: sessions)
    }
}

struct SessionRow: View {
    let url: URL
    let live: Bool

    var body: some View {
        let preview = (try? String(contentsOf: url, encoding: .utf8)).map(Model.parse)?.first?.en
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(url)).fontWeight(.medium).lineLimit(1)
                Text(preview ?? "Chưa có lời nói").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if live {
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.red).symbolEffect(.pulse)
            } else if FileManager.default.fileExists(atPath: Model.media(url, "screen.mov").path) {
                Image(systemName: "video.fill").font(.caption).foregroundStyle(.secondary).help("Có video quay màn hình")
            }
        }
        .padding(.vertical, 3)
    }

    nonisolated static func title(_ url: URL) -> String {
        guard let d = Model.date(of: url) else { return url.deletingPathExtension().lastPathComponent }
        let time = d.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(d) { return "Hôm nay, \(time)" }
        if Calendar.current.isDateInYesterday(d) { return "Hôm qua, \(time)" }
        return d.formatted(.dateTime.day().month().year().hour().minute())
    }
}

// MARK: - Live

struct LiveView: View {
    let model: Model
    let vocab: VocabStore

    var body: some View {
        Group {
            if model.lines.isEmpty && model.liveEN.isEmpty {
                EmptyLive(model: model)
            } else {
                Bilingual {
                    TranscriptCard(title: Model.name(model.sourceLocale), code: Model.code(model.source)) {
                        MeterGroup(model: model)
                    } content: {
                        TranscriptView(lines: model.lines.map { .init(time: Self.time($0.time), source: $0.source, text: $0.en, counterpart: $0.vi) },
                                       live: Self.live(model.liveEN), language: model.source, other: model.target,
                                       session: model.stamp, vocab: vocab)
                    }
                    TranscriptCard(title: Model.name(model.target), code: Model.code(model.target)) {
                        EmptyView()
                    } content: {
                        TranscriptView(lines: model.lines.map { .init(time: Self.time($0.time), source: $0.source, text: $0.vi, counterpart: $0.en) },
                                       live: Self.live(model.liveVI), language: model.target, other: model.source, isSource: false,
                                       session: model.stamp, vocab: vocab)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: model.lines.isEmpty && model.liveEN.isEmpty)
        .navigationTitle("Phiên dịch trực tiếp")
    }

    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .standard) }
    static func live(_ text: [Source: String]) -> [(Source, String)] { Source.allCases.compactMap { s in text[s].map { (s, $0) } } }
}

/// Side by side when there is room, stacked when the window is narrow.
struct Bilingual<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var narrow = false

    var body: some View {
        let layout = narrow ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
        layout { content }
            .padding(narrow ? 10 : 14)
            .onGeometryChange(for: Bool.self) { $0.size.width < 700 } action: { narrow = $0 }
            .animation(.smooth, value: narrow)
    }
}

struct TranscriptCard<Accessory: View, Content: View>: View {
    let title: String
    let code: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(code)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.parley.gradient, in: Capsule())
                Text(title).font(.headline).lineLimit(1)
                Spacer()
                accessory
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider().opacity(0.6)
            content
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
    }
}

struct MeterGroup: View {
    let model: Model
    @AppStorage("includeMic", store: AppDefaults.store) private var includeMic = true

    var body: some View {
        HStack(spacing: 14) {
            AudioMeter(source: .system, level: model.levels[.system] ?? 0, active: model.running)
            if includeMic { AudioMeter(source: .mic, level: model.levels[.mic] ?? 0, active: model.running) }
        }
    }
}

struct AudioMeter: View {
    let source: Source
    let level: Float
    let active: Bool
    /// -55…-10 dBFS mapped to 0…1.
    private var norm: Double { Double(min(1, max(0, (20 * log10(max(level, 1e-5)) + 55) / 45))) }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: source.symbol).font(.caption).foregroundStyle(active ? source.color : .secondary)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    let h = active ? max(0.18, min(1, norm * 1.5 - abs(Double(i) - 2) * 0.22)) : 0.18
                    Capsule().fill(source.color.opacity(active ? 0.9 : 0.25)).frame(width: 3, height: 3 + 13 * h)
                }
            }
            .frame(height: 16)
        }
        .animation(.easeOut(duration: 0.12), value: norm)
        .help(source.label)
        .accessibilityLabel(source.label)
    }
}

struct EmptyLive: View {
    let model: Model
    @State private var breathe = false

    var body: some View {
        if model.needsPermission {
            ScrollView { PermissionView(model: model) }
        } else if model.missingPack {
            ScrollView { LanguagePackView(model: model) }
        } else {
            ViewThatFits(in: .vertical) { hero(compact: false); hero(compact: true) }
        }
    }

    private func hero(compact: Bool) -> some View {
        VStack(spacing: compact ? 12 : 22) {
            ZStack {
                Circle().fill(Color.parley.opacity(0.10)).frame(width: compact ? 96 : 156, height: compact ? 96 : 156)
                    .scaleEffect(model.running && breathe ? 1.1 : 1)
                    .animation(model.running ? .easeInOut(duration: 1.4).repeatForever() : .default, value: breathe)
                Circle().fill(Color.parley.opacity(0.16)).frame(width: compact ? 66 : 108, height: compact ? 66 : 108)
                Image(systemName: model.running ? "waveform" : "captions.bubble.fill")
                    .font(.system(size: compact ? 30 : 46, weight: .medium))
                    .foregroundStyle(Color.parley.gradient)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: model.running)
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(spacing: 8) {
                Text(model.running ? "Đang lắng nghe…" : "Sẵn sàng phiên dịch")
                    .font(compact ? .title2.weight(.semibold) : .largeTitle.weight(.semibold))
                Text(model.running
                     ? "Khi có người nói \(Model.name(model.source)), lời nói và bản dịch sẽ hiện ở đây."
                     : "Mở cuộc họp hoặc video rồi bấm Bắt đầu. Mọi thứ chạy ngay trên máy — không cần mạng, không gửi dữ liệu đi đâu.")
                    .font(compact ? .callout : .title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            if model.running {
                MeterGroup(model: model).scaleEffect(1.5).padding(.top, 6)
            } else {
                Button { Task { await model.start() } } label: {
                    Label("Bắt đầu", systemImage: "play.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                if !compact { HStack(spacing: 34) {
                    Feature(symbol: "lock.shield.fill", title: "100% offline")
                    Feature(symbol: "rectangle.split.2x1.fill", title: "Song ngữ realtime")
                    Feature(symbol: "character.book.closed.fill", title: "Bôi đen để học từ")
                }
                .padding(.top, 12) }
            }
        }
        .padding(compact ? 16 : 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { breathe = true }
    }
}

struct PermissionView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.14)).frame(width: 120, height: 120)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.orange.gradient)
                    .symbolEffect(.wiggle, options: .repeat(2))
            }
            VStack(spacing: 8) {
                Text("Cho phép Parley nghe âm thanh của máy").font(.title.weight(.semibold))
                Text("Để dịch Zoom, Meet hay video, macOS cần bạn cho phép một lần. Âm thanh chỉ được xử lý ngay trên máy này.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
            }
            VStack(alignment: .leading, spacing: 12) {
                Step(number: 1, text: "Bấm **Mở Cài đặt** bên dưới")
                Step(number: 2, text: "Bật công tắc cạnh **Parley** trong *Screen & System Audio Recording*")
                Step(number: 3, text: "Quay lại đây và bấm **Khởi động lại**")
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            HStack(spacing: 12) {
                Button { model.openPermissionSettings() } label: { Label("Mở Cài đặt", systemImage: "gearshape") }
                    .buttonStyle(.glassProminent)
                Button { model.relaunch() } label: { Label("Khởi động lại", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

struct LanguagePackView: View {
    let model: Model

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(Color.parley.opacity(0.14)).frame(width: 120, height: 120)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(Color.parley.gradient)
                    .symbolEffect(.bounce, options: .repeat(2))
            }
            VStack(spacing: 8) {
                Text("Cần tải gói dịch \(Model.name(model.source)) → \(Model.name(model.target))").font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Gói này chỉ tải một lần, sau đó dịch hoàn toàn offline. Nếu bạn không định dùng cặp ngôn ngữ này, hãy đổi lại ở thanh công cụ phía trên.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 480)
            }
            HStack(spacing: 12) {
                Button { Task { await model.start() } } label: { Label("Tải gói dịch", systemImage: "arrow.down.circle") }
                    .buttonStyle(.glassProminent)
                Button { model.openLanguageSettings() } label: { Label("Mở Cài đặt ngôn ngữ", systemImage: "gearshape") }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
            Text("Trong Cài đặt: General › Language & Region › Translation Languages")
                .font(.callout).foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.parley.gradient, in: Circle())
            Text(text)
        }
    }
}

struct Feature: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.parley.gradient)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Saved session

struct SessionView: View {
    let url: URL
    let vocab: VocabStore
    @State private var entries: [Model.Entry] = []
    @State private var player: AVPlayer?
    @State private var playing: Int? // entry being heard right now
    @State private var source = Locale.Language(identifier: "en-US")
    @State private var target = Locale.Language(identifier: "vi")

    var body: some View {
        let stamp = url.deletingPathExtension().lastPathComponent
        Group {
            if let player {
                // Video on top, transcript below; drag the divider to resize.
                VSplitView {
                    PlayerView(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding([.horizontal, .top], 14)
                        .padding(.bottom, 6)
                        .frame(minHeight: 180, idealHeight: 380)
                    transcript(stamp).frame(minHeight: 180)
                }
            } else {
                transcript(stamp)
            }
        }
        .navigationTitle(SessionRow.title(url))
        .toolbar {
            ToolbarItemGroup {
                ForEach(Source.allCases, id: \.self) { s in
                    let audio = Model.media(url, "\(s.fileSuffix).m4a")
                    if FileManager.default.fileExists(atPath: audio.path) {
                        Button { NSWorkspace.shared.open(audio) } label: {
                            Label(s == .mic ? "Nghe lại micro" : "Nghe lại âm thanh máy", systemImage: s == .mic ? "mic" : "speaker.wave.2")
                        }
                        .help(s == .mic ? "Nghe lại micro" : "Nghe lại âm thanh máy")
                    }
                }
                let video = Model.media(url, "screen.mov")
                if FileManager.default.fileExists(atPath: video.path) {
                    Button { NSWorkspace.shared.open(video) } label: { Label("Xem video", systemImage: "play.rectangle") }
                        .help("Xem video quay màn hình")
                }
                Button { NSWorkspace.shared.open(url) } label: { Label("Mở ghi chú", systemImage: "doc.text") }
                    .help("Mở file ghi chú (.md)")
            }
        }
        .task(id: url) {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            (source, target) = Model.languages(in: text)
            entries = Model.parse(text)
            let video = Model.media(url, "screen.mov")
            player = FileManager.default.fileExists(atPath: video.path) ? AVPlayer(url: video) : nil
            // Follow playback: highlight the sentence being heard.
            while let player, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                let now = player.currentTime().seconds
                let i = entries.lastIndex { ($0.offset ?? .infinity) <= now + 0.2 }
                if i != playing { playing = i }
            }
        }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder private func transcript(_ stamp: String) -> some View {
        if entries.isEmpty {
            ContentUnavailableView("Phiên này chưa có lời nói", systemImage: "text.bubble",
                                   description: Text("Có thể phiên đã dừng trước khi có người nói."))
        } else {
            let seek: ((Int) -> Void)? = player == nil ? nil : { i in
                guard let t = entries[i].offset else { return }
                player?.seek(to: CMTime(seconds: max(0, t - 0.3), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                player?.play()
            }
            Bilingual {
                TranscriptCard(title: Model.name(source), code: Model.code(source)) {
                    if player != nil { Label("Bấm một câu để tua", systemImage: "hand.tap").font(.caption).foregroundStyle(.secondary) }
                } content: {
                    TranscriptView(lines: entries.map { .init(time: $0.time, source: $0.source, text: $0.en, counterpart: $0.vi) },
                                   language: source, other: target, session: stamp, vocab: vocab,
                                   highlighted: playing, onLineClick: seek)
                }
                TranscriptCard(title: Model.name(target), code: Model.code(target)) { EmptyView() } content: {
                    TranscriptView(lines: entries.map { .init(time: $0.time, source: $0.source, text: $0.vi, counterpart: $0.en) },
                                   language: target, other: source, isSource: false, session: stamp, vocab: vocab,
                                   highlighted: playing, onLineClick: seek)
                }
            }
        }
    }
}

/// AppKit's player (same as QuickTime). SwiftUI's `VideoPlayer` aborts at launch of the view on macOS 27 when the app
/// is built as a Swift package (its _AVKit_SwiftUI overlay fails to resolve AVPlayerView's metadata).
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .floating
        v.showsFullScreenToggleButton = true
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if v.player !== player { v.player = player }
    }
}

// MARK: - Word card (selection popover)

struct WordCard: View {
    let term: String
    let language: Locale.Language // language of `term`
    let other: Locale.Language
    let isSource: Bool             // term is in the heard language (the one being learned)
    let context: String
    let contextOther: String
    let session: String?
    let vocab: VocabStore
    @State private var meaning: String?
    @State private var failed = false
    @State private var bounce = 0
    @AppStorage("showIPA", store: AppDefaults.store) private var showIPA = true
    @AppStorage("autoSpeak", store: AppDefaults.store) private var autoSpeak = false

    /// The word in the language being learned, and that language.
    private var learnTerm: String { isSource ? term : (meaning ?? "") }
    private var learnLanguage: Locale.Language { isSource ? language : other }
    private var words: Int { term.split(whereSeparator: \.isWhitespace).count }
    private var ipa: String? { showIPA ? Pronunciation.ipa(learnTerm, language: learnLanguage) : nil }
    private var saved: Bool { !learnTerm.isEmpty && vocab.contains(learnTerm) }
    /// Hide the example when the selection already is (most of) that sentence — it would just repeat itself.
    private var showContext: Bool { !context.isEmpty && !Model.isEcho(term, of: context) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { details }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 440) // long selections scroll instead of growing past the screen
            HStack {
                Spacer()
                if saved {
                    Label("Đã lưu vào từ vựng", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Button { save() } label: { Label("Thêm vào từ vựng", systemImage: "plus") }
                        .buttonStyle(.glassProminent)
                        .disabled(meaning == nil)
                        .transition(.opacity)
                }
            }
            .padding([.horizontal, .bottom], 18)
            .padding(.top, 10)
        }
        .frame(width: 360)
        .tint(.parley)
        .animation(.spring(duration: 0.35), value: saved)
        .animation(.easeOut(duration: 0.25), value: meaning)
        .task {
            if autoSpeak, isSource { speak() }
            meaning = await Translator.translate(term, from: language, to: other)
            failed = meaning == nil
            if autoSpeak, !isSource, meaning != nil { speak() } // hear the word in the language being learned
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(term)
                        .font(words > 8 ? .title3.weight(.semibold) : .title2.weight(.semibold))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if isSource, let ipa { ipaText(ipa) }
                }
                Spacer(minLength: 8)
                Button { speak() } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .symbolEffect(.bounce, value: bounce)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Nghe phát âm")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(Model.name(other).uppercased())
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                if let meaning {
                    Text(meaning).font(.title3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    if !isSource, let ipa { ipaText(ipa) }
                } else if failed {
                    Text("Chưa có gói dịch offline cho chiều này").foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Đang dịch…").foregroundStyle(.secondary) }
                }
            }

            if showContext {
                VStack(alignment: .leading, spacing: 4) {
                    Text(highlight(context))
                    if !contextOther.isEmpty { Text(contextOther).foregroundStyle(.secondary) }
                }
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.parley.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding([.horizontal, .top], 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Wraps fully (long phrases scroll inside the card instead of being cut with "…").
    private func ipaText(_ ipa: String) -> some View {
        Text(ipa)
            .font(.system(size: words > 8 ? 13 : 15))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func speak() {
        bounce += 1
        if learnTerm.isEmpty { Speaker.speak(term, language: language) } else { Speaker.speak(learnTerm, language: learnLanguage) }
    }

    private func save() {
        guard let meaning else { return }
        vocab.add(VocabItem(term: isSource ? term : meaning, meaning: isSource ? meaning : term,
                            termLanguage: learnLanguage.maximalIdentifier,
                            meaningLanguage: (isSource ? other : language).minimalIdentifier,
                            ipa: Pronunciation.ipa(learnTerm, language: learnLanguage),
                            example: isSource ? context : contextOther,
                            exampleTranslation: isSource ? contextOther : context,
                            session: session))
    }

    private func highlight(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        if let r = a.range(of: term, options: .caseInsensitive) {
            a[r].foregroundColor = .parley
            a[r].font = .callout.bold()
        }
        return a
    }
}

// MARK: - Vocabulary

struct VocabularyView: View {
    let store: VocabStore
    @State private var search = ""
    @State private var filter = 0 // 0 all · 1 learning · 2 mastered
    @State private var selection = Set<UUID>()
    @State private var sort = [KeyPathComparator(\VocabItem.added, order: .reverse)]
    @State private var transferMessage: String?
    @State private var transferErrors: [String] = []

    var body: some View {
        let rows = store.items.filter { item in
            (filter == 0 || (filter == 1) != item.mastered)
                && (search.isEmpty || item.term.localizedCaseInsensitiveContains(search) || item.meaning.localizedCaseInsensitiveContains(search))
        }.sorted(using: sort)
        Group {
            if store.items.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có từ nào", systemImage: "character.book.closed")
                } description: {
                    Text("Trong lúc phiên dịch, bôi đen một từ hoặc cụm từ rồi bấm “Thêm vào từ vựng”. Từ được lưu kèm phiên âm, nghĩa và câu ví dụ.")
                }
            } else {
                VStack(spacing: 12) {
                    VocabSummary(store: store)
                    vocabTable(rows)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .contextMenu(forSelectionType: VocabItem.ID.self) { ids in
                        Button("Đánh dấu đã thuộc", systemImage: "checkmark.circle") { store.setMastered(ids, true) }
                        Button("Đánh dấu đang học", systemImage: "arrow.uturn.backward.circle") { store.setMastered(ids, false) }
                        Divider()
                        Button("Xoá", systemImage: "trash", role: .destructive) { store.remove(ids) }
                    } primaryAction: { ids in
                        if let item = store.items.first(where: { ids.contains($0.id) }) {
                            Speaker.speak(item.term, language: Locale.Language(identifier: item.termLanguage))
                        }
                    }
                    .onDeleteCommand { store.remove(selection) }
                }
                .padding(14)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Tìm từ")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Nhập từ tệp CSV / TSV (Anki, Excel)…", systemImage: "square.and.arrow.down") {
                        if let r = VocabFiles.importPanel(store) { transferErrors = r.errors; transferMessage = r.summary }
                    }
                    Button("Xuất ra tệp CSV…", systemImage: "square.and.arrow.up") {
                        if let m = VocabFiles.exportPanel(store) { transferErrors = []; transferMessage = m }
                    }
                    .disabled(store.items.isEmpty)
                } label: {
                    Label("Nhập / Xuất", systemImage: "arrow.up.arrow.down.square")
                }
                .help("Nhập hoặc xuất danh sách từ (CSV, mở được bằng Anki/Excel)")
            }
            ToolbarItem {
                Picker("Lọc", selection: $filter) {
                    Text("Tất cả").tag(0)
                    Text("Đang học").tag(1)
                    Text("Đã thuộc").tag(2)
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle("Từ vựng")
        .problemBanner(store.problem)
        .task { // debug/screenshots: `--import <file>` runs an import without the open panel
            if let path = DebugArgs.value("--import") {
                let r = VocabFiles.importFile(URL(fileURLWithPath: path), into: store)
                transferErrors = r.errors
                transferMessage = r.summary
            }
        }
        .alert(transferMessage ?? "", isPresented: Binding(get: { transferMessage != nil }, set: { if !$0 { transferMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            if !transferErrors.isEmpty {
                Text(transferErrors.prefix(8).joined(separator: "\n") + (transferErrors.count > 8 ? "\n… và \(transferErrors.count - 8) dòng khác" : ""))
            }
        }
    }

    private func vocabTable(_ rows: [VocabItem]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sort) {
            TableColumn("") { (item: VocabItem) in
                Button { Speaker.speak(item.term, language: Locale.Language(identifier: item.termLanguage)) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.parley)
                .help("Nghe")
            }
            .width(26)
            TableColumn("Từ / cụm từ", value: \.term) { (item: VocabItem) in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.term).fontWeight(.semibold)
                    if let ipa = item.ipa { Text(ipa).font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
            }
            TableColumn("Nghĩa", value: \VocabItem.meaning)
            TableColumn("Ví dụ") { (item: VocabItem) in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.example).lineLimit(2)
                    Text(item.exampleTranslation).foregroundStyle(.secondary).lineLimit(2)
                }
                .font(.callout)
            }
            TableColumn("Ngày thêm", value: \.added) { (item: VocabItem) in Text(item.added, format: .dateTime.day().month().year()).foregroundStyle(.secondary) }
                .width(min: 80, ideal: 90)
            TableColumn("Đã thuộc", value: \.masteredRank) { (item: VocabItem) in
                Toggle("Đã thuộc", isOn: Binding(get: { item.mastered }, set: { store.setMastered([item.id], $0) }))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
            }
            .width(60)
        }
    }
}

struct VocabSummary: View {
    let store: VocabStore

    var body: some View {
        let total = store.items.count
        let done = total - store.learning
        HStack(spacing: 16) {
            Gauge(value: Double(done), in: 0...Double(max(total, 1))) {
                EmptyView()
            } currentValueLabel: {
                Text("\(done * 100 / max(total, 1))%").font(.caption.weight(.bold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(Color.parley)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(total) từ đã lưu").font(.title3.weight(.semibold))
                Text("\(store.learning) đang học · \(done) đã thuộc").foregroundStyle(.secondary)
            }
            Spacer()
            Label("Bấm loa hoặc nhấp đúp một dòng để nghe", systemImage: "speaker.wave.2").font(.callout).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .animation(.smooth, value: done)
    }
}

// MARK: - Mini window (always on top, corner of the screen)

struct MiniView: View {
    let model: Model
    /// Rows the Mini window keeps (a whole meeting stays in the main window): enough to scroll back through a long
    /// conversation without laying out thousands of rows on every live update.
    nonisolated static let limit = 200

    /// The last `limit` lines.
    nonisolated static func shownRange(count: Int) -> Range<Int> { max(0, count - limit)..<count }

    /// `--mini-sample [n]`: n lines (default 100) of mixed length, the first and last easy to spot.
    static var sample: [Model.Line] {
        let n = DebugArgs.value("--mini-sample").flatMap(Int.init) ?? 100
        return (1...max(1, n)).map { i in
            let long = i % 4 == 0
            let vi = i == 1 ? "DÒNG ĐẦU TIÊN (1)" : i == n ? "DÒNG CUỐI CÙNG (\(i))"
                : long ? "Cuộc họp tuần tới bắt đầu lúc 2 giờ chiều thứ Ba. Vui lòng chia sẻ tài liệu trước một ngày. (\(i))"
                : "Tôi hiểu rồi. (\(i))"
            return Model.Line(source: i % 3 == 0 ? .mic : .system,
                              en: long ? "来週の会議は火曜日の午後二時からです。資料は前日までに共有してください。\(i)" : "了解しました。\(i)", vi: vi)
        }
    }
    /// Purple caret marks a sentence still being spoken; the words stay in the normal text color for readability.
    static let caret = Text(" ▍").foregroundStyle(Color.parley)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("fontSize", store: AppDefaults.store) private var fontSize = 17.0
    @AppStorage("miniShowSource", store: AppDefaults.store) private var showSource = true

    var body: some View {
        let shown = Self.shownRange(count: model.lines.count)
        let live = Source.allCases.filter { model.liveEN[$0] != nil } // sources currently mid-sentence
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if model.running, let since = model.startedAt {
                    RecordingPill(since: since, screen: model.recordScreen)
                } else {
                    Text("\(Model.code(model.source)) → \(Model.code(model.target))").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                MeterGroup(model: model)
                Button { showSource.toggle() } label: { Image(systemName: showSource ? "text.bubble.fill" : "text.bubble") }
                    .help(showSource ? "Ẩn câu gốc" : "Hiện câu gốc")
                Button { Task { await model.toggle() } } label: { Image(systemName: model.running ? "stop.fill" : "play.fill") }
                    .tint(model.running ? .red : .parley)
                    .help(model.running ? "Dừng (⌘R)" : "Bắt đầu (⌘R)")
                Button { openWindow(id: "main"); dismissWindow(id: "mini") } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Mở cửa sổ đầy đủ")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .padding(.leading, 76) // room for the window's traffic lights
            .padding(.trailing, 10)
            .padding(.vertical, 8)

            if model.lines.isEmpty && live.isEmpty {
                Text(model.running ? "Đang lắng nghe…" : "Bấm ▶ để bắt đầu phiên dịch")
                    .font(.title3).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Not lazy: a LazyVStack only estimates the height of rows it has not laid out, so after scrolling
                    // up the bottom-anchored view stopped short of the last line. At most `limit` rows are shown.
                    VStack(alignment: .leading, spacing: 12) {
                        if shown.lowerBound > 0 {
                            Label("\(shown.lowerBound) câu cũ hơn ở cửa sổ đầy đủ", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(shown, id: \.self) { i in
                            let l = model.lines[i]
                            VStack(alignment: .leading, spacing: 3) {
                                if showSource {
                                    Label { Text(l.en) } icon: { Image(systemName: l.source.symbol).foregroundStyle(l.source.color) }
                                        .font(.system(size: fontSize * 0.85)).foregroundStyle(.secondary)
                                }
                                Text(l.vi.isEmpty ? "…" : l.vi).font(.system(size: fontSize, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // In-progress sentence: same layout as finished ones (source above, translation below), in accent color.
                        ForEach(live, id: \.self) { s in
                            VStack(alignment: .leading, spacing: 3) {
                                if showSource {
                                    Label { Text("\(model.liveEN[s] ?? "")\(Self.caret)") } icon: { Image(systemName: s.symbol).foregroundStyle(s.color) }
                                        .font(.system(size: fontSize * 0.85)).foregroundStyle(.secondary)
                                }
                                Text("\(model.liveVI[s] ?? "…")\(showSource ? Text("") : Self.caret)")
                                    .font(.system(size: fontSize, weight: .medium))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
            }
        }
        .frame(minWidth: 320, minHeight: 140)
        .modifier(CheckInAlert(model: model))
        .containerBackground(.regularMaterial, for: .window)
        .tint(.parley)
    }
}

/// "Still recording?" prompt shown every 2 h (see Model.scheduleCheckIn); attached to both windows.
struct CheckInAlert: ViewModifier {
    let model: Model

    func body(content: Content) -> some View {
        content.alert("Bạn có muốn tiếp tục không?",
                      isPresented: Binding(get: { model.checkInDeadline != nil }, set: { _ in })) {
            Button("Tiếp tục ghi") { model.keepRunning() }
            Button("Dừng và lưu", role: .destructive) { Task { await model.stop() } }
        } message: {
            Text("Parley đã ghi liên tục \(Self.duration(Model.checkInterval)). Nếu bạn không chọn, phiên sẽ tự dừng và lưu sau \(Self.duration(Model.checkGrace)).")
        }
    }

    static func duration(_ s: TimeInterval) -> String {
        Duration.seconds(s).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

// MARK: - Settings & commands

struct SettingsView: View {
    @AppStorage("fontSize", store: AppDefaults.store) private var fontSize = 17.0
    @AppStorage("includeMic", store: AppDefaults.store) private var includeMic = true
    @AppStorage("showIPA", store: AppDefaults.store) private var showIPA = true
    @AppStorage("autoSpeak", store: AppDefaults.store) private var autoSpeak = false
    @AppStorage("speechRate", store: AppDefaults.store) private var speechRate = 0.85
    @AppStorage("reminderOn", store: AppDefaults.store) private var reminderOn = false
    @AppStorage("reminderMinutes", store: AppDefaults.store) private var reminderMinutes = Reminder.defaultMinutes
    @State private var reminderDenied = false

    var body: some View {
        Form {
            Section("Hiển thị") {
                LabeledContent("Cỡ chữ") {
                    HStack {
                        Slider(value: $fontSize, in: 13...32, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section {
                Toggle("Nghe cả micro (giọng của bạn)", isOn: $includeMic)
            } header: {
                Text("Nghe")
            } footer: {
                Text("Nên dùng tai nghe để micro không thu lại tiếng loa.").foregroundStyle(.secondary)
            }
            Section("Học từ") {
                Toggle("Tự đọc khi bôi đen", isOn: $autoSpeak)
                Toggle("Hiện phiên âm IPA (tiếng Anh)", isOn: $showIPA)
                LabeledContent("Tốc độ đọc") {
                    Slider(value: $speechRate, in: 0.5...1.2) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                }
            }
            Section {
                Toggle("Nhắc tôi học mỗi ngày", isOn: $reminderOn)
                DatePicker("Lúc", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: reminderMinutes / 60, minute: reminderMinutes % 60, second: 0, of: .now) ?? .now
                }, set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    reminderMinutes = (c.hour ?? 20) * 60 + (c.minute ?? 0)
                }), displayedComponents: .hourAndMinute)
                .disabled(!reminderOn)
            } header: {
                Text("Nhắc học")
            } footer: {
                Text(reminderDenied ? "macOS đang chặn thông báo của Parley — bật lại trong System Settings → Notifications."
                                    : "Chỉ nhắc khi hôm nay chưa đạt mục tiêu XP.")
                    .foregroundStyle(reminderDenied ? .orange : .secondary)
            }
            .onChange(of: reminderOn) {
                Task {
                    if reminderOn {
                        let granted = await Reminder.requestPermission()
                        reminderDenied = !AppDefaults.sandboxed && !granted
                    }
                    Reminder.reschedule()
                }
            }
            .onChange(of: reminderMinutes) { Reminder.reschedule() }
            .task {
                let denied = await Reminder.isDenied()
                reminderDenied = reminderOn && denied
            }
            Section("Dữ liệu") {
                LabeledContent("Thư mục", value: (Model.dataDir.path as NSString).abbreviatingWithTildeInPath)
                Button("Mở trong Finder") {
                    try? FileManager.default.createDirectory(at: Model.dataDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Model.dataDir)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ParleyCommands: Commands {
    let model: Model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("fontSize", store: AppDefaults.store) private var fontSize = 17.0
    @AppStorage("includeMic", store: AppDefaults.store) private var includeMic = true

    var body: some Commands {
        CommandMenu("Phiên dịch") {
            Button(model.running ? "Dừng" : "Bắt đầu") { Task { await model.toggle() } }
                .keyboardShortcut("r")
            Divider()
            Toggle("Nghe micro", isOn: $includeMic)
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(model.running)
            Toggle("Quay màn hình", isOn: Binding(get: { model.recordScreen }, set: { model.recordScreen = $0 }))
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model.running)
            Divider()
            Button("Cửa sổ mini") { openWindow(id: "mini") }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Cửa sổ đầy đủ") { openWindow(id: "main") }
                .keyboardShortcut("0", modifiers: [.command, .shift])
            Divider()
            Button("Đổi chiều dịch") { model.swapLanguages() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(model.running || !model.canSwap)
        }
        CommandGroup(after: .toolbar) {
            Button("Phóng to chữ") { fontSize = min(fontSize + 2, 40) }.keyboardShortcut("+")
            Button("Thu nhỏ chữ") { fontSize = max(fontSize - 2, 12) }.keyboardShortcut("-")
            Button("Cỡ chữ mặc định") { fontSize = 17 }.keyboardShortcut("0")
            Divider()
        }
    }
}
