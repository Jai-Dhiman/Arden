import AppIntents
import SwiftUI

struct ArdenAssistantIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Arden"
    static var description = IntentDescription("Interact with your offline AI assistant")

    static var openAppWhenRun: Bool = true

    @Parameter(title: "Query", description: "What would you like to ask?")
    var query: String?

    func perform() async throws -> some IntentResult & OpensIntent {
        return .result(opensIntent: ArdenOpenIntent(query: query))
    }
}

struct ArdenOpenIntent: OpenIntent {
    var query: String?

    var target: some AppIntentTarget {
        return ArdenAppTarget(query: query)
    }
}

struct ArdenAppTarget: AppIntentTarget {
    var query: String?
}

struct ArdenShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ArdenAssistantIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Ask Arden",
            systemImageName: "waveform.circle.fill"
        )
    }
}
