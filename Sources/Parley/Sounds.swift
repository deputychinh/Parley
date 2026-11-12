import SwiftUI

// MARK: - The sounds of (US) English, taught for Vietnamese speakers (PARLEY-32)

/// One English sound: the IPA symbol Parley shows on every word card (CMUdict, US English), how to make it, what a
/// Vietnamese speaker tends to say instead, and example words that contain it.
struct IPASound: Identifiable, Hashable {
    enum Group: String, CaseIterable, Identifiable {
        case shortVowel = "Nguyên âm ngắn", longVowel = "Nguyên âm dài", diphthong = "Nguyên âm đôi",
             pair = "Phụ âm theo cặp (vô thanh – hữu thanh)", consonant = "Phụ âm khác"
        var id: String { rawValue }
    }

    /// How much the sound matters for being understood (brief.md: intelligibility first).
    enum Priority: Int, Comparable {
        case high = 0, normal, low
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// ARPAbet without stress, except "AH0" (schwa) and "ER0" (unstressed r-vowel), which are their own sounds.
    let id: String
    let group: Group
    let priority: Priority
    let howTo: String
    let confusedWith: String
    let examples: [String]

    var symbol: String { Pronunciation.symbol(id.hasSuffix("0") ? id : id + "1") }

    /// Does this CMUdict phone ("AH1", "SH") stand for this sound?
    func matches(_ phone: String) -> Bool {
        let base = phone.filter { !$0.isNumber }
        if id == "AH0" || id == "ER0" { return phone == id }
        if id == "AH" || id == "ER" { return base == id && !phone.hasSuffix("0") }
        return base == id
    }

    static let all: [IPASound] = vowels + diphthongs + pairs + others

    /// The pair group as (voiceless, voiced) tuples, in table order.
    static func pairs(_ sounds: [IPASound]) -> [(IPASound, IPASound)] {
        stride(from: 0, to: sounds.count - 1, by: 2).map { (sounds[$0], sounds[$0 + 1]) }
    }

    /// Where the sound sits in an example word: "start", "middle", "end".
    func positions(in word: String) -> Set<String> {
        let phones = Pronunciation.phones(word) ?? []
        var out = Set<String>()
        for (i, p) in phones.enumerated() where matches(p) {
            out.insert(i == 0 ? "start" : i == phones.count - 1 ? "end" : "middle")
        }
        return out
    }

    static func sound(_ id: String) -> IPASound? { all.first { $0.id == id } }

    /// The sound a CMUdict phone belongs to.
    static func of(phone: String) -> IPASound? { all.first { $0.matches(phone) } }

