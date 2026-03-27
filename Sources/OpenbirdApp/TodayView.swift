import SwiftUI

struct TodayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                DatePicker("Day", selection: Binding(
                    get: { model.selectedDay },
                    set: { model.selectDay($0) }
                ), displayedComponents: .date)
                .datePickerStyle(.compact)

                Spacer()

                Button("Raw Logs") {
                    model.isShowingRawLogInspector = true
                }
                Button("Generate Review") {
                    model.generateTodayJournal()
                }
                .buttonStyle(.borderedProminent)
            }

            if let journal = model.todayJournal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        markdownView(journal.markdown)

                        if journal.sections.isEmpty == false {
                            Divider()
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Sections")
                                    .font(.headline)
                                ForEach(journal.sections) { section in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(section.timeRange) • \(section.heading)")
                                            .font(.headline)
                                        ForEach(section.bullets, id: \.self) { bullet in
                                            Text("• \(bullet)")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                                }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No daily review yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Capture some activity, then generate a review from your local logs.")
                )
            }
        }
        .padding(28)
        .navigationTitle("Today")
    }

    @ViewBuilder
    private func markdownView(_ markdown: String) -> some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(markdown)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
