# Testing

| Layer | Tool | Where | Run |
| --- | --- | --- | --- |
| Unit (logic, stores, parsers, scoring) | Swift Testing | `Tests/ParleyTests/*.swift` | `make test` |
| Pipeline (speech recognition + translation on a real file) | `Parley --file` | `Sources/Parley/App.swift` `selfTest` | `make pipeline` |
| On-device AI | `Parley --ai-eval` | per feature | `make ai-eval` (needs Apple Intelligence) |
| UI | screenshots with seeded data, looked at | `scripts/shot.sh` | `make shot ROUTE=… NAME=…` |
| Performance | Swift Testing suites named `Bench…` | `Tests/ParleyTests` | `make bench` |

Rules: tests write only to `TestData.file(_:)` temp folders; stores take a `file:` URL for that. A UI item is not done
until its screenshot has been looked at (sample data). SwiftPM cannot run XCUITest, so UI behaviour is kept in
testable view models / static functions and the screens are checked by screenshot and a manual click-through.