    // Vowels — length and the neutral schwa change meaning and rhythm.
    static let vowels: [IPASound] = [
        .init(id: "IY", group: .longVowel, priority: .high,
              howTo: "Âm “i” kéo dài, môi bành sang hai bên như đang cười, lưỡi cao và căng.",
              confusedWith: "Đọc ngắn thành /ɪ/: sheep → ship, seat → sit.", examples: ["see", "eat", "team", "machine"]),
        .init(id: "IH", group: .shortVowel, priority: .high,
              howTo: "Âm “i” ngắn và lỏng: miệng thả lỏng, lưỡi thấp hơn /i/ một chút, nghe hơi ngả về “ê”.",
              confusedWith: "Kéo dài thành /i/: ship → sheep, sit → seat.", examples: ["it", "sit", "finish", "women"]),
        .init(id: "EH", group: .shortVowel, priority: .normal,
              howTo: "Gần “e” tiếng Việt, ngắn, miệng mở vừa.",
              confusedWith: "Mở rộng thành /æ/: bed → bad, men → man.", examples: ["bed", "ten", "many", "said"]),
        .init(id: "AE", group: .shortVowel, priority: .normal,
              howTo: "Hạ hàm thật thấp, miệng mở rộng như nói “e” nhưng hướng về “a”; lưỡi thấp và phẳng.",
              confusedWith: "Đọc thành “e” hay “a” tiếng Việt: bad → bed.", examples: ["cat", "bad", "apple", "plan"]),
        .init(id: "AH", group: .shortVowel, priority: .normal,
              howTo: "Như “ă/â” ngắn, miệng mở vừa, lưỡi ở giữa; âm này có trọng âm.",
              confusedWith: "Mở miệng quá rộng thành /æ/ hoặc đọc “a” dài: cup → cap, but → bat.", examples: ["cup", "love", "money", "but"]),
        .init(id: "AH0", group: .shortVowel, priority: .high,
              howTo: "Schwa — âm yếu nhất tiếng Anh: “ơ” rất nhẹ và ngắn, miệng thả lỏng hoàn toàn. Chỉ có ở âm tiết KHÔNG nhấn.",
              confusedWith: "Đọc rõ từng chữ cái (a-bao, ba-na-na) làm mất nhịp; người nghe khó tìm âm tiết chính.",
              examples: ["about", "banana", "problem", "sofa"]),
        .init(id: "UH", group: .shortVowel, priority: .normal,
              howTo: "Âm “u” ngắn và lỏng, môi tròn nhẹ, không chu.",
              confusedWith: "Kéo dài thành /u/: full → fool, look → Luke.", examples: ["book", "put", "good", "could"]),
        .init(id: "UW", group: .longVowel, priority: .normal,
              howTo: "Âm “u” kéo dài, môi tròn và chu ra trước.",
              confusedWith: "Đọc ngắn thành /ʊ/: pool → pull.", examples: ["food", "blue", "two", "school"]),
        .init(id: "AA", group: .longVowel, priority: .normal,
              howTo: "“a” mở to và sâu, lưỡi thấp, kéo dài hơn “a” tiếng Việt.",
              confusedWith: "Đọc thành “o” theo chữ viết: hot → hốt, stop → stốp.", examples: ["hot", "father", "stop", "car"]),
        .init(id: "AO", group: .longVowel, priority: .low,
              howTo: "“o” tròn môi, miệng mở; nhiều người Mỹ đọc giống /ɑ/ — cả hai đều được hiểu.",
              confusedWith: "Thường không gây hiểu nhầm.", examples: ["law", "talk", "call", "thought"]),
        .init(id: "ER", group: .longVowel, priority: .high,
              howTo: "“ơ” kèm cong lưỡi: đầu lưỡi cong lên phía sau, không chạm vòm; môi hơi tròn.",
              confusedWith: "Bỏ phần cong lưỡi thành “ơ”: work → walk, bird → bơ.", examples: ["bird", "work", "learn", "her"]),
        .init(id: "ER0", group: .shortVowel, priority: .normal,
              howTo: "Như /ɝ/ nhưng nhẹ và ngắn, ở âm tiết không nhấn (đuôi -er, -or).",
              confusedWith: "Đọc thành “ơ” tròn rõ: teacher → ti-chơ.", examples: ["teacher", "better", "water", "doctor"]),
    ]

    static let diphthongs: [IPASound] = [
        .init(id: "EY", group: .diphthong, priority: .normal,
              howTo: "Lướt từ “ê” sang “i”: “ây”.", confusedWith: "Bỏ phần “i” thành “ê”: late → let.",
              examples: ["day", "make", "rain", "eight"]),
        .init(id: "AY", group: .diphthong, priority: .normal,
              howTo: "Lướt từ “a” sang “i”: “ai”.", confusedWith: "Thường không gây hiểu nhầm.",
              examples: ["my", "time", "light", "buy"]),
        .init(id: "OY", group: .diphthong, priority: .low,
              howTo: "Lướt từ “o” sang “i”: “oi”.", confusedWith: "Thường không gây hiểu nhầm.",
              examples: ["boy", "choice", "noise", "join"]),
        .init(id: "AW", group: .diphthong, priority: .normal,
              howTo: "Lướt từ “a” sang “u”: “ao”.", confusedWith: "Đọc thành “ô”: now → nô.",
              examples: ["now", "house", "out", "down"]),
        .init(id: "OW", group: .diphthong, priority: .normal,
              howTo: "Lướt từ “ô” sang “u”, môi tròn dần: “âu”.", confusedWith: "Đọc “ô” đơn: phone → phôn, go → gô.",
              examples: ["go", "phone", "know", "road"]),
    ]

