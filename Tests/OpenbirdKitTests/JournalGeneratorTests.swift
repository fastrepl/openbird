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
        #expect(journal.markdown.contains("Stitched together from your local activity logs"))
        #expect(journal.markdown.contains("## 9:00"))
        #expect(journal.markdown.contains("Spent this block"))
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
}
