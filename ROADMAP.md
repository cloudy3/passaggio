# Roadmap

## Goal

Passaggio's purpose is to give you **high-quality practice audio — scales and exercises — tailored to you**, built from what your teacher says in lessons. New features should serve that goal.

## Where the app stands

The main loop works end to end: **lesson recording → key points → recurring insights → practice routine → practice audio**, with backup and restore around it. On the first two real lessons, key point extraction and topic grouping were accurate.

## 1. Playback for studying a lesson

- **Playback speed (0.5×–1×).** `PlayerController` sets `enableRate = false`. Slowing the teacher's demonstration down is a common need.
- **Lock screen and background playback.** There's no `UIBackgroundModes` audio entry and no `MPNowPlayingInfoCenter` or remote commands, so a lesson can't be listened to with the screen off. The background audio mode is an `Info.plist` key, so it works with a Personal Team.
- **Transpose a clip** with `AVAudioUnitTimePitch`, for when the teacher demonstrated in a key that doesn't suit your range.

## 2. Record lessons in the app

Import currently goes Voice Memos → Files → Passaggio, and the direct share-sheet route is still unverified on a device. A record button on the Lessons tab would remove that step. It needs `NSMicrophoneUsageDescription` in `Info.plist`, which doesn't need an entitlement.

## 3. Prepare for the next lesson

A screen to open before a lesson, with:

- what the teacher focused on last time;
- how often you practised each item since then;
- which topics keep coming back.

This needs no language model, because it only aggregates existing data. That keeps it within the rule that the teacher is the authority (`FeedbackAnalyst.principles(for:)`).

## 4. Smaller improvements

- **Search** across transcripts and key points (`.searchable`). The app has no search yet.
- **Configurable vocal range.** D#2–G#4 and the C4–F#4 passaggio are hard-coded (`Note.singerFloor` and `Note.singerCeiling` in `PassaggioCore`, and the footer text in `GeneratorView`). Ranges change with training, so this belongs in Settings.
- **Practice calendar or streak, and reminders.** History exists only per routine today. Local notifications need no entitlement.
- **More control over routines:** a custom length beyond 15, 30 and 45 minutes, and pinning or excluding a topic ("always include breath work").

## Not planned

- **Tools for correcting key points and topics** (edit, delete, merge, move). Extraction and grouping were accurate on real lessons. Reconsider only if that changes.
- **Recording yourself while practising.** It isn't part of your practice habit.
- **Pitch detection or scoring your singing.** It's hard to do well, and it would compete with the teacher as the authority on your technique.
- **Sync and sharing.** Free provisioning rules out iCloud, and backups to Files already protect the data.