    // Consonants in voiceless–voiced pairs: the voice and the final sound carry meaning.
    static let pairs: [IPASound] = [
        .init(id: "P", group: .pair, priority: .high,
              howTo: "Đầu từ: bật một luồng hơi (đặt tay trước miệng sẽ thấy). Cuối từ: khép môi rồi mở nhẹ cho nghe ra “p”.",
              confusedWith: "Đầu từ không bật hơi nghe thành /b/; cuối từ bị nuốt: stop → sto.", examples: ["pen", "happy", "cup", "stop"]),
        .init(id: "B", group: .pair, priority: .high,
              howTo: "Như /p/ nhưng rung dây thanh (sờ cổ thấy rung), không bật hơi.",
              confusedWith: "Cuối từ đọc thành /p/ hoặc bỏ: job → jop, cab → cap.", examples: ["big", "rubber", "job", "club"]),
        .init(id: "T", group: .pair, priority: .high,
              howTo: "Đầu lưỡi chạm lợi sau răng trên (không chạm răng như “t” tiếng Việt), bật hơi ở đầu từ; cuối từ phải nghe ra “t” nhẹ.",
              confusedWith: "Nuốt âm cuối: light → lie, eight → ây.", examples: ["ten", "water", "cat", "eight"]),
        .init(id: "D", group: .pair, priority: .high,
              howTo: "Như /t/ nhưng rung, đầu lưỡi ở lợi (khác “đ” tiếng Việt chạm răng). Đuôi -ed sau âm hữu thanh đọc /d/.",
              confusedWith: "Cuối từ đọc thành /t/ hoặc bỏ: need → nee, played → play.", examples: ["day", "lady", "bed", "need"]),
        .init(id: "K", group: .pair, priority: .high,
              howTo: "Cuống lưỡi chạm vòm mềm rồi bật hơi; cuối từ phải nghe ra “k”.",
              confusedWith: "Nuốt âm cuối: bike → bai, book → bu.", examples: ["key", "school", "book", "bike"]),
        .init(id: "G", group: .pair, priority: .high,
              howTo: "Như /k/ nhưng rung, không bật hơi.", confusedWith: "Cuối từ đọc thành /k/ hoặc bỏ: dog → dock.",
              examples: ["go", "again", "big", "dog"]),
        .init(id: "F", group: .pair, priority: .high,
              howTo: "Răng trên chạm nhẹ môi dưới, thổi hơi qua khe; cuối từ giữ hơi đủ lâu để nghe ra.",
              confusedWith: "Tiếng Việt không có /f/ cuối từ nên hay bị bỏ: laugh → lah, off → o.", examples: ["five", "coffee", "off", "laugh"]),
        .init(id: "V", group: .pair, priority: .high,
              howTo: "Như /f/ nhưng rung — răng trên chạm môi dưới, KHÔNG mím hai môi.",
              confusedWith: "Cuối từ đọc thành /f/, /p/ hoặc bỏ: have → hap, five → fai.", examples: ["very", "seven", "love", "have"]),
        .init(id: "TH", group: .pair, priority: .low,
              howTo: "Đầu lưỡi đặt nhẹ giữa hai hàm răng, thổi hơi, không rung.",
              confusedWith: "Đọc thành “th” tiếng Việt, /t/ hoặc /s/: think → tink/sink. Ít ảnh hưởng việc được hiểu, nên luyện sau.",
              examples: ["think", "three", "nothing", "month"]),
        .init(id: "DH", group: .pair, priority: .low,
              howTo: "Như /θ/ nhưng rung: lưỡi giữa hai răng.",
              confusedWith: "Đọc thành “đ”, /d/ hoặc /z/: they → đây. Ít ảnh hưởng việc được hiểu, nên luyện sau.",
              examples: ["this", "they", "mother", "with"]),
        .init(id: "S", group: .pair, priority: .high,
              howTo: "Đầu lưỡi gần lợi trên, thổi hơi xì qua khe hẹp, môi bành. Cực quan trọng ở cuối từ: số nhiều, ngôi thứ ba (works).",
              confusedWith: "Bỏ “s” cuối: works → work; đọc thành /ʃ/: see → she.", examples: ["see", "basic", "bus", "works"]),
        .init(id: "Z", group: .pair, priority: .high,
              howTo: "Như /s/ nhưng rung, như tiếng ong vo ve. Đuôi -s sau âm hữu thanh đọc /z/: dogs, plays.",
              confusedWith: "Đọc thành /s/ hoặc bỏ: dogs → dog, is → ít.", examples: ["zoo", "easy", "is", "dogs"]),
        .init(id: "SH", group: .pair, priority: .high,
              howTo: "Môi tròn chu ra, lưỡi lùi về sau hơn /s/, thổi hơi “suỵt”.",
              confusedWith: "Đọc thành /s/ (“x” tiếng Việt): ship → sip, she → see.", examples: ["she", "ocean", "nation", "wash"]),
        .init(id: "ZH", group: .pair, priority: .low,
              howTo: "Như /ʃ/ nhưng rung.", confusedWith: "Đọc thành /z/ hoặc “gi”: measure → me-zơ.",
              examples: ["measure", "vision", "usual", "decision"]),
        .init(id: "CH", group: .pair, priority: .normal,
              howTo: "Bắt đầu như /t/ rồi bật sang /ʃ/, môi chu: mạnh và bật hơi hơn “ch” tiếng Việt.",
              confusedWith: "Đọc thành “ch/tr” tiếng Việt, cuối từ bị bỏ: watch → wa.", examples: ["chair", "teacher", "much", "watch"]),
        .init(id: "JH", group: .pair, priority: .normal,
              howTo: "Như /tʃ/ nhưng rung: /d/ trượt sang /ʒ/.",
              confusedWith: "Đọc thành “gi/d” tiếng Việt, cuối từ đọc “ét”: age → ây-ét.", examples: ["job", "major", "age", "bridge"]),
    ]

