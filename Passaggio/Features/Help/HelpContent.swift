import Foundation

// The in-app guide (Settings › How to Use Passaggio). Strings are Markdown so UI
// paths can be bold. Quote labels exactly as the screens show them, and update
// this file when a feature or menu item is added or renamed.

nonisolated enum HelpSection: String, CaseIterable, Identifiable {
    case gettingStarted, lessons, insights, practice, tracks, data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .lessons: "Lessons"
        case .insights: "Insights"
        case .practice: "Practice"
        case .tracks: "Tracks"
        case .data: "Your Data"
        }
    }
}

nonisolated struct HelpTopic: Identifiable, Hashable {
    let id: String
    let section: HelpSection
    let title: String
    let systemImage: String
    let summary: String
    let steps: [String]
    var tips: [String] = []

    /// Topics containing every word of `query` in their title or text, ignoring case
    /// and accents. An empty query returns every topic.
    static func matching(_ query: String) -> [HelpTopic] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return all }
        return all.filter { topic in
            let text = ([topic.title, topic.summary] + topic.steps + topic.tips).joined(separator: "\n")
            return words.allSatisfy { text.localizedStandardContains($0) }
        }
    }

    static let all: [HelpTopic] = [
        // MARK: Getting Started
        HelpTopic(
            id: "api-key", section: .gettingStarted, title: "Add Your API Key", systemImage: "key",
            summary: "Transcription and key points need an OpenAI API key.",
            steps: [
                "Open **Settings › OpenAI API Key**.",
                "Paste your key and tap **Save to Keychain**. The status changes to **Saved**.",
                "To use Anthropic for key points and routines instead, add an Anthropic key too and choose it under **Key Points and Routines › Provider**.",
            ],
            tips: [
                "Keys stay in the Keychain on this iPhone. They aren’t included in backups, so add them again after restoring.",
            ]
        ),
        HelpTopic(
            id: "import", section: .gettingStarted, title: "Import a Lesson", systemImage: "square.and.arrow.down",
            summary: "Bring a recording in from Voice Memos.",
            steps: [
                "In Voice Memos, tap the recording, then **⋯ › Share › Save to Files**. You can select several memos at once.",
                "In Passaggio, tap **Lessons › +** and pick the files.",
            ],
            tips: [
                "You can also share an audio file straight to Passaggio from the share sheet, if it’s listed there.",
                "The lesson date comes from the recording. Change it, the title or your notes in the lesson’s **Details** tab.",
            ]
        ),
        HelpTopic(
            id: "voices", section: .gettingStarted, title: "Mark Your Voices Once", systemImage: "person.wave.2",
            summary: "Short samples of your teacher’s voice and yours let every lesson be labelled automatically.",
            steps: [
                "Open any lesson, tap **⋯** and choose **Mark Teacher’s Voice…** from the menu.",
                "Drag on the waveform to select 2–10 seconds where only your teacher is speaking: no piano and no singing.",
                "Play the selection to check it, then tap **Save**.",
                "Do the same with **Mark My Voice…** in the same menu.",
            ],
            tips: [
                "The samples are listed under **Settings › Voice Samples**. Swipe one to delete it.",
                "Without samples, speakers come back as A, B and so on, and you’ll be asked which one is your teacher.",
            ]
        ),

        // MARK: Lessons
        HelpTopic(
            id: "key-points", section: .lessons, title: "Get Key Points from a Lesson", systemImage: "sparkles",
            summary: "Passaggio transcribes the lesson, then pulls out your teacher’s feedback.",
            steps: [
                "Open the lesson. On the **Key Points** tab, tap **Transcribe and Find Key Points**.",
                "Wait while it transcribes and finds key points. You can leave the screen; tap **Cancel** to stop.",
                "Tap a key point to play the lesson from that moment.",
            ],
            tips: [
                "Only your teacher’s speech is sent for key points, and the key points only organise what your teacher said.",
                "Cancelling during transcription means it starts again from the beginning next time.",
            ]
        ),
        HelpTopic(
            id: "choose-teacher", section: .lessons, title: "Choose Which Speaker Is Your Teacher",
            systemImage: "person.2.badge.gearshape",
            summary: "When a lesson says “Choose which speaker is your teacher”, the speakers couldn’t be recognised.",
            steps: [
                "Open the lesson. The **Key Points** tab shows **Who is your teacher?** with one line from each speaker.",
                "Tap a line to hear it in the transcript.",
                "Tap **Teacher** for your teacher and **Me** for yourself.",
                "Tap **Find Key Points**.",
            ],
            tips: [
                "You can also touch and hold a line in the **Transcript** tab and choose **Label This Speaker as Teacher**.",
                "Mark your voices once (see Getting Started) so this isn’t needed next time.",
            ]
        ),
        HelpTopic(
            id: "screaming", section: .lessons, title: "Screaming Lessons", systemImage: "bolt",
            summary: "Mark harsh-vocals lessons as Screaming so distortion work isn’t treated as a bad habit.",
            steps: [
                "Open the lesson and go to the **Details** tab.",
                "Set **Style** to **Screaming**.",
                "If the lesson already has key points, tap **Find Key Points Again**.",
            ],
            tips: [
                "Screaming lessons add a **Distortion and texture** theme.",
                "Singing and screaming lessons keep separate recurring topics in Insights.",
            ]
        ),
        HelpTopic(
            id: "playback", section: .lessons, title: "Listen and Jump Around", systemImage: "waveform",
            summary: "Find the moment you want in a lesson.",
            steps: [
                "Drag on the waveform to move through the lesson, and use the buttons to play, pause or skip 5 seconds.",
                "Tap a key point, or a line in the **Transcript** tab, to play from there.",
                "Turn on **Teacher only** in the **Transcript** tab to hide everyone else’s lines.",
            ]
        ),
        HelpTopic(
            id: "clip", section: .lessons, title: "Save a Practice Clip", systemImage: "scissors",
            summary: "Keep a stretch of a lesson, such as your teacher playing an exercise, to loop while you practise.",
            steps: [
                "Open the lesson, tap **⋯** and choose **Save Practice Clip…** from the menu.",
                "Drag on the waveform to select the stretch, and fine-tune its edges.",
                "Name the clip, play it to check the loop, then tap **Save**.",
            ],
            tips: [
                "Clips appear under **Tracks › Lesson Clips**, and routines can use them.",
            ]
        ),
        HelpTopic(
            id: "redo", section: .lessons, title: "Transcribe Again or Find Key Points Again",
            systemImage: "arrow.clockwise",
            summary: "Both are in a lesson’s **⋯** menu. They redo different amounts of work.",
            steps: [
                "**Find Key Points Again** reuses the transcript and only redoes the key points. Use it after changing the style, the speakers or the model. It’s the cheaper of the two.",
                "**Transcribe Again** redoes the whole lesson, starting with transcription. Use it after marking your voices, or if the transcript is wrong.",
            ]
        ),
        HelpTopic(
            id: "failed", section: .lessons, title: "When a Lesson Fails or Stops", systemImage: "exclamationmark.triangle",
            summary: "The Lessons list shows “Failed — open to retry” or “Interrupted — open to resume”.",
            steps: [
                "Open the lesson and read the message on the **Key Points** tab.",
                "Fix the cause if it names one, such as a missing API key in Settings.",
                "Tap **Try Again**, or **Transcribe and Find Key Points** if it was interrupted.",
            ],
            tips: [
                "A finished transcript is kept, so trying again only redoes the key points.",
            ]
        ),

        // MARK: Insights
        HelpTopic(
            id: "insights", section: .insights, title: "See What Keeps Coming Up", systemImage: "chart.bar.xaxis",
            summary: "Insights groups your teacher’s feedback into topics and counts the lessons each one came up in.",
            steps: [
                "Open **Insights**. **Recurring** lists topics from more than one lesson, most repeated first. **Mentioned Once** lists the rest.",
                "Tap **Filter** to show one theme.",
                "Tap a topic to see **What Your Teacher Said** in each lesson, then tap one to open the lesson at that moment.",
            ]
        ),

        // MARK: Practice
        HelpTopic(
            id: "routine", section: .practice, title: "Make a Practice Routine", systemImage: "figure.mind.and.body",
            summary: "Routines are built from your lessons, weighted toward points your teacher repeats and recent lessons.",
            steps: [
                "Open **Practice** and tap **New 15-minute routine**, **New 30-minute routine** or **New 45-minute routine**.",
                "Open the routine to see each exercise, the teacher quotes it came from, and its track.",
                "Tap a quote to open the lesson at that moment.",
                "To get different exercises, tap **Regenerate**. The practice history is kept.",
            ],
            tips: [
                "Swipe a saved routine to delete it.",
            ]
        ),
        HelpTopic(
            id: "practise", section: .practice, title: "Practise with a Routine", systemImage: "timer",
            summary: "Practice mode shows one exercise at a time with a timer and its track.",
            steps: [
                "Open a routine and tap **Start Practice**.",
                "Start the timer. The phone vibrates when it reaches zero, and the screen stays on.",
                "Move between exercises with the previous and next buttons. Finishing the last one logs the session.",
                "Tap **End** to leave early.",
            ],
            tips: [
                "Practised without practice mode? Tap **Mark Session Done** on the routine to add it to **History**.",
            ]
        ),

        // MARK: Tracks
        HelpTopic(
            id: "exercise", section: .tracks, title: "Make a Piano Exercise", systemImage: "pianokeys",
            summary: "Generate scales and arpeggios that move through your range.",
            steps: [
                "Open **Tracks** and tap **New Exercise**, or tap an existing exercise to change it.",
                "Choose a **Pattern**.",
                "Set the notes, or tap **My range** or **Passaggio focus**.",
                "Set the direction, the step each repetition and the tempo.",
                "Play it to hear the changes.",
            ],
            tips: [
                "**Play root chord before each repetition** gives you the key before you sing.",
                "Swipe an exercise in the list to delete it.",
            ]
        ),
        HelpTopic(
            id: "custom-sequence", section: .tracks, title: "Use a Custom Sequence", systemImage: "number",
            summary: "Write your own pattern as scale degrees.",
            steps: [
                "In an exercise, set **Pattern** to **Custom sequence**.",
                "Type scale degrees separated by spaces, such as **1 3 5 8 5 3 1**.",
                "If a message appears in red, fix the sequence it points to.",
            ]
        ),
        HelpTopic(
            id: "export", section: .tracks, title: "Share a Track", systemImage: "square.and.arrow.up",
            summary: "Use an exercise outside the app.",
            steps: [
                "Open the exercise and tap **Export**.",
                "Choose **Share as M4A** (smaller) or **Share as WAV**.",
                "AirDrop it, save it to Files or send it.",
            ]
        ),
        HelpTopic(
            id: "lesson-clips", section: .tracks, title: "Manage Lesson Clips", systemImage: "music.note.list",
            summary: "Clips you saved from lessons are under **Tracks › Lesson Clips**.",
            steps: [
                "Tap a clip to play it on a loop.",
                "Touch and hold it to **Rename** it or **Open Lesson** at that moment.",
                "Swipe it to delete it.",
            ]
        ),

        // MARK: Your Data
        HelpTopic(
            id: "backup", section: .data, title: "Back Up and Restore", systemImage: "externaldrive",
            summary: "There’s no iCloud sync, so keep a backup file.",
            steps: [
                "Tap **Settings › Back Up to Files…** and save the file, such as to iCloud Drive.",
                "To restore, tap **Settings › Restore from Backup…** and pick the file. Check the date and contents, then tap **Replace All Data**.",
            ],
            tips: [
                "Restoring replaces everything currently in the app.",
                "API keys aren’t in the backup. Add them again afterwards.",
            ]
        ),
        HelpTopic(
            id: "expiry", section: .data, title: "The App Stopped Opening", systemImage: "calendar.badge.exclamationmark",
            summary: "Builds signed with a free Apple ID expire after 7 days. Your data is still there.",
            steps: [
                "Connect the iPhone to the Mac.",
                "Open the project in Xcode and press **Run**.",
            ],
            tips: [
                "Don’t delete the app to fix it. Deleting it erases its data.",
            ]
        ),
        HelpTopic(
            id: "costs", section: .data, title: "Models and Costs", systemImage: "dollarsign.circle",
            summary: "You pay the AI provider directly for each lesson.",
            steps: [
                "Transcription always uses OpenAI and costs about 36¢ for an hour of recording.",
                "Finding key points costs a few cents to about 20¢ per lesson, depending on the model in **Settings › Key Points and Routines**.",
                "**Find Key Points Again** only pays for key points. **Transcribe Again** pays for both.",
            ],
            tips: [
                "Check your provider’s usage page to see what you’ve actually spent.",
            ]
        ),
    ]
}
