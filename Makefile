# Full Xcode is required (Command Line Tools lack the SwiftUI / FoundationModels macro plugins).
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
# GNU Make 3.81 does not pass exported variables to $(shell): name the Xcode explicitly.
SWIFT_FLAGS := -Xswiftc -warnings-as-errors $(shell DEVELOPER_DIR=$(DEVELOPER_DIR) scripts/link-flags.sh)

.PHONY: build test ci offline-guard defaults-guard wiring-guard sandbox-app app run install pipeline ai-eval bench shot shot-test

SHELL := /bin/bash
build:            ## release build; warnings are errors (also concurrency warnings the flag lets through)
	mkdir -p .build && set -o pipefail; swift build -c release $(SWIFT_FLAGS) 2>&1 | tee .build/build.log
	@! grep -n 'warning:' .build/build.log || (echo "build warnings (see above) — fix them"; exit 1)
	@[ -n "$(findstring platform_version,$(SWIFT_FLAGS))" ] || { echo "scripts/link-flags.sh failed"; exit 1; }
	@scripts/check-sdk.sh .build/release/Parley

test:             ## unit tests (Swift Testing); default stores point at a temp folder, never ~/Documents/Parley
	PARLEY_DATA_DIR="$$(mktemp -d "$${TMPDIR:-/tmp}/parley-test.XXXXXX")" swift test $(SWIFT_FLAGS)

wiring-guard:     ## call sites use the tested decisions (PARLEY-20 pronunciation, PARLEY-21 translation end, PARLEY-22 readings, PARLEY-26 auto-translate, PARLEY-31 mic)
	@grep -q 'if Self.recordsPronunciation(from: s, kept: kept, source: sourceLocale)' Sources/Parley/Model.swift || (echo "Model.start must gate pronunciation.record with recordsPronunciation"; exit 1)
	@grep -q '            finish(for: mine)' Sources/Parley/Translate.swift && grep -q '                cancelled(for: mine)' Sources/Parley/Translate.swift || (echo "TranslatePad.run must end through finish(for:) / cancelled(for:) (PARLEY-21)"; exit 1)
	@grep -q 'if let ruby = TranslatePad.shownReading(pair, enabled: showReadings)' Sources/Parley/Translate.swift || (echo "TranslateScreen must draw readings through TranslatePad.shownReading (PARLEY-22)"; exit 1)
	@grep -q 'if pad.hasReadings {' Sources/Parley/Translate.swift || (echo "TranslateScreen must show the Cách đọc toggle when pad.hasReadings (PARLEY-22)"; exit 1)
	@grep -q 'await pad.autoTranslate(after: TranslatePad.autoDelay, source: source, target: target, supported: supported,' Sources/Parley/Translate.swift && grep -q 'busy: pad.busy' Sources/Parley/Translate.swift || (echo "TranslateScreen must auto-translate through TranslatePad.autoTranslate, re-run when busy changes (PARLEY-26)"; exit 1)
	@grep -q 'ready: { !Self.composing() })' Sources/Parley/Translate.swift || (echo "TranslateScreen must wait while an input method is converting (PARLEY-26)"; exit 1)
	@grep -q 'Self.announcement(for: phase, automatic: pad.automatic)' Sources/Parley/Translate.swift || (echo "TranslateScreen must announce automatic requests quietly (PARLEY-26)"; exit 1)
	@for f in Practice Pronunciation Listening Conversation; do grep -q 'await mic.listen(' Sources/Parley/$$f.swift || { echo "$$f.swift must use the one-press mic (mic.listen, PARLEY-31)"; exit 1; }; done
	@for f in Practice Pronunciation Listening Conversation; do grep -q '.micLevel(mic' Sources/Parley/$$f.swift && grep -q 'MyVoiceButton(mic: mic)' Sources/Parley/$$f.swift || { echo "$$f.swift: level ring and own-voice replay on every mic (PARLEY-31)"; exit 1; }; done
	@grep -q 'cap: MicCheck.wordCap' Sources/Parley/Practice.swift && grep -q 'cap: MicCheck.wordCap' Sources/Parley/Pronunciation.swift && grep -q '.micLevel(mic, active: listening)' Sources/Parley/Pronunciation.swift && grep -q 'mic.reset()' Sources/Parley/Practice.swift && grep -q 'if mic.permissionDenied { MyVoiceButton(mic: mic) }' Sources/Parley/Listening.swift || (echo "mic caps, per-row ring, per-card reset and 'Mở Cài đặt' before a result (PARLEY-31)"; exit 1)
	@[ "$$(grep -c 'MicCheck.clearAttempts()' Sources/Parley/App.swift)" = 2 ] || (echo "App.swift must clear learner recordings at launch and quit (PARLEY-31)"; exit 1)
	@grep -A1 'chosen = nil' Sources/Parley/Practice.swift | grep -q 'mic.reset()' && grep -A4 'index += 1' Sources/Parley/Listening.swift | grep -q 'mic.reset()' && grep -q 'cap: MicCheck.turnCap, quiet: MicCheck.turnQuiet' Sources/Parley/Conversation.swift && grep -q 'guard !mic.busy else { return }' Sources/Parley/Pronunciation.swift && grep -q '.shortcut(.space) { if let w = keyWord' Sources/Parley/Pronunciation.swift && grep -q '.keyboardShortcut(.space, modifiers: \[\])' Sources/Parley/Practice.swift && grep -q '.keyboardShortcut(.space, modifiers: .option)' Sources/Parley/Conversation.swift || (echo "mic: reset per card, conversation cap, busy guard and Space keys (PARLEY-31)"; exit 1)
	@grep -q 'let plan = Self.finish(text: text, error: error, current: mine == attempt)' Sources/Parley/Speaking.swift && grep -q 'if plan.discardRecording' Sources/Parley/Speaking.swift && grep -q 'let gate = Self.gate(allowed)' Sources/Parley/Speaking.swift && grep -q 'permissionDenied = gate.denied' Sources/Parley/Speaking.swift && grep -q 'attempt += 1' Sources/Parley/Speaking.swift && grep -q 'Speaker.stop() // the model voice' Sources/Parley/Speaking.swift || (echo "MicCheck.listen must go through finish / gate, stop the model voice and honour reset (PARLEY-31)"; exit 1)
	@grep -q 'guard !listening, !starting, !stopping else { return } // `pending` is listen() itself' Sources/Parley/Speaking.swift || (echo "MicCheck.start must not refuse its own listen() (pending) — the mic would never open (PARLEY-31)"; exit 1)
	@! grep -n 'mic.start(\|Task.sleep(for: .seconds([34]))' Sources/Parley/Practice.swift Sources/Parley/Pronunciation.swift Sources/Parley/Listening.swift Sources/Parley/Conversation.swift || (echo "no fixed mic windows: use mic.listen (PARLEY-31)"; exit 1)