    static let others: [IPASound] = [
        .init(id: "HH", group: .consonant, priority: .low,
              howTo: "Thổi hơi nhẹ từ cổ họng, như “h” tiếng Việt.", confusedWith: "Thường không gây hiểu nhầm.",
              examples: ["hot", "who", "behind", "house"]),
        .init(id: "M", group: .consonant, priority: .normal,
              howTo: "Mím môi, hơi ra đằng mũi; cuối từ giữ môi khép.", confusedWith: "Thường không gây hiểu nhầm.",
              examples: ["man", "summer", "come", "time"]),
        .init(id: "N", group: .consonant, priority: .normal,
              howTo: "Đầu lưỡi chạm lợi trên, hơi ra đằng mũi.", confusedWith: "Lẫn với /ŋ/ ở cuối từ: thin → thing.",
              examples: ["no", "dinner", "sun", "ten"]),
        .init(id: "NG", group: .consonant, priority: .normal,
              howTo: "Cuống lưỡi chạm vòm mềm như “ng” tiếng Việt; không thêm “g” phía sau.",
              confusedWith: "Lẫn với /n/: thing → thin.", examples: ["sing", "long", "thinking", "english"]),
        .init(id: "L", group: .consonant, priority: .high,
              howTo: "Đầu lưỡi chạm lợi trên; ở cuối từ vẫn giữ lưỡi chạm lợi (“l tối”), đừng bỏ.",
              confusedWith: "Bỏ “l” cuối hoặc đọc thành “ô/u”: feel → fi, people → pi-pô; lẫn với /n/ ở đầu từ.",
              examples: ["light", "hello", "feel", "people"]),
        .init(id: "R", group: .consonant, priority: .normal,
              howTo: "Lưỡi cong lên phía sau, KHÔNG chạm vòm và không rung; môi hơi tròn.",
              confusedWith: "Đọc thành “r” rung hoặc “z” tiếng Việt, lẫn với /l/: right → light.", examples: ["red", "very", "car", "sorry"]),
        .init(id: "W", group: .consonant, priority: .normal,
              howTo: "Môi tròn chu như “u” rồi lướt nhanh sang nguyên âm sau.", confusedWith: "Đọc thành /v/: west → vest.",
              examples: ["we", "one", "quick", "away"]),
        .init(id: "Y", group: .consonant, priority: .low,
              howTo: "Như “d” giọng miền Nam hoặc “i” lướt: lưỡi cao rồi trượt sang nguyên âm.",
              confusedWith: "Thường không gây hiểu nhầm.", examples: ["yes", "you", "use", "million"]),
    ]
}

// MARK: - Screen "Âm tiếng Anh"

struct SoundsView: View {
    let store: SoundStore
    @State private var open: IPASound?
    @State private var lab: ContrastSet?

