# Code review — `snig-17/gemma`

Reviewed at `6c0553d` ("firebase auth implementation - haven't tested yet"), ~5,100 lines of Swift / SwiftUI across 16 files.

**Caveat:** this container is Linux with no Swift toolchain, so nothing here was compiled or run. Every finding is from reading the source, the `.pbxproj`, and git history. Anything marked *build/runtime* needs confirming in Xcode.

---

## 0. Do this today, before anything else

### 0.1 Two Gemini API keys are in public git history — revoke both now

`gemma/TutoringViewModel.swift` held a hardcoded key in two commits before it was moved to the gitignored `Secrets.swift`:

| Commit | Line |
|---|---|
| `3afb861` | `gemma/TutoringViewModel.swift:24` |
| `580a2f3` | `gemma/TutoringViewModel.swift:25` |

To recover the two key values so you know which to revoke in the console, run locally:

```
git grep -nE 'AIzaSy[A-Za-z0-9_-]{20,}' 3afb861 580a2f3 -- gemma/TutoringViewModel.swift
```

(They are deliberately not reproduced in this file, which lives in the same public repo.)

The repo is public. Removing a secret in a later commit does not remove it from history — both keys are still fetchable by anyone who clones, and GitHub's public event firehose is scraped continuously for exactly this pattern. Assume both are compromised.

Order of operations:
1. Delete both keys in Google AI Studio / the GCP console. Do this first — rotation is the fix, history rewriting is cosmetic.
2. Check billing on the project for unexpected usage.
3. Create the replacement key with an API restriction (Generative Language API only) so a future leak is bounded.
4. Only then decide about history. `git filter-repo` plus a force-push would scrub it, but GitHub keeps unreferenced objects reachable for a while and forks keep their own copies, so this is tidying, not remediation.

### 0.2 `gemma/GoogleService-Info.plist` is committed

This one is less alarming — Firebase config is designed to ship inside the app bundle, and the `API_KEY` in it is an identifier, not a secret. **But** it only stays harmless if Firestore security rules and App Check are doing the actual access control, and neither is present in this repo (see 0.3). Right now that plist tells anyone the project ID and storage bucket.

### 0.3 No Firestore or Storage security rules anywhere in the repo

There is no `firestore.rules`, no `storage.rules`, no `firebase.json`. Every read and write goes through the client (`FirebaseService.swift`) straight to `users/{uid}/…`. If the project is still on the default test-mode rules, the entire database — names, roles, every tutoring transcript, every whiteboard image — is world-readable and world-writable to anyone with the project ID, which is in the committed plist.