offline-guard:    ## ADR 0001: no network code in the app
	@! grep -rnE 'URLSession|NSURLConnection|CFNetwork|NWConnection|NWListener|URLRequest|import Network|https?://' Sources/ || (echo "network code found (ADR 0001)"; exit 1)

defaults-guard:   ## PARLEY-13: settings always go through AppDefaults.store (never the owner's domain in a sandboxed run)
	@! grep -rn '@AppStorage(' Sources/ | grep -vE '@AppStorage\("[^"]+", store: AppDefaults\.store\)' || (echo "@AppStorage must name store: AppDefaults.store"; exit 1)
	@! grep -rnE 'defaultAppStorage\(\.standard|CFPreferences' Sources/ || (echo "settings must go through AppDefaults.store"; exit 1)
	@! grep -rnE 'UserDefaults(\(|\.standard)' Sources/ | grep -v 'AppDefaults.swift' || (echo "use AppDefaults.store"; exit 1)

ci: offline-guard defaults-guard wiring-guard build test

app: build        ## build/Parley.app (signed)
	./build.sh

run: app
	open build/Parley.app

install:          ## replace /Applications/Parley.app and launch it
	./build.sh install

pipeline: build   ## real speech recognition + translation on a synthesized file
	say -o "$${TMPDIR:-/tmp}/parley-t.aiff" "Good morning everyone, let's start the meeting."
	.build/release/Parley --file "$${TMPDIR:-/tmp}/parley-t.aiff"
	@if say -v '?' | grep -q '^Kyoko '; then \
	  say -v Kyoko -o "$${TMPDIR:-/tmp}/parley-ja.aiff" "おはようございます。今日の会議を始めましょう。" && \
	  .build/release/Parley --file "$${TMPDIR:-/tmp}/parley-ja.aiff" --source ja_JP --target vi; \
	else echo "pipeline: no Japanese voice (Kyoko) — Japanese run skipped"; fi

ai-eval: build    ## on-device model checks (needs Apple Intelligence; not in CI)
	.build/release/Parley --ai-eval

bench:            ## performance workloads (benchmarks/plan.md)
	PARLEY_BENCH=1 PARLEY_DATA_DIR="$$(mktemp -d "$${TMPDIR:-/tmp}/parley-test.XXXXXX")" swift test -c release $(SWIFT_FLAGS) --filter Bench

sandbox-app: app  ## build/Parley-sandbox.app: same app, bundle id com.david.parley.sandbox (screenshots and reviews)
	scripts/sandbox-app.sh

shot-test: sandbox-app ## shot.sh leaves other Parley instances alone and cleans up its own (needs a GUI session)
	scripts/shot-test.sh

shot: sandbox-app ## make shot ROUTE=progress NAME=progress [ARGS="--open x"]
	scripts/shot.sh $(ROUTE) $(NAME) $(ARGS)