    var body: some View {
        Group {
            if let lab {
                SoundLabView(set: lab, store: store) { withAnimation(.smooth) { self.lab = nil } }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let open {
                SoundLesson(sound: open, practise: { set in withAnimation(.smooth) { self.open = nil; lab = set } }) {
                    withAnimation(.smooth) { self.open = nil }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                chart.transition(.opacity)
            }
        }
        .navigationTitle(lab.map { "Luyện âm: \($0.title)" } ?? open.map { "Âm /\($0.symbol)/" } ?? "Âm tiếng Anh")
        .problemBanner(store.problem)
        .task {
            guard let id = DebugArgs.value("--open") else { return }
            open = IPASound.sound(id)
            lab = ContrastSet.set(id)
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Luyện âm — nghe rồi nói").font(.title3.weight(.semibold))
                Spacer()
                if let next = store.next {
                    Button { withAnimation(.smooth) { lab = next } } label: { Label("Luyện tiếp: \(next.title)", systemImage: "play.fill") }
                        .buttonStyle(.glassProminent)
                }
            }
            Text("Mỗi lượt: 10 câu nghe phân biệt (nhiều giọng) rồi 10 câu nói. Đạt khi nói đúng từ 80% sau ít nhất 10 lần.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(ContrastSet.all) { set in
                let s = store.stats[set.id]
                Button { withAnimation(.smooth) { lab = set } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: s?.passed == true ? "checkmark.seal.fill" : set.priority == .high ? "star.fill" : "circle")
                            .foregroundStyle(s?.passed == true ? .green : set.priority == .high ? .orange : .secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.title).font(.headline)
                            Text(set.why).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        if let s, s.said > 0 {
                            Text("nói đúng \(Int((s.saidRate * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(set.title)\(s?.passed == true ? ", đã đạt" : set.priority == .high ? ", ưu tiên" : "")")
                .accessibilityHint(set.why)
            }
        }
    }

    private var chart: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Các âm tiếng Anh (giọng Mỹ)").font(.largeTitle.weight(.bold))
                    Text("Ký hiệu IPA ở đây giống hệt ký hiệu trên thẻ từ. Học các âm “Ưu tiên” trước: đó là những âm người Việt hay nói sai nhất và làm người nghe khó hiểu nhất.")
                        .foregroundStyle(.secondary)
                }
                if let next = store.next {
                    Button { withAnimation(.smooth) { lab = next } } label: { Label("Luyện âm tiếp: \(next.title)", systemImage: "play.fill") }
                        .buttonStyle(.glassProminent)
                }
                ForEach(IPASound.Group.allCases) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.rawValue).font(.title3.weight(.semibold))
                        let sounds = IPASound.all.filter { $0.group == group }
                        if group == .pair {
                            // voiceless and voiced side by side, always: /p/ /b/, /t/ /d/ …
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 10) {
                                ForEach(IPASound.pairs(sounds), id: \.0.id) { a, b in
                                    HStack(spacing: 6) { tile(a); tile(b) }
                                        .accessibilityElement(children: .contain)
                                }
                            }
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                                ForEach(sounds) { sound in tile(sound) }
                            }
                        }
                    }
                }
                practice
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func tile(_ sound: IPASound) -> some View {
        Button { withAnimation(.smooth) { open = sound } } label: {
            VStack(spacing: 4) {
                Text("/\(sound.symbol)/").font(.system(size: 30, weight: .semibold, design: .serif))
                Text(sound.examples[0]).font(.callout).foregroundStyle(.secondary)
                Text(sound.priority == .high ? "Ưu tiên" : " ").font(.caption2.weight(.bold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(sound.priority == .high ? Color.orange.opacity(0.18) : .clear, in: Capsule())
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(sound.priority == .high ? Color.orange.opacity(0.4) : Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Âm \(sound.symbol), ví dụ \(sound.examples[0])\(sound.priority == .high ? ", ưu tiên" : "")")
    }
}

struct SoundLesson: View {
    let sound: IPASound
    var practise: ((ContrastSet) -> Void)?   // nil inside the lab's sheet
    var backTitle = "Tất cả các âm"
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BackButton(title: backTitle, action: back)
                HStack(alignment: .center, spacing: 18) {
                    Text("/\(sound.symbol)/").font(.system(size: 64, weight: .semibold, design: .serif))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sound.group.rawValue).font(.headline).foregroundStyle(.secondary)
                        if sound.priority == .high { Label("Ưu tiên cho người Việt", systemImage: "star.fill").foregroundStyle(.orange) }
                        if sound.priority == .low { Label("Luyện sau: ít ảnh hưởng việc được hiểu", systemImage: "arrow.down.circle").foregroundStyle(.secondary) }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Cách phát âm", systemImage: "mouth").font(.headline)
                        Text(sound.howTo).font(.title3)
                        Divider()
                        Label("Người Việt hay nhầm", systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(.orange)
                        Text(sound.confusedWith)
                    }
                }
                if let practise, let set = ContrastSet.sets(for: sound.id).first {
                    Button { practise(set) } label: { Label("Luyện âm này: \(set.title)", systemImage: "mic.fill") }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
                Text("Ví dụ").font(.title3.weight(.semibold))
                ForEach(sound.examples, id: \.self) { word in
                    HStack(spacing: 14) {
                        SpeakButton { Speaker.speak(word, language: Locale.Language(identifier: "en-US")) }
                        Text(word).font(.title2.weight(.semibold))
                        Text(Self.highlighted(word, sound)).font(.title3)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// "/ʃɪp/" with the lesson's sound in the accent colour.
    static func highlighted(_ word: String, _ sound: IPASound) -> AttributedString {
        var out = AttributedString("/")
        for phone in Pronunciation.phones(word) ?? [] {
            var piece = AttributedString(Pronunciation.symbol(phone))
            if sound.matches(phone) {
                piece.foregroundColor = .parley
                piece.font = .title3.bold()
            } else {
                piece.foregroundColor = .secondary
            }
            out += piece
        }
        out += AttributedString("/")
        return out
    }
}