Check the rules in the Firebase console now. The minimum is:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/{document=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

and the equivalent for Storage on `users/{userId}/drawings/{file}`. Commit both files to the repo so they are reviewable and deployable, rather than living only in a console someone can misclick.

### 0.4 The Gemini key ships inside the app binary

`TutoringViewModel.swift:27,143` reads `Secrets.geminiAPIKey` and puts it in the query string of a request made from the device. `SpeechService.swift:36,278` does the same for Cloud TTS. A compiled key in an IPA is extractable with `strings` in about ten seconds — gitignoring `Secrets.swift` keeps it off GitHub but not out of the app.

Consequence for a paid product: unmetered spend on your key, attributable to you, with no per-user limit and no way to cut off one abuser. Every model call has to move behind a server you control (Cloud Functions / Cloud Run is the shortest path given Firebase is already here) which checks the Firebase ID token, enforces a per-user daily cap, and holds the key. This is the single largest piece of work implied by this review and it is not optional for anything with a bill attached.

---

## 1. Blocking — this cannot work or ship as configured

### 1.1 Sign in with Apple has no entitlement *(build/runtime)*

`AuthView.swift` + `FirebaseService.signInWithApple` are implemented correctly, but there is no `.entitlements` file in the repo and no `CODE_SIGN_ENTITLEMENTS` in either build configuration of `project.pbxproj`. `ASAuthorizationController` requires the `com.apple.developer.applesignin` entitlement; without it, authorization fails at runtime rather than at build time. Given the commit message says "haven't tested yet", this is very likely the first thing you'll hit.

Fix: in Xcode, target → Signing & Capabilities → + Capability → Sign in with Apple. Commit the generated `gemma.entitlements`. Also confirm Apple is enabled as a provider in Firebase Auth, with the Services ID and key configured.

### 1.2 The app installs on almost nothing

Both configurations set:

- `TARGETED_DEVICE_FAMILY = 2` — **iPad only.** It will not install on an iPhone, despite `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` being set and `ContentView` having a whole `compactLayout` branch for phone widths.
- `IPHONEOS_DEPLOYMENT_TARGET = 26.2` — only the newest iOS point release. Excludes essentially every device in the hands of a GCSE student.

For a hackathon demo on your own iPad, fine. For anyone else running it, `TARGETED_DEVICE_FAMILY = 1,2` and a deployment target two or three majors back. The PencilKit whiteboard genuinely is an iPad feature, but the voice tutor is not, and phone-only households are the majority of the market.

### 1.3 `fatalError("No authenticated user")` is a crash, not an error

`FirebaseService.swift:94-99`. Every Firestore and Storage call routes through this computed `uid`. `fatalError` is uncatchable — `try?` does not save you.

Concrete path: tap Sign Out in `LandingPageView.swift:298` while any of the fire-and-forget writes is in flight (`gemmaApp.swift:87`, `TutoringViewModel.swift:276,439,448,456,467,490`). `currentUser` goes nil, the task resumes, the app hard-crashes. Same on token expiry.

Make it `throws`:

```swift
private func requireUID() throws -> String {
    guard let uid = currentUser?.uid else { throw FirebaseServiceError.notAuthenticated }
    return uid
}
```

and let the call sites handle it. While you're there: `signOut()` doesn't clear `currentNonce`, so a stale nonce survives into the next sign-in attempt.

### 1.4 `maxOutputTokens: 300` will likely produce empty responses

`TutoringViewModel.swift:213`. The configured model is `gemini-3.1-flash-lite-preview`, from the 3.x family, where thinking tokens count against `maxOutputTokens`. A 300-token budget can be consumed entirely by thinking, returning a candidate with `finishReason: MAX_TOKENS` and **no `parts`**. The guard at `:228-240` then can't find `parts[0].text`, finds no `error` object either, and throws "Unexpected response format" — which surfaces to the student as *"I'm having trouble connecting. Please check your API key"*, a message that will send you debugging the wrong thing entirely.

Raise the budget substantially, set `thinkingConfig` explicitly, and handle `finishReason` and `promptFeedback.blockReason` as distinct cases with distinct messages. Also: pinning a `-preview` model in a hardcoded URL (`:28`) guarantees a silent outage the week it's withdrawn. Pin a stable model and make it configurable.

---

## 2. Real bugs

### 2.1 The latest user message is sent to Gemini twice

`TutoringViewModel.swift:56-68` appends the user's message to `messages`, *then* calls `callGemma`. In `performAPICall`, `messages.suffix(20)` at `:185` already contains that message, and `:204-207` appends it again as the current turn. Every request carries the newest message twice and ends with two consecutive `user` turns. Wasted tokens on every call, and a malformed conversation shape.

Fix: `messages.dropLast().suffix(20)`, or stop appending the current turn separately.

### 2.2 `TutoringViewModel` is reconstructed on every re-render

`ContentView.swift:26`: `self._viewModel = State(initialValue: TutoringViewModel(subject: subject))`.

SwiftUI calls a `View`'s `init` on every re-render of its parent. `State(initialValue:)` discards the surplus value, but the expression is still *evaluated* — so each re-render builds a whole `TutoringViewModel`, and its `init` (`:30-52`) fires `loadSessions()` and `loadFlashcards()` against Firestore and constructs a `SpeechService`, whose own `init` activates the shared `AVAudioSession`. `RootView` re-renders whenever `profile` or `flashcards` change, which is often.

So: duplicated Firestore reads you're billed for, multiple `SpeechService` instances fighting over one audio session, orphaned `PKCanvasView`s.

Fix: build the view model once in `RootView` (or a `@StateObject`-style holder keyed on the subject) and pass it in, rather than constructing it inside `init`.

### 2.3 A failed profile load silently overwrites the real profile with a blank one

`gemmaApp.swift:118-133`. On any thrown error — offline, a rules rejection, a decode failure — the `catch` sets `hasLoadedData = true` and leaves `profile` as the default `UserProfile()`, whose `hasCompletedOnboarding` is `false`. `RootView` then shows onboarding to an existing user, and `finishOnboarding` → `saveProfile()` writes the blank profile over the real one with `merge: true`. Name, role, subjects and streak gone.

Distinguish "no document" (→ onboarding) from "load failed" (→ retry or an error state that does *not* let a write proceed). This is the most likely way a real user loses their data.

### 2.4 Flashcards race, then get clobbered

Three writers to one list, in nondeterministic order:
- `TutoringViewModel.init` → `loadFlashcards()` → async `flashcards = loaded` (`:494-502`)
- `ContentView.onAppear` → `viewModel.flashcards = flashcards` (`ContentView.swift:44`)
- session end → `flashcards = updatedFlashcards`, wholesale replace (`gemmaApp.swift:64`)

Whichever lands last wins. If `onAppear` wins, the Firebase load is discarded and the session-end replace writes a truncated list back. Pick one owner for this list — given `RootView` already loads it, the view model shouldn't load it at all.

### 2.5 Every new session uploads an empty drawing

`createNewSession()` (`:404-413`) and `selectSession()` (`:415-422`) both call `saveDrawingToSession()` unconditionally. That method (`:270-278`) takes `canvasView.drawing.dataRepresentation()` — non-empty even for a blank canvas — sets `hasDrawing = true`, and uploads to Storage.

Result: every session is flagged as having a drawing, every session gets a junk blob in Storage, and `loadDrawingFromSession()` (`:383-400`) then does a pointless network download for each one. The Export button (`WhiteboardView.swift:184-189`) has the same shape: it calls `onSave()` before checking whether there's anything to export, so an empty canvas uploads a blob and *then* says "Nothing to Export".

Guard on `canvasHasStrokes` before saving.

### 2.6 The drawing indicator never appears for loaded sessions

`SessionHistoryView.swift:118` tests `session.drawingData != nil`. But `drawingData` is deliberately excluded from `CodingKeys` (`Models.swift:51-53`), so any session decoded from Firestore has `drawingData == nil` regardless. The pencil icon only ever shows for the session created in this process. Use `session.hasDrawing`.

### 2.7 "Delete Forever" doesn't delete

`LandingPageView.swift:84-95` promises *"permanently remove this subject and its stats"*. It removes the `Subject` from `profile.subjects` and saves the profile. Every session document, every message subcollection, and every drawing blob for that subject stays in Firestore and Storage forever, unreachable from the UI.

`FirebaseService.deleteSubject` exists (`:138-140`) and is never called — and even it only deletes the subject doc, not the sessions. For a product that will handle children's data, "delete" has to actually cascade; a promise in an alert that the backend doesn't honour is the kind of thing that turns into a real problem later.

Related: there is **no account deletion at all.** App Store Review Guideline 5.1.1(v) requires any app with account creation to offer in-app account deletion. This is a rejection, not a nit.

### 2.8 Flashcard saves break silently past 500 cards

`FirebaseService.saveFlashcards` (`:209-216`) rewrites *every* flashcard in one `WriteBatch` on every single change. Firestore caps a batch at 500 operations, so at 501 cards the commit throws — and every caller is `try? await` (`TutoringViewModel.swift:490`), so the throw is swallowed and flashcards simply stop persisting with no error anywhere.

Write only the changed card (`saveFlashcard` already exists, unused), and stop discarding errors with `try?` on writes that matter.

### 2.9 Firestore writes aren't actually awaited

`setData(from:merge:)` at `FirebaseService.swift:108,149,206,231` is the non-async overload — it returns as soon as the write hits the local cache, so the enclosing `async throws` never surfaces a server-side failure such as a rules rejection. Combined with `try?` at every call site, a write can fail server-side and nothing, anywhere, notices. Use the completion-based or async variants and propagate.

### 2.10 Nothing prevents concurrent model requests

`sendMessage` (`:56`) has no `isLoading` guard, and it's reachable from both the mic (`SpeechService.onFinalTranscript`, `:42-49`) and the Board button. Two in-flight calls append replies in completion order, interleaving the conversation and double-billing. Guard on `isLoading`, or cancel the in-flight `Task`.

### 2.11 TTS keeps playing after the user stops it

`SpeechService.speak` (`:245-269`) sets `speechState = .speaking` *before* awaiting `fetchGoogleTTSAudio`. If the student taps the mic during that window, `stopSpeaking()` sets `.idle` — then the fetch resolves and plays the audio anyway, over whatever happens next. Needs a generation counter or a cancellable `Task` stored on the service.

Two more in the same file:
- **Truncation is invisible.** `:276` cuts TTS input at 800 characters. The on-screen text is complete, the spoken answer stops mid-sentence. Google's limit is 5,000 bytes, so 800 is self-imposed; if you keep it, truncate at a sentence boundary.
- **The TTS key is probably the wrong kind of key.** `:278` calls `texttospeech.googleapis.com` with the Gemini key. An AI Studio key won't carry the Cloud TTS API, so this likely 403s every time and silently falls back to Apple TTS (`:265-267`) — meaning the voice you tuned isn't the voice shipping. Verify with one curl. If it *does* work, the leaked keys in §0.1 were billable Cloud TTS keys, which raises the stakes there.

### 2.12 The app seizes the audio session at launch

`SpeechService.init` → `prepareAudioSession()` (`:61-78`) sets `.playAndRecord` and activates the session immediately. Whenever a `SpeechService` is constructed — which per §2.2 is more often than you think — the app interrupts any music or podcast playing and lights the orange microphone indicator, before the student has touched the mic. Activate on demand in `startListening`/`speak`, and deactivate when leaving the tutoring screen.

### 2.13 The blink loop is unkillable and multiplies

`GemmaAvatarView.swift:479-492`: `startBlinkLoop()` reschedules itself through `DispatchQueue.main.asyncAfter` forever. There is no cancellation and no weak capture, and `onDisappear` (`:77-79`) only stops motion updates. Every `onAppear` — tab switch, rotation, re-render — starts another independent loop, and none of them ever stop. `startAnimations()` restacks the `repeatForever` animations the same way.

Also `startMotionTracking` (`:506-525`) runs CoreMotion at 30 Hz delivering to `.main` and calls `withAnimation` on every sample. That's a continuous main-thread animation transaction 30 times a second for an eye that moves three points. On a kid's iPad through an hour of revision, that's real battery.

Drive these from `TimelineView` or a cancellable `Task` tied to the view's lifetime, and drop motion to ~10 Hz without `withAnimation`.

### 2.14 The whiteboard canvas is owned by the wrong object

`TutoringViewModel.swift:17-18` holds the `PKCanvasView` and `PKToolPicker`, and `CanvasView.makeUIView` (`WhiteboardView.swift:20-46`) configures and returns that externally-owned instance. `makeUIView` is expected to create a fresh view; returning a shared one means a second representable (rotation between `landscapeLayout` and `portraitLayout`, or the `compactLayout` `TabView`) tries to adopt a view that already has a superview. `insertSubview` for the tag-999 background also runs again on each `makeUIView`, stacking duplicate 2048×4096 pattern views.

Speaking of which: `BackgroundPatternView` is 2048×4096 (~32 MB backing store) and its `draw(_:)` paints the whole pattern — the dotted case fills ~14,500 ellipses on the main thread per redraw. It also ignores `rect.origin` while using `rect.width/height`, so a partial dirty rect draws the pattern misaligned. Use a tiled `CGPattern` or a small repeating image.

### 2.15 Stale indices in the delete confirmation

`SessionHistoryView.swift:68-81` stores an `IndexSet` from `onDelete`, shows an alert, and applies it on confirm. `TutoringViewModel.deleteSession(at:)` (`:424-441`) then does `offsets.map { sessions[$0] }`. If `sessions` changed between the swipe and the confirm — the async `loadSessions()` landing, say — this deletes the wrong session or traps out of range. Capture session IDs, not offsets.

Also in that method: deleting the current session calls `selectSession(sessions[0])`, which calls `saveDrawingToSession()` and *uploads a drawing for the session being deleted*, racing the delete task that's trying to remove it. Orphaned blob.

### 2.16 Smaller things

- **Force-unwrapped URLs** — `TutoringViewModel.swift:143`, `SpeechService.swift:278`. A malformed key crashes rather than erroring.
- **Speech errors are never shown.** `GemmaCallView.errorOverlay` (`:274-286`) is defined and never placed in the hierarchy, so everything written to `speechService.errorMessage` — including "Speech recognition not authorized" — is invisible. The student just sees a mic that does nothing.
- **Mic can latch disabled.** The button is `.disabled(speechState == .processing)` (`:237`); the `silent: true` branch of `callGemma` (`:134-136`) returns without ever leaving `.processing`. That parameter is currently never passed as `true`, so it's latent — but it's a dead-end state with no recovery.
- **"N exchanges" counts every message**, user and model (`GemmaCallView.swift:93-95`), so it reads roughly double.
- **`print()` of full model responses** — `TutoringViewModel.swift:222-226` logs status and 500 characters of every response. `print` is not stripped in release; student conversation content goes to the device console. Use `Logger` with `#if DEBUG`, and never log response bodies in release.
- **Streak can stick at zero.** `UserProfile.recordActivity` (`:360-379`) leaves `streak` untouched when `daysDiff == 0`, so a profile with a same-day `lastActiveDate` and `streak == 0` stays at 0. Clamp to `max(streak, 1)`.
- **Non-deterministic subject order.** `OnboardingView.swift:320` maps a `Set<String>`, so subjects land in a different order every run.
- **No onboarding validation.** "Get Started" works with no role, no name, no subject selected (`:308-328`).
- **Dead code:** `FirebaseService.saveSubjects` / `loadSubjects` / `deleteSubject` / `saveFlashcard`, `SpeechService.onSpeechFinished` (declared, invoked, never assigned), `hasPermissions`, `WhiteboardView`'s `onSnapshot` (wired to `{}`), `callGemma(silent:)`. The **FirebaseDatabase** SPM product is linked (`project.pbxproj:14`) and never imported — drop it, it's binary size for nothing.
- **Exported PDFs accumulate** in `temporaryDirectory` (`:309`) and are never cleaned up. The filename is built from the session title — i.e. from the student's first message — with only `/` sanitised (`:308`); a title containing `..` traverses. Sandboxed and self-inflicted, so low impact, but use a UUID.
- **`hasDrawing` can go stale** — it's set in `TutoringSession.init` from `drawingData` (`Models.swift:61`) but not maintained when `drawingData` is assigned later. Make it a computed property or stop keeping both.
- **Nonce charset is missing `W`** (`FirebaseService.swift:82`) — inherited from Apple's own sample snippet, and 63 characters means `% charset.count` on a 256-value byte is very slightly biased. Harmless at 32 characters; mentioned only so it isn't mistaken for intent.

---

## 3. No safety net

No test target. No CI. No linter. `README.md` is one line, so a fresh clone gives a stranger (or you in six months) no hint that it won't compile until they copy `Secrets.swift.template` to `Secrets.swift`.

The highest-value tests here need no device and no network:
- `Flashcard.parseFlashcards` — malformed tags, `]` inside the `back:` text, multiple tags, no tags.
- `UserProfile.recordActivity` — the streak transitions, including the zero case above.
- `GemTier.tier(forMessages:)` — the boundaries.
- The Gemini request builder, once it's extracted from `performAPICall` — the duplicate-message bug in §2.1 is exactly what a two-line test catches.

A GitHub Actions workflow on `macos-latest` running `xcodebuild test` would also have caught §1.1 and §1.2 the moment they were introduced.

---

## 4. Against the aim: a paid tutoring product for GCSE students

The engineering above is fixable in a week or two. This part isn't, and it's what actually decides whether this codebase can become a business.

**There is no age gate and no parental consent, anywhere.** The app asks a child to self-identify as "GCSE" (`Models.swift:69-81`), takes their name and email through Apple Sign In (`AuthView.swift:41`), records every tutoring transcript, and uploads photographs of their handwriting. For UK users under 13 that needs a parent's consent under UK GDPR Article 8, and the ICO's Age Appropriate Design Code applies to the whole design, not just the privacy policy. There's no privacy policy, no consent record, no data-retention policy, and — per §2.7 — no working erasure.

This is precisely the gap the new web build closes with its parent-creates-account / student-gets-a-code-and-PIN flow, and it's the strongest single argument that the web build, not this one, is the product.

**Three more things this codebase doesn't have that a paid product can't skip:**

- **Safeguarding.** A child talking to a tutor at 1am will eventually say something about self-harm, abuse, or an eating disorder. There's no distress detection and no escalation path — it goes to Gemini as maths homework. The web build's fixed Childline response is the right pattern. For a product aimed at minors this is table stakes, not a nice-to-have, and it's the first thing a school or a careful parent will ask about.
- **Cost control.** Per §0.4 the key is in the binary and there is no per-user cap. One leaked build is an unbounded bill.
- **No safety settings or blocked-response handling** on the Gemini call. `safetySettings` is absent and `promptFeedback.blockReason` is never read, so a blocked response surfaces as "check your API key".

**And the pedagogy isn't in the code yet.** The system prompt (`TutoringViewModel.swift:149-169`) asks for guiding questions, but never forbids giving the answer — so when a student says "just tell me", it will. Nothing maps a response to an AQA specification point; nothing tracks a misconception across sessions; the `GemTier` ladder rewards raw message count (`Models.swift:261-268`), which rewards chatting rather than learning, and parents don't pay for chatting.

The web build's learner record — mastery per topic, coded misconceptions, resolution tracking — is the thing a parent would actually pay for, because it's the thing a £40/hour tutor produces that a chatbot doesn't. That asset lives in the other codebase.

### The call

Don't port this. Treat `gemma` as what it is: the hackathon artifact that proved the interaction, and a reference for two things the web build doesn't have — the PencilKit whiteboard as a maths input surface, and the voice loop. Those are worth revisiting as an iPad companion once there are paying users, not before.

What carries forward is narrow and worth being precise about: the whiteboard-as-input idea, the "show me your working" interaction, and the finding that students will talk to a tutor they can see. Everything else — auth model, data model, persistence, prompt — is superseded.

Whatever you decide about the code, §0.1 through §0.3 are live right now, on a public repo, on a project that may be holding real data behind default rules. Those don't wait on the strategy.
