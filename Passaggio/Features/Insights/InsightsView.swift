import PassaggioCore
import SwiftData
import SwiftUI

/// Feedback that keeps coming back, across all lessons. Recurring corrections are
/// what most need work, so they're listed first.
struct InsightsView: View {
    @Query private var topics: [FeedbackTopic]
    @State private var themeFilter: Theme?

    private var ranked: [FeedbackTopic] {
        topics
            .filter { themeFilter == nil || $0.theme == themeFilter }
            .filter { !$0.keyPoints.isEmpty }
            .sorted {
                let (a, b) = ($0.lessons.count, $1.lessons.count)
                if a != b { return a > b }
                return ($0.lastSeen ?? .distantPast) > ($1.lastSeen ?? .distantPast)
            }
    }

    var body: some View {
        NavigationStack {
            List {
                let recurring = ranked.filter { $0.lessons.count > 1 }
                let once = ranked.filter { $0.lessons.count <= 1 }

                if !recurring.isEmpty {
                    Section {
                        ForEach(recurring) { TopicRow(topic: $0) }
                    } header: {
                        Text("Recurring")
                    } footer: {
                        Text("Your teacher has raised these in more than one lesson.")
                    }
                }
                if !once.isEmpty {
                    Section("Mentioned Once") {
                        ForEach(once) { TopicRow(topic: $0) }
                    }
                }
            }
            .overlay {
                if topics.isEmpty {
                    ContentUnavailableView(
                        "No Feedback Yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Transcribe a lesson to see which points your teacher keeps coming back to.")
                    )
                }
            }
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Theme", selection: $themeFilter) {
                            Text("All Themes").tag(Theme?.none)
                            ForEach(Theme.allCases) { theme in
                                theme.label.tag(Theme?.some(theme))
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: themeFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .navigationDestination(for: FeedbackTopic.self) { topic in
                TopicDetailView(topic: topic)
            }
            .navigationDestination(for: LessonMoment.self) { moment in
                LessonDestination(moment: moment)
            }
        }
    }
}

struct TopicRow: View {
    let topic: FeedbackTopic

    var body: some View {
        NavigationLink(value: topic) {
            HStack(spacing: 12) {
                Image(systemName: topic.theme.systemImage)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.title)
                        .font(.body)
                    HStack(spacing: 4) {
                        Text(topic.theme.displayName)
                        if let lastSeen = topic.lastSeen {
                            Text("· last \(lastSeen, format: .relative(presentation: .named))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(topic.lessons.count)×")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(topic.lessons.count > 1 ? Color.accentColor : .secondary)
                    .accessibilityLabel("in \(topic.lessons.count) lessons")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TopicDetailView: View {
    let topic: FeedbackTopic

    var body: some View {
        List {
            Section {
                LabeledContent("Theme", value: topic.theme.displayName)
                LabeledContent("Lessons", value: "\(topic.lessons.count)")
                if let lastSeen = topic.lastSeen {
                    LabeledContent("Last mentioned") {
                        Text(lastSeen, format: .dateTime.day().month().year())
                    }
                }
            }
            Section("What Your Teacher Said") {
                ForEach(topic.sortedKeyPoints) { point in
                    if let lesson = point.lesson {
                        NavigationLink(value: LessonMoment(lessonID: lesson.id, time: point.timestamp)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lesson.date, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(point.summary)
                                if !point.quote.isEmpty {
                                    Text("“\(point.quote)”")
                                        .font(.callout)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                }
                                Label(formatTimestamp(point.timestamp), systemImage: "play.circle.fill")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.vertical, 2)
                        }
                        .accessibilityHint("Opens the lesson at \(formatTimestamp(point.timestamp))")
                    }
                }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
