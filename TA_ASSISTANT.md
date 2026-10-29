# Textream TA Assistant (macOS)

This fork adds a switchable office-hours assistant using your own OpenAI API key.

## Get this version

```sh
git clone https://github.com/George121380/textream.git
cd textream
open Textream/Textream.xcodeproj
```

Select the **Textream** macOS scheme, choose **My Mac**, configure your own signing team if needed, and build with **Command-R**. The upstream macOS application requires macOS 15+ and Xcode 16+; Xcode 26 is recommended for this combined macOS/iOS project. Xcode 14 cannot build the full project. The original Homebrew/App Store downloads do not include this fork's changes.

## Use it

1. Open **TA Assistant → Open TA Assistant…** (Command-Shift-A).
2. Expand **Setup** and save your OpenAI API key. It is saved in this Mac's Keychain, not the repository. Each person cloning this fork enters their own key. API usage is billed separately from a ChatGPT subscription.
3. Pick the speech language and reply language, and optionally paste course definitions, reference notes or examples. The default model is `gpt-5.4-mini`; the model ID is editable.
4. Turn on **Enable TA assistant**. Allow Speech Recognition and Screen & System Audio Recording when macOS asks. Depending on macOS, you may need to quit and reopen the app after granting access.
5. Play the meeting audio normally, including through headphones. The question appears in **Question / live transcript**. With **Auto reply after a pause** on, a pause of 1.8 seconds starts a draft; adjust the pause from 1 to 5 seconds.
6. The suggested answer streams into the assistant window. Review it, read it aloud, copy it manually, or choose **Read in prompter** to display it in Textream's existing overlay. This pauses meeting transcription to avoid two competing speech recognizers; resume audio from the assistant when ready.

You can switch off automatic replies and use **Generate reply** when the full question is ready. Typing or correcting a question pauses audio so speech cannot overwrite your edit. **New student** cancels work and clears conversational context. Closing the assistant stops capture and requests and clears the conversation.

## Scope and data

- Captures **all Mac playback**, not just Zoom/Meet, and excludes this application's own output. The microphone is not connected to the assistant. Close unrelated audio. This is not speaker diarization; system playback can still contain a recording of your own voice or shared videos.
- A pause is only a timing heuristic. It cannot reliably distinguish a finished question from a pause within a sentence. Use manual generation or a longer pause when needed.
- Audio goes to Apple's speech recognition; on-device recognition is requested when supported, otherwise Apple may process it. No screen frames are consumed or sent to GPT.
- The recognized question (up to 8,000 characters), course notes (first 16,000 characters), and at most the last three successful Q/A turns are sent to `https://api.openai.com/v1/responses` over HTTPS. No other endpoint or redirect receives the key. The client sends `store: false`; this does not promise zero retention under all provider policies.
- Transcript, replies and notes stay in app memory. Course notes survive closing/reopening the panel within the same app session; conversations do not. Model and language preferences are saved locally.
- Responses are drafts. Nothing is posted to meeting chat or sent to students automatically. The assistant window can appear in screen sharing; share the course window instead of the entire desktop when appropriate.
- Failed calls are not automatically retried. HTTP authentication/quota errors and interrupted or incomplete streams are surfaced in the UI; visible text after an error may be partial.

## Validation

The full universal macOS app (Apple Silicon and Intel) and all 36 mock regression checks passed with Xcode 26.3 in [GitHub Actions](https://github.com/George121380/textream/actions/runs/40813211932). The tested application sources are from commit `638a711`.

The [TA Assistant checks workflow](https://github.com/George121380/textream/actions/workflows/ta-checks.yml) repeats these checks for relevant pushes and pull requests, and can also be run manually. Each successful run keeps validation logs and a `Textream-TA-unsigned` test artifact for seven days. This artifact is unsigned and not notarized; a successful build does not verify local permissions, audio capture, or a real OpenAI response.

The four new feature files compile together against the installed macOS SDK. The regression checks exercise UTF-8/SSE framing, error events, request destination and storage settings, bounded context, cancellation, stale results, debounce, missing keys, and new-student resets. They use mocks, with no network, audio or Keychain access.

Run from the repository root:

```sh
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  Textream/Textream/TA*.swift TARegressionTests.swift \
  -o /tmp/textream-ta-tests
/tmp/textream-ta-tests
```

The test executable targets macOS 13 solely to check the standalone feature with older toolchains. It does not change the full app's macOS 15 requirement.

Before using this for a live session, build the full app with a supported Xcode, configure a key, and check: real meeting audio/transcription in both languages; permissions denied/revoked; an actual API response; switching off while generating; and the existing prompter's display/reading behavior. These hardware and live API checks have not been performed in this development environment.

## Files

- `TAMeetingCapture.swift`: ScreenCaptureKit audio and Apple speech recognition, with recognizer rotation.
- `TAResponseClient.swift`: Keychain storage, bounded Responses requests and cancellable SSE streaming.
- `TAAssistantModel.swift`: lifecycle, pause detection, conversation and cancellation guards.
- `TAAssistantView.swift`: floating assistant window and setup.
- `TextreamApp.swift`: menu entry and existing-overlay integration.
- `TARegressionTests.swift`: executable regression suite outside the app target.

The Xcode macOS target uses a synchronized source folder, so the new files are included automatically. The iOS app is unchanged. Upstream licensing and attribution are preserved.
