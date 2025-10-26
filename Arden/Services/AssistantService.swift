import Foundation
import SwiftUI

@MainActor
class AssistantService: ObservableObject {
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var isProcessing = false
    @Published var currentIntent: IntentType?
    @Published var pendingConfirmation: AssistantResponse?

    private let llmService = LLMService()
    private let functionRouter = FunctionRouter()

    var isModelLoaded: Bool {
        llmService.isModelLoaded
    }

    var loadingProgress: Double {
        llmService.loadingProgress
    }

    func loadModel() async {
        await llmService.loadModel()
    }

    func processUserInput(_ input: String) async {
        guard !input.isEmpty else { return }

        isProcessing = true

        let userMessage = ConversationMessage(text: input, isUser: true)
        conversationHistory.append(userMessage)

        do {
            let rawResponse = try await llmService.generate(
                userInput: input,
                conversationHistory: conversationHistory
            )

            let response = try llmService.parseResponse(rawResponse)

            if response.confidence < 0.7 {
                let clarificationMessage = ConversationMessage(
                    text: response.naturalLanguageResponse,
                    isUser: false
                )
                conversationHistory.append(clarificationMessage)
                isProcessing = false
                return
            }

            if response.needsConfirmation {
                pendingConfirmation = response
                let confirmMessage = ConversationMessage(
                    text: "\(response.naturalLanguageResponse) Would you like me to proceed?",
                    isUser: false,
                    requiresConfirmation: true
                )
                conversationHistory.append(confirmMessage)
                isProcessing = false
                return
            }

            try await executeIntent(response)

        } catch {
            let errorMessage = ConversationMessage(
                text: "Error: \(error.localizedDescription)",
                isUser: false
            )
            conversationHistory.append(errorMessage)
        }

        isProcessing = false
    }

    func confirmPendingAction() async {
        guard let confirmation = pendingConfirmation else { return }

        isProcessing = true

        do {
            try await executeIntent(confirmation)
        } catch {
            let errorMessage = ConversationMessage(
                text: "Error executing action: \(error.localizedDescription)",
                isUser: false
            )
            conversationHistory.append(errorMessage)
        }

        pendingConfirmation = nil
        isProcessing = false
    }

    func cancelPendingAction() {
        pendingConfirmation = nil

        let cancelMessage = ConversationMessage(
            text: "Action cancelled.",
            isUser: false
        )
        conversationHistory.append(cancelMessage)
    }

    private func executeIntent(_ response: AssistantResponse) async throws {
        guard let intentType = IntentType(rawValue: response.intent) else {
            throw AssistantError.unknownIntent
        }

        currentIntent = intentType

        let result = try await functionRouter.execute(
            intent: intentType,
            parameters: response.parameters
        )

        let resultMessage = ConversationMessage(
            text: result.message,
            isUser: false,
            intent: intentType
        )
        conversationHistory.append(resultMessage)

        currentIntent = nil
    }

    func clearHistory() {
        conversationHistory.removeAll()
    }
}

enum AssistantError: LocalizedError {
    case unknownIntent
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unknownIntent:
            return "Unable to understand the intent"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}
