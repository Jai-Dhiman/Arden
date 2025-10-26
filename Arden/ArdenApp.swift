import SwiftUI

@main
struct ArdenApp: App {
    @StateObject private var assistantService = AssistantService()
    @StateObject private var speechService = SpeechService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(assistantService)
                .environmentObject(speechService)
                .onAppear {
                    Task {
                        await assistantService.loadModel()
                    }
                }
        }
    }
}
