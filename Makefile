# Full Xcode is required (Command Line Tools lack the SwiftUI / FoundationModels macro plugins).
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SWIFT_FLAGS := -Xswiftc -warnings-as-errors

.PHONY: build test ci offline-guard app run install pipeline ai-eval bench shot

build:            ## release build of the executable, warnings are errors
	swift build -c release $(SWIFT_FLAGS)

test:             ## unit tests (Swift Testing); default stores point at a temp folder, never ~/Documents/Parley
	PARLEY_DATA_DIR="$$(mktemp -d "$${TMPDIR:-/tmp}/parley-test.XXXXXX")" swift test $(SWIFT_FLAGS)

offline-guard:    ## ADR 0001: no network code in the app
	@! grep -rnE 'URLSession|NSURLConnection|CFNetwork' Sources/ || (echo "network code found (ADR 0001)"; exit 1)

ci: offline-guard build test

app: build        ## build/Parley.app (signed)
	./build.sh

run: app
	open build/Parley.app

install:          ## replace /Applications/Parley.app and launch it
	./build.sh install

pipeline: build   ## real speech recognition + translation on a synthesized file
	say -o "$${TMPDIR:-/tmp}/parley-t.aiff" "Good morning everyone, let's start the meeting."
	.build/release/Parley --file "$${TMPDIR:-/tmp}/parley-t.aiff"

ai-eval: build    ## on-device model checks (needs Apple Intelligence; not in CI)
	.build/release/Parley --ai-eval

bench:            ## performance workloads (benchmarks/plan.md)
	PARLEY_DATA_DIR="$$(mktemp -d "$${TMPDIR:-/tmp}/parley-test.XXXXXX")" swift test -c release --filter Bench

shot: app         ## make shot ROUTE=progress NAME=progress [ARGS="--open x"]
	scripts/shot.sh $(ROUTE) $(NAME) $(ARGS)
