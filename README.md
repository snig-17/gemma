# gemma

Hackathon iOS app (SwiftUI, iPad): a voice AI tutor with a PencilKit whiteboard, Firebase auth and persistence.

## Contents

| Path | What it is |
|---|---|
| `gemma/`, `*.swift` at root | the iOS app |
| `CODE_REVIEW.md` | review of the app at `6c0553d` — read §0 first, it covers credential exposure |
| `docs/DESIGN.md` | design for a coverage-aware adaptive GCSE platform (not built; separate product) |

## Building the app

Requires Xcode and a Firebase project.

1. Copy `gemma/Secrets.swift.template` to `gemma/Secrets.swift` and add a Gemini API key. The project will not compile without this file; it is gitignored.
2. Open `gemma.xcodeproj`. Dependencies resolve via SPM (firebase-ios-sdk 12.10.0).

Known blockers, both detailed in `CODE_REVIEW.md`: Sign in with Apple is implemented without its entitlement, and the target is configured iPad-only on iOS 26.2.
