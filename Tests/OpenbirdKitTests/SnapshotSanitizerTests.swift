import Testing
@testable import OpenbirdKit

struct SnapshotSanitizerTests {
    @Test func normalizesSlackTitlesAndRemovesDuplicateVisibleText() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            windowTitle: "product (Channel) - Fastrepl - 1 new item - Slack",
            url: nil,
            visibleText: "product (Channel) - Fastrepl - 1 new item - Slack",
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "product (Channel)")
        #expect(sanitized.visibleText.isEmpty)
    }

    @Test func usesNormalizedSlackVisibleTextWhenWindowTitleIsGeneric() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            windowTitle: "Slack",
            url: nil,
            visibleText: "alert-users (Channel) - Fastrepl - 1 new item - Slack",
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "alert-users (Channel)")
        #expect(sanitized.visibleText.isEmpty)
    }

    @Test func stripsSlackUnreadMarkersAndComposerPrompts() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.tinyspeck.slackmacgap",
            appName: "Slack",
            windowTitle: "* Peter Choi (DM) - Fastrepl - Slack",
            url: nil,
            visibleText: """
            * Peter Choi (DM) - Fastrepl - Slack
            Message to Peter Choi
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "Peter Choi (DM)")
        #expect(sanitized.visibleText.isEmpty)
    }

    @Test func removesGenericCodexVisibleText() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.openai.codex",
            appName: "Codex",
            windowTitle: "Codex",
            url: nil,
            visibleText: "Codex",
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "Codex")
        #expect(sanitized.visibleText.isEmpty)
    }

    @Test func filtersMessagesChromeAndKeepsTranscript() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.apple.MobileSMS",
            appName: "Messages",
            windowTitle: "Josh Earle",
            url: nil,
            visibleText: """
            Josh Earle
            Search
            Messages
            Sounds good, I'll send it tonight.
            Perfect, thanks.
            compose
            Start FaceTime
            Message
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "Josh Earle")
        #expect(sanitized.visibleText == "Sounds good, I'll send it tonight.\nPerfect, thanks.")
    }

    @Test func fallsBackToMessagesParticipantWhenWindowTitleIsGeneric() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.apple.MobileSMS",
            appName: "Messages",
            windowTitle: "Messages",
            url: nil,
            visibleText: """
            Josh Earle
            Search
            Messages
            Can you review this before 5?
            Yep, I'll take a look.
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "Josh Earle")
        #expect(sanitized.visibleText == "Can you review this before 5?\nYep, I'll take a look.")
    }

    @Test func filtersKakaoTalkChromeAndKeepsMessageText() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.kakao.KakaoTalkMac",
            appName: "KakaoTalk",
            windowTitle: "Yoo✨",
            url: nil,
            visibleText: """
            Yoo✨
            Profile
            6:29 PM
            오 저도 사나 좋아하는데...
            Enter a message
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "Yoo✨")
        #expect(sanitized.visibleText == "오 저도 사나 좋아하는데...")
    }

    @Test func fallsBackToKakaoTalkConversationWhenTitleIsGeneric() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.kakao.KakaoTalkMac",
            appName: "KakaoTalk",
            windowTitle: "KakaoTalk",
            url: nil,
            visibleText: """
            KakaoTalk
            common icon newdot
            Notifications
            Settings
            Chats
            Add chatroom
            Search
            Profile
            8:59 PM
            박륜지
            내가 강한 사람이라서 스스로 처리한거지^
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "박륜지")
        #expect(sanitized.visibleText == "내가 강한 사람이라서 스스로 처리한거지^")
    }

    @Test func fallsBackToKakaoTalkConversationWhenTitleIsNumeric() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.kakao.KakaoTalkMac",
            appName: "KakaoTalk",
            windowTitle: "1",
            url: nil,
            visibleText: """
            Chats
            Silent Chatroom
            박륜지
            Unread folder, 1 New message
            8:30 PM
            ㅋㅋㅋㅋ 먼지가 없긴 해요
            Enter a message
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "박륜지")
        #expect(sanitized.visibleText == "ㅋㅋㅋㅋ 먼지가 없긴 해요")
    }

    @Test func preservesKakaoTalkSpeakerMarkersWhenAvailable() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.kakao.KakaoTalkMac",
            appName: "KakaoTalk",
            windowTitle: "KakaoTalk",
            url: nil,
            visibleText: """
            Them: 윤진솔.
            Them: youtu.be
            Them: 이거알지!!
            Me: 좋은 노래다
            Me: 난 근데 라우브가 파멸적인데
            Me: 1
            9:15 AM
            Me: 이거 진짜..
            Enter a message
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "윤진솔.")
        #expect(sanitized.visibleText.contains("Them: 이거알지!!"))
        #expect(sanitized.visibleText.contains("Me: 좋은 노래다"))
        #expect(sanitized.visibleText.contains("Me: 이거 진짜.."))
        #expect(sanitized.visibleText.contains("Me: 1") == false)
        #expect(sanitized.visibleText.contains("Enter a message") == false)
    }

    @Test func fallsBackToMeaningfulVisibleTextWhenWindowTitleIsMissing() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.johnjeong.philo",
            appName: "Philo",
            windowTitle: "",
            url: nil,
            visibleText: """
            Project notes
            Start meeting recording
            Pin window
            Ship activity tracking fix
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "Project notes")
        #expect(sanitized.visibleText == "Ship activity tracking fix")
    }

    @Test func discardsLoginWindowSnapshots() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.apple.loginwindow",
            appName: "loginwindow",
            windowTitle: "loginwindow",
            url: nil,
            visibleText: "",
            source: "accessibility"
        )

        #expect(sanitizer.shouldDiscard(snapshot))
    }

    @Test func filtersBrowserChromeFragmentsAndKeepsMeaningfulContent() {
        let sanitizer = SnapshotSanitizer()
        let snapshot = WindowSnapshot(
            bundleId: "com.apple.Safari",
            appName: "Safari",
            windowTitle: "ComputelessComputer/openbird",
            url: "https://github.com/ComputelessComputer/openbird",
            visibleText: """
            ComputelessComputer/openbird
            Tab bar, 2 tabs, 7 pinned tabs Go back Go forward Page Menu Add page to Reading List
            PR fixes calendar sync behavior
            https://github.com/ComputelessComputer/openbird
            """,
            source: "accessibility"
        )

        let sanitized = sanitizer.sanitize(snapshot)

        #expect(sanitized.windowTitle == "ComputelessComputer/openbird")
        #expect(sanitized.visibleText == "PR fixes calendar sync behavior\nhttps://github.com/ComputelessComputer/openbird")
    }
}
