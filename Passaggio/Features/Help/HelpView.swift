import SwiftUI

/// The in-app guide, opened from Settings. Topics live in `HelpContent.swift`.
struct HelpView: View {
    @State private var query = ""

    var body: some View {
        let topics = HelpTopic.matching(query)
        List {
            ForEach(HelpSection.allCases) { section in
                let inSection = topics.filter { $0.section == section }
                if !inSection.isEmpty {
                    Section(section.title) {
                        ForEach(inSection) { topic in
                            NavigationLink {
                                HelpArticleView(topic: topic)
                            } label: {
                                Label(topic.title, systemImage: topic.systemImage)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if topics.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "How do I…")
        .navigationTitle("How to Use Passaggio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpArticleView: View {
    let topic: HelpTopic

    var body: some View {
        List {
            Section {
                Text(markdown: topic.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Section("Steps") {
                ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 20, alignment: .leading)
                        Text(markdown: step)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Step \(index + 1): \(String(AttributedString(guideMarkdown: step).characters))")
                }
            }
            if !topic.tips.isEmpty {
                Section("Good to Know") {
                    ForEach(topic.tips, id: \.self) { tip in
                        Text(markdown: tip)
                    }
                }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension AttributedString {
    /// The guide's inline Markdown (bold UI paths), or the plain text if it doesn't parse.
    init(guideMarkdown: String) {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        self = (try? AttributedString(markdown: guideMarkdown, options: options)) ?? AttributedString(guideMarkdown)
    }
}

private extension Text {
    /// Renders guide text without making the strings localisation keys.
    init(markdown: String) {
        self.init(AttributedString(guideMarkdown: markdown))
    }
}

#Preview("Help") {
    NavigationStack { HelpView() }
}

#Preview("Article") {
    NavigationStack { HelpArticleView(topic: HelpTopic.all.first { $0.id == "voices" } ?? HelpTopic.all[0]) }
}
