# End-to-end verification checklist

Run this once after the first successful build, on the iPhone 16 Pro, with `Fixtures/sample-lesson.m4a` and then with one real lesson. AirDrop the fixture files to the phone, saving them to Files.

The sample lesson contains two synthetic voices: the "teacher" gives three corrections (chest pushed too high around C, a jaw that clamps on the top note, support to the end of the phrase), and the "student" asks one question. It also has piano cue chords and two sung 5-note scales. `sample-lesson-long.m4a` is the same lesson repeated eight times (~8 min), which forces two transcription chunks.

## Build
- [ ] `make bootstrap TEAM_ID=…` succeeds and `make doctor` reports the SDK is new enough.
- [ ] `make test-core` passes.
- [ ] `make build-sim` succeeds.
- [ ] `make test` passes: app tests on the simulator (backup round trip, render, Keychain).
- [ ] `make build-device TEAM_ID=…` succeeds, and Run from Xcode installs and launches on the phone.

## 1. Import and library
- [ ] Lessons › + › pick `sample-lesson.m4a`: the lesson appears with a date and a 0:57 duration.
- [ ] Voice Memos › recording › Share: is **Passaggio** offered? Note yes or no in the README's "Known limitations".
- [ ] Files › long-press `sample-lesson-long.m4a` › Share › Passaggio: it imports.
- [ ] Details tab: edit the title, date and notes; go back and return, and the changes are kept.
- [ ] Waveform: drag to scrub, play/pause, ±5 s; playback continues with the silent switch on.

## 2. Transcription and key points
- [ ] Settings: save the OpenAI key; the status shows "Saved".
- [ ] Transcribe the sample lesson without voice samples: the Key Points tab asks "Who is your teacher?", and choosing one runs key point extraction.
- [ ] ⋯ › Mark Teacher's Voice: select 3–6 s of teacher speech (preview it), then save. Mark My Voice likewise. Settings › Voice Samples lists both.
- [ ] ⋯ › Transcribe Again: segments are now labelled Teacher and Me with no manual step.
- [ ] Key points appear under Registration and mix (chest/C), Tension and bad habits (jaw), and Breath support (support). Tapping each plays from just before the correction.
- [ ] The long fixture transcribes in two chunks (the progress shows two ranges). Its transcript timestamps run continuously to about 8:00, with no duplicated lines at the ~5:00 cut.
- [ ] Transcript tab: tapping a line plays from it; "Teacher only" filters.

## 3. Insights
- [ ] After both fixtures are analysed, Insights › Recurring lists the repeated corrections with a count of 2×.
- [ ] A topic shows each lesson's quote; tapping one opens that lesson at the moment.

## 4. Practice routine
- [ ] Practice › New 15-minute routine: 3 exercises totalling 15 minutes, each quoting the teacher and linking back to lesson moments.
- [ ] 30 and 45 minutes: the minutes always sum to the chosen length.
- [ ] Regenerate: the exercises change and the history is kept.
- [ ] Start Practice: large controls; the timer counts down with a haptic at zero; the screen stays awake; the attached track plays looped; Finish logs a session.
- [ ] Mark Session Done adds to History.

## 5. Practice audio
- [ ] Tracks › "Passaggio · 5-note scale": plays an F major chord, then F3–C4 and back, rising a semitone per repetition until the top note is F#4, then back down to F3; loops.
- [ ] Change the pattern, start, floor, ceiling, tempo, step, direction and cue toggle: the summary updates, and preview restarts with the new settings.
- [ ] Custom sequence "1 3 5 8 5 3 1" sounds the same as the Arpeggio preset; "1 x" shows an error.
- [ ] Export › Share as M4A and as WAV: AirDrop or Save to Files works, and the file plays elsewhere.
- [ ] Lesson ⋯ › Save Practice Clip: name it, preview the loop, save. It appears under Tracks › Lesson Clips and loops cleanly.
- [ ] A routine exercise can use a clip (generate a routine after saving a clip whose name matches a topic).

## 6. Settings
- [ ] Switch the provider to Anthropic (add a key), then choose Find Key Points Again on a lesson: it works.
- [ ] Remove Key: transcribing now shows "Add your OpenAI API key in Settings."

## 7. Backup and restore
- [ ] Back Up to Files: saves a `.passaggiobackup` file to iCloud Drive.
- [ ] Delete the app, reinstall from Xcode, then Restore from Backup: lessons, audio, key points, insights, routines, clips, presets and voice samples all return. Re-enter the API key.
- [ ] After the 7-day expiry, press Run in Xcode again: the data is still there.
