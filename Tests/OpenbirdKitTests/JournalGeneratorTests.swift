import Foundation
import Testing
@testable import OpenbirdKit

struct JournalGeneratorTests {
    @Test func generatesSectionsFromSyntheticEvents() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let generator = JournalGenerator(store: store)

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(600),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Investor Portal",
                url: "https://example.com",
                visibleText: "Reviewed startup profiles",
                source: "accessibility",
                contentHash: "a",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(700),
                endedAt: start.addingTimeInterval(1300),
                bundleId: "com.microsoft.VSCode",
                appName: "VS Code",
                windowTitle: "openbird",
                url: nil,
                visibleText: "Implemented journaling",
                source: "accessibility",
                contentHash: "b",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let journal = try await generator.generate(
            request: JournalGenerationRequest(
                date: start,
                providerID: nil
            )
        )

        #expect(journal.sections.count >= 1)
        #expect(journal.markdown.contains("Looked through your context."))
        #expect(journal.markdown.contains("Here's the shape of your"))
        #expect(journal.markdown.contains("## Investor Portal"))
        #expect(journal.markdown.contains("This part of the day centered on Investor Portal in Safari."))
    }

    @Test func prefersSpecificHeadingsAndDeduplicatedBullets() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let generator = JournalGenerator(store: store)

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(180),
                bundleId: "com.tinyspeck.slackmacgap",
                appName: "Slack",
                windowTitle: "product (Channel)",
                url: nil,
                visibleText: "product (Channel)",
                source: "accessibility",
                contentHash: "slack-1",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(181),
                endedAt: start.addingTimeInterval(360),
                bundleId: "com.tinyspeck.slackmacgap",
                appName: "Slack",
                windowTitle: "Slack",
                url: nil,
                visibleText: "",
                source: "workspace",
                contentHash: "slack-2",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let journal = try await generator.generate(
            request: JournalGenerationRequest(
                date: start,
                providerID: nil
            )
        )

        #expect(journal.sections.first?.heading == "product (Channel)")
        #expect(journal.sections.first?.bullets.first == "Slack • product (Channel)")
    }

    @Test func parsesStructuredMarkdownIntoBlocks() throws {
        let markdown = """
        Looked through your context and stitched together the interesting parts.

        ## ~3:15 PM - 4:15 PM - Char Dev Sprint
        Heads-down on `fastrepl/char`, shipping a wave of PRs.

        | PR | What it does | Status |
        | --- | --- | --- |
        | #4761 | Expand onboarding calendars after connection | Merged |
        | #4768 | Streamline plan status display in settings | Open |

        ## ~4:27 PM - Big Strategy Call
        Long team strategy discussion with a few concrete themes.

        - **Pricing:** $15 viable with speaker ID.
        - **CLI rearchitecture:** Rust-based standalone core.
        """

        let document = JournalMarkdownParser.parse(markdown)

        #expect(document.leadingBlocks.count == 1)
        #expect(document.sections.count == 2)

        guard case .paragraph(let intro)? = document.leadingBlocks.first else {
            Issue.record("Expected leading paragraph block")
            return
        }
        #expect(intro.contains("stitched together"))

        let firstSection = try #require(document.sections.first)
        #expect(firstSection.title == "~3:15 PM - 4:15 PM - Char Dev Sprint")
        #expect(firstSection.blocks.count == 2)

        guard case .table(let table) = firstSection.blocks[1] else {
            Issue.record("Expected markdown table in first section")
            return
        }
        #expect(table.headers == ["PR", "What it does", "Status"])
        #expect(table.rows.count == 2)

        let secondSection = try #require(document.sections.last)
        guard case .bulletList(let bullets) = secondSection.blocks.last else {
            Issue.record("Expected bullet list in second section")
            return
        }
        #expect(bullets.count == 2)
    }

    @Test func parsesOrderedListsIntoBlocks() throws {
        let markdown = """
        Based on the journal, here are the areas where you could have contributed more:

        1. **Spent more time on growth.**
        2. **Followed through on SEO research.**

        ## Follow-up
        1. Verify the shipped fix.
        """

        let document = JournalMarkdownParser.parse(markdown)

        #expect(document.leadingBlocks.count == 2)

        guard case .orderedList(let items) = document.leadingBlocks[1] else {
            Issue.record("Expected ordered list in leading blocks")
            return
        }
        #expect(items == [
            "**Spent more time on growth.**",
            "**Followed through on SEO research.**",
        ])

        let section = try #require(document.sections.first)
        guard case .orderedList(let followUpItems) = section.blocks.first else {
            Issue.record("Expected ordered list in follow-up section")
            return
        }
        #expect(followUpItems == ["Verify the shipped fix."])
    }

    @Test func ignoresLowSignalEventsInGeneratedReview() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let generator = JournalGenerator(store: store)

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.apple.loginwindow",
                appName: "loginwindow",
                windowTitle: "loginwindow",
                url: nil,
                visibleText: "",
                source: "accessibility",
                contentHash: "loginwindow",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(120),
                endedAt: start.addingTimeInterval(180),
                bundleId: "com.openai.codex",
                appName: "Codex",
                windowTitle: "Codex",
                url: nil,
                visibleText: "",
                source: "accessibility",
                contentHash: "codex",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(240),
                endedAt: start.addingTimeInterval(600),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "ComputelessComputer/openbird",
                url: "https://github.com/ComputelessComputer/openbird",
                visibleText: "Reviewed PR about preserving Google Calendar selections across sync.",
                source: "accessibility",
                contentHash: "safari",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let journal = try await generator.generate(
            request: JournalGenerationRequest(
                date: start,
                providerID: nil
            )
        )

        #expect(journal.sections.count == 1)
        #expect(journal.sections.first?.heading == "ComputelessComputer/openbird")
        #expect(journal.markdown.contains("loginwindow") == false)
        #expect(journal.markdown.contains("Codex") == false)
    }

    @Test func fallbackMarkdownPrefersTaskHeadingOverBareToolName() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let generator = JournalGenerator(store: store)

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(300),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Safari",
                url: "https://stilla.ai/pricing",
                visibleText: "",
                source: "accessibility",
                contentHash: "safari-pricing",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let journal = try await generator.generate(
            request: JournalGenerationRequest(
                date: start,
                providerID: nil
            )
        )

        let headingLine = journal.markdown
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix("## ") }

        #expect(headingLine?.contains("Reviewing stilla.ai/pricing") == true)
        #expect(headingLine?.contains("Safari") == false)
    }

    @Test func groupsNoisyChatSnapshotsBeforeSummarizing() throws {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(30),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice Profile 9:31 PM See you there Enter a message Search Voice Call Video Call Menu",
                source: "accessibility",
                contentHash: "chat-1",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(31),
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 9:39 PM See you there tomorrow Enter a message Search Menu",
                source: "accessibility",
                contentHash: "chat-2",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(61),
                endedAt: start.addingTimeInterval(90),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 10:23 PM See you there tomorrow",
                source: "accessibility",
                contentHash: "chat-3",
                isExcluded: false
            ),
        ]

        let grouped = ActivityEvidencePreprocessor.groupedMeaningfulEvents(from: events)
        let firstGroup = try #require(grouped.first)

        #expect(grouped.count == 1)
        #expect(firstGroup.sourceEventCount == 3)
        #expect(firstGroup.excerpt.contains("Enter a message") == false)
        #expect(firstGroup.excerpt.contains("Voice Call") == false)
        #expect(firstGroup.excerpt.contains("See you there"))
    }

    @Test func generatesDeduplicatedSectionsFromGroupedEvidence() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let generator = JournalGenerator(store: store)

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(30),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice Profile 9:31 PM See you there Enter a message Search Voice Call Video Call Menu",
                source: "accessibility",
                contentHash: "chat-a",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(31),
                endedAt: start.addingTimeInterval(60),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 9:39 PM See you there tomorrow Enter a message Search Menu",
                source: "accessibility",
                contentHash: "chat-b",
                isExcluded: false
            ),
            ActivityEvent(
                startedAt: start.addingTimeInterval(90),
                endedAt: start.addingTimeInterval(180),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "Alice",
                url: nil,
                visibleText: "Alice 10:23 PM Shared the pickup plan",
                source: "accessibility",
                contentHash: "chat-c",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let journal = try await generator.generate(
            request: JournalGenerationRequest(
                date: start,
                providerID: nil
            )
        )

        #expect(journal.sections.count == 1)
        #expect(journal.sections.first?.sourceEventIDs.count == 3)
        #expect(journal.sections.first?.bullets.count == 1)
        #expect(journal.sections.first?.bullets.first?.contains("Enter a message") == false)
        #expect(journal.sections.first?.bullets.first?.contains("Voice Call") == false)
        #expect(journal.markdown.contains("Looked through your context."))
        #expect(journal.markdown.contains("## Alice"))
        #expect(journal.markdown.contains("This part of the day centered on Alice in KakaoTalk."))
        #expect(journal.markdown.contains("- See you there"))
    }

    @Test func fallbackMarkdownKeepsDirectMessageTitlesPlain() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let generator = JournalGenerator(store: store)

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        let events = [
            ActivityEvent(
                startedAt: start,
                endedAt: start.addingTimeInterval(45),
                bundleId: "com.kakao.KakaoTalkMac",
                appName: "KakaoTalk",
                windowTitle: "윤진솔",
                url: nil,
                visibleText: "윤진솔 너무 피곤하다 해커톤 끝나고 바로 훠궈 먹었어",
                source: "accessibility",
                contentHash: "dm-1",
                isExcluded: false
            ),
        ]

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let journal = try await generator.generate(
            request: JournalGenerationRequest(
                date: start,
                providerID: nil
            )
        )

        #expect(journal.markdown.contains("## 윤진솔"))
        #expect(journal.markdown.contains("This part of the day centered on 윤진솔 in KakaoTalk."))
        #expect(journal.markdown.contains("## Chatting with 윤진솔") == false)
    }

    @Test func compactsAcrossWholeDayWhenSourceEventsAreCapped() async throws {
        let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("sqlite")
        let store = try OpenbirdStore(databaseURL: databaseURL)
        let generator = JournalGenerator(store: store)

        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(8 * 3600)
        let events = (0..<6).map { index in
            let eventStart = start.addingTimeInterval(TimeInterval(index * 3600))
            return ActivityEvent(
                startedAt: eventStart,
                endedAt: eventStart.addingTimeInterval(300),
                bundleId: "com.apple.Safari",
                appName: "Safari",
                windowTitle: "Window \(index + 1)",
                url: "https://example.com/\(index + 1)",
                visibleText: "Checked window \(index + 1)",
                source: "accessibility",
                contentHash: "event-\(index + 1)",
                isExcluded: false
            )
        }

        for event in events {
            try await store.saveActivityEvent(event)
        }

        let journal = try await generator.generate(
            request: JournalGenerationRequest(
                date: start,
                maxSourceEvents: 4,
                providerID: nil
            )
        )

        let coveredSourceEventIDs = Set(journal.sections.flatMap(\.sourceEventIDs))

        #expect(journal.sections.count == 4)
        #expect(coveredSourceEventIDs == Set(events.map(\.id)))
        #expect(journal.sections.first?.sourceEventIDs.contains(events[0].id) == true)
        #expect(journal.sections.last?.sourceEventIDs.contains(events[5].id) == true)
    }
}
