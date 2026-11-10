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

wiring-guard:     ## PARLEY-20: the mic → "Phát âm của tôi" call site uses the tested decision
	@grep -q 'if Self.recordsPronunciation(from: s, kept: kept, source: sourceLocale)' Sources/Parley/Model.swift || (echo "Model.start must gate pronunciation.record with recordsPronunciation"; exit 1)

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
	PARLEY_DATA_DIR="$$(mktemp -d "$${TMPDIR:-/tmp}/parley-test.XXXXXX")" swift test -c release $(SWIFT_FLAGS) --filter Bench

sandbox-app: app  ## build/Parley-sandbox.app: same app, bundle id com.david.parley.sandbox (screenshots and reviews)
	scripts/sandbox-app.sh

shot-test: sandbox-app ## shot.sh leaves other Parley instances alone and cleans up its own (needs a GUI session)
	scripts/shot-test.sh

shot: sandbox-app ## make shot ROUTE=progress NAME=progress [ARGS="--open x"]
	scripts/shot.sh $(ROUTE) $(NAME) $(ARGS)
