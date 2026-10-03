# Passaggio

An iPhone app that turns recorded singing lessons into study notes, a practice routine and practice audio.

- **Lessons**: import Voice Memos recordings, play them back on a scrubbable waveform, and keep notes per lesson.
- **Key points**: the lesson is transcribed with speaker labels (OpenAI `gpt-4o-transcribe-diarize`). Only your teacher's speech goes to a language model, which pulls out their feedback and groups it into seven themes (breath support, registration and mix, placement and resonance, vowels, tension and bad habits, range, repertoire). Tapping a point plays the lesson from that moment. A lesson's **Style** (Details tab) is Singing by default. Set it to Screaming for harsh-vocals lessons: they add an eighth theme, distortion and texture, and treat constriction or distortion the teacher asks for as technique, not a bad habit. Singing lessons get exactly the same prompts either way, and the two styles keep separate recurring topics.
- **Insights**: shows which corrections recur across lessons, most-repeated first.
- **Practice**: builds 15-, 30- or 45-minute routines weighted toward recurring and recent feedback. Each exercise is linked to the moments your teacher said it and can carry a practice track. There's a full-screen practice mode with a timer, and you can mark sessions done.
- **Tracks**: a piano exercise generator on the phone (scales, arpeggios, octave slides and custom sequences; a root-chord cue before each repetition; presets for your D#2–G#4 range and the C4–F#4 passaggio). Also looping clips cut from lessons, typically your teacher playing an exercise.
- **Help**: a step-by-step guide to every feature, searchable, under **Settings › How to Use Passaggio**.

Your teacher's feedback is the authority. Every prompt tells the model to organise and quote what the teacher said and never to add technique or advice of its own (`FeedbackAnalyst.principles(for:)` in `Packages/PassaggioCore/Sources/PassaggioCore/Notes/FeedbackAnalyst.swift`).

> **Build status.** The app builds with Xcode 27 and Swift 6.4, and `make test` passes: 83 `PassaggioCore` tests and 10 app tests on the simulator (backup round trip, lesson styles, rendering, clip export, Keychain, model settings, help guide). `VERIFY.md` is the on-device checklist for the parts tests can't cover, such as real API calls and the Voice Memos share route.
>
> See [ROADMAP.md](ROADMAP.md) for planned features.

## Requirements

- A Mac with Xcode 26 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- iPhone 16 Pro on iOS 27 or later. The deployment target is set once in `project.yml` (`deploymentTarget.iOS`). `make doctor` checks it against your installed SDK. If your phone runs a newer iOS, you can raise the target to match.
- A free Apple ID (Personal Team). No paid developer account is needed.
- An OpenAI API key. An Anthropic key is optional.

## Install with a free Apple ID

1. In Xcode, open **Settings › Accounts**, click **+ › Apple ID** and sign in. A "Personal Team" appears. To find its Team ID, select the team and click **Manage Certificates**, or run `make bootstrap`, open the project, and read it from **Signing & Capabilities**.
2. In this folder:
   ```sh
   make bootstrap TEAM_ID=ABCDE12345   # writes Config/Local.xcconfig, generates Passaggio.xcodeproj
   open Passaggio.xcodeproj
   ```
3. Connect the iPhone and trust the Mac. On the phone, turn on **Settings › Privacy & Security › Developer Mode** (the phone restarts).
4. In Xcode, select the **Passaggio** scheme and your iPhone, then press **Run** (⌘R).
5. The first launch is blocked until you trust your certificate: **Settings › General › VPN & Device Management › Apple Development: your Apple ID › Trust**.

Command-line equivalent: `make build-device TEAM_ID=ABCDE12345` builds and signs. Install from Xcode (Run), or with `xcrun devicectl device install app --device <UDID> build/DerivedData/Build/Products/Debug-iphoneos/Passaggio.app`.

### Reinstalling every 7 days

Free-provisioning profiles expire after 7 days, and then the app won't open. **Your data isn't lost**: connect the phone and press **Run** in Xcode again. The bundle identifier is fixed (`sg.cloudy3.passaggio`, in `Config/Base.xcconfig`), so the new build replaces the old one in place and keeps its database and recordings.

- Don't delete the app from the phone to "fix" an expired install. Deleting it erases its data.
- Keep the bundle identifier the same forever. If Xcode ever says it's unavailable, change it once in `Config/Base.xcconfig` and restore from a backup.
- Free accounts are limited to a few app IDs per week. Reinstalling the same app doesn't use a new one.
- Make a backup (below) before anything you're unsure about.

## Getting recordings out of Voice Memos

**Route A: share straight to Passaggio.** Passaggio registers as an "Open in" handler for `.m4a`/audio files (`CFBundleDocumentTypes` in `Info.plist`). That needs no entitlement, so it works with Personal Team signing. In Voice Memos, tap a recording, then **⋯ › Share**, and look for **Passaggio** in the app row (you may need **More** at the end of the row). Passaggio opens and imports the file.

> I couldn't check on a device whether Voice Memos' share sheet lists third-party "Open in" handlers for its recordings. Recent iOS versions do list them for audio files shared from Files. If Passaggio isn't offered, use route B.

**Route B: through Files (always works).**
1. Voice Memos: **⋯ › Share › Save to Files**, and pick a folder (iCloud Drive or On My iPhone). You can select several memos and share them together.
2. Passaggio: **Lessons › +**, then pick the file(s). Multiple selection is supported.

The lesson date comes from the recording's embedded creation date (Voice Memos writes one), falling back to the file's date. You can edit it in the lesson's **Details** tab.

## Adding your API key

**Settings › OpenAI API Key**: paste the key and tap **Save to Keychain**. The key is stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. It never appears in source code or UserDefaults and isn't included in backups, so re-enter it after restoring to another phone.

Transcription always uses OpenAI. For key points and routines you can choose **OpenAI** (default model `gpt-6.1-sol`) or **Anthropic** (default model `claude-opus-5`, which needs an Anthropic key). Both model names are editable. The defaults were checked against each provider’s docs in October 2026. If you had saved an earlier default in Settings, it moves to the new one; a model name you typed yourself is kept.

## Mark your voices once

Open any lesson and choose **⋯ › Mark Teacher's Voice…**. Select 2–10 seconds where only your teacher is speaking (no piano, no singing), then save. Do the same with **Mark My Voice…**. The clips are sent with every transcription request (`known_speaker_names[]` / `known_speaker_references[]`), so segments come back labelled "teacher" and "me" consistently across chunks and lessons.

If you skip this, lessons come back with anonymous speakers (A, B…). The lesson's Key Points tab then asks you which one is your teacher.

## Backing up and restoring

There's no iCloud sync under free provisioning, so back up regularly, and always before a macOS or Xcode reinstall.

- **Back up**: tap **Settings › Back Up to Files…**, then choose a location such as iCloud Drive. This writes one `Passaggio-YYYYMMDD-HHMM.passaggiobackup` file containing every recording, transcript, key point, topic, clip, generator preset, routine, practice session and voice sample.
- **Restore**: tap **Settings › Restore from Backup…** and pick the file, or tap the file in the Files app and share it to Passaggio. You'll see the backup's date and contents and confirm before anything is replaced. Restore *replaces* everything currently in the app.

The format is a plain POSIX tar file: `data.json` plus `recordings/` and `references/` folders. You can inspect it on a Mac with `tar -tvf`.

## Costs

Only transcription and the language-model calls cost money. Everything else, including the piano generator, runs on the phone.

- Transcription sends each lesson in chunks of about 5 minutes. A lesson is transcribed once, unless you choose **Transcribe Again**.
- Key points take one or two model calls per lesson. Routines take one call per generation.
- Check current prices at <https://openai.com/api/pricing> and <https://www.anthropic.com/pricing>.

## Known limitations

- **Voice Memos share route.** The "Open in Passaggio" route from Voice Memos hasn't been tested on a device. Route B through Files always works.
- **Transcription of singing is unreliable.** That's why only teacher speech is used for key points. The transcript view still shows everything, including sung syllables.
- **Speech over piano can be missed** or split into short segments. Speaker labels are only as good as your reference clips; re-mark them if labels look wrong.
- **Output cap.** `gpt-4o-transcribe-diarize` returns at most 2,000 output tokens per request, and uploads are limited to 25 MB and about 1,400 s. The app cuts lessons into ~5-minute chunks at quiet points, overlaps them by 1.5 s, de-duplicates the overlap, and keeps timestamps continuous. If a response still hits the cap, that chunk is halved and re-sent automatically.
- **Keep the app open while transcribing.** Without background modes, iOS suspends the app shortly after you leave it. Processing then stops, and the lesson shows "Interrupted — open to resume".
- **Recurring topics** are matched by the model, with a local word-overlap fallback. Matching isn't perfect: two differently worded corrections may stay separate topics. **Find Key Points Again** re-runs the matching for a lesson.
- **The piano doesn't glide.** For the octave slide, it plays the anchor notes and you do the slide. The bundled piano is a small two-velocity-layer upright, chosen for size and licence.
- **7-day expiry and no iCloud**: those are limits of free provisioning, covered above.

## Piano sound (SoundFont)

`Passaggio/Resources/UprightPianoKW.sf2` is **Upright Piano KW (small), version 2019-07-03**, from the FreePats project:

- Source: <https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html> (file `UprightPianoKW-small-SF2-20190703.7z`, SHA-256 `3bd025e7c2ffa9e6f3f99215ce383c9cebbac991cfbf9be1453cdb4328ec3492`; the extracted `.sf2` has SHA-256 `cf2a98eb38a32c4954b4b6e2caae4112d62dd8e892eceefdd7942b0e7d01ac2f`).
- License: **Creative Commons CC0 1.0** (public-domain dedication), which allows bundling in any app. The licence text ships alongside it as `Passaggio/Resources/UprightPianoKW-LICENSE.txt`.

I chose it over larger CC-BY pianos (Salamander, YDP) because it is 9 MB, has no attribution requirement, and has a single preset at bank 0 / program 0, which `AVAudioUnitSampler` loads directly.

## Development

```
project.yml                  XcodeGen spec (source of truth for the Xcode project)
Config/Base.xcconfig         bundle ID; includes git-ignored Local.xcconfig (Team ID)
Packages/PassaggioCore/      platform-independent logic and its tests (swift test)
Passaggio/                   the iOS app: Model (SwiftData), Services, Features (SwiftUI)
PassaggioTests/              app-level tests: SwiftData backup round trip, rendering, Keychain
Fixtures/                    generated sample lesson and voice references
scripts/                     make_sample_lesson.py, smoke_api.py
```

- `make test-core` runs the core unit tests: chunking and timestamp offsets, `diarized_json` parsing, provider request and response handling, note and interval math, routine weighting, and the backup archive. They use recorded fixture responses, never live APIs.
- `make test` runs the core tests, then the app tests on the simulator.
- `make samples` regenerates `Fixtures/`. It needs ffmpeg and uses the platform's text-to-speech.
- `OPENAI_API_KEY=… ANTHROPIC_API_KEY=… make smoke` makes one short real call to each API. That's about a minute of audio, so under a cent. Add `--record` (run `python3 scripts/smoke_api.py --record`) to save the responses as `live_*.json` fixtures.

### Design notes

These are the decisions that aren't obvious from the code:

- **Core logic lives in a Swift package.** Everything testable without Apple frameworks is in `PassaggioCore`, so it runs under `swift test` anywhere, including CI without a simulator.
- **XcodeGen instead of a committed `.xcodeproj`.** Project files are merge-hostile and were impossible to author reliably without Xcode. `project.yml` is short and reviewable.
- **Concurrency settings.** The app target uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with approachable concurrency: UI and SwiftData code is main-actor by default, and audio, rendering and archive work is marked `@concurrent`. It builds in Swift 5 language mode with `SWIFT_STRICT_CONCURRENCY=complete`, so data-race issues show as warnings. Switch to Swift 6 once the build is warning-free.
- **Exercises render to a file**, rather than being sequenced live. `AVAudioEngine` renders in offline manual mode, driving `AVAudioUnitSampler` sample-accurately. The resulting WAV serves preview, looping and export alike, and is cached by a hash of the parameters.
- **The backup is JSON plus tar**, rather than a copy of the SQLite store. It avoids capturing a half-written WAL, survives schema changes, and streams gigabytes with constant memory.
- **Enums are stored as raw strings** in SwiftData models, which keeps predicates and the backup format simple.
