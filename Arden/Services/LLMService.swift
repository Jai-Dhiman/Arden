import Foundation
import MLX
import MLXNN
import MLXLLM

@MainActor
class LLMService: ObservableObject {
    @Published var isModelLoaded = false
    @Published var loadingProgress: Double = 0.0
    @Published var errorMessage: String?

    private var modelConfiguration: ModelConfiguration?
    private var model: LLMModel?
    private var tokenizer: Tokenizer?

    #if targetEnvironment(simulator)
    private let isSimulator = true
    private let useMockResponses = true
    #else
    private let isSimulator = false
    private let useMockResponses = false
    #endif

    private let systemPrompt = """
You are an advanced offline voice assistant running on iPhone. Your role is to understand user commands and respond with structured JSON output that maps to system integrations.

CRITICAL: You MUST respond ONLY with valid JSON in the following format:
{
  "intent": "calendar|reminder|timer|note|alarm|message|email|call|flashlight|camera|volume|brightness|wifi|bluetooth|calculation|weather|dateTime|unitConversion|unknown",
  "parameters": {
    // Intent-specific parameters as key-value pairs
  },
  "confidence": 0.95,
  "needsConfirmation": false,
  "naturalLanguageResponse": "I'll create a reminder for you."
}

INTENT SCHEMAS:

calendar: {"title": str, "date": ISO8601, "time": ISO8601, "duration": minutes, "location": str?}
reminder: {"title": str, "date": ISO8601?, "time": ISO8601?, "priority": "low|medium|high"}
timer: {"duration": seconds, "label": str?}
note: {"title": str, "content": str}
alarm: {"time": ISO8601, "label": str?, "recurring": bool}
message: {"recipient": str, "body": str}
email: {"recipient": str, "subject": str, "body": str}
call: {"recipient": str, "video": bool}
flashlight: {"state": "on|off|toggle"}
camera: {"action": "open|photo|video"}
volume: {"level": 0-100, "change": "up|down|set"}
brightness: {"level": 0-100, "change": "up|down|set"}
wifi: {"state": "on|off|toggle"}
bluetooth: {"state": "on|off|toggle"}
calculation: {"expression": str}
weather: {"location": str?, "when": "now|today|tomorrow"}
dateTime: {"query": "date|time|day|timezone"}
unitConversion: {"value": float, "from": str, "to": str}

RULES:
1. Set confidence based on clarity of user intent (0.0-1.0)
2. Set needsConfirmation=true for destructive actions or ambiguous requests
3. If confidence < 0.7, ask for clarification in naturalLanguageResponse
4. Use ISO8601 format for all dates/times
5. Extract ALL relevant parameters from user input
6. If intent is unclear, use "unknown" and explain in naturalLanguageResponse

Examples:
User: "Set a timer for 5 minutes"
{"intent": "timer", "parameters": {"duration": 300, "label": null}, "confidence": 0.99, "needsConfirmation": false, "naturalLanguageResponse": "Starting a 5-minute timer."}

User: "Remind me to call mom tomorrow at 2pm"
{"intent": "reminder", "parameters": {"title": "Call mom", "date": "2025-10-26", "time": "14:00"}, "confidence": 0.95, "needsConfirmation": false, "naturalLanguageResponse": "I'll remind you to call mom tomorrow at 2 PM."}

User: "Turn on the flashlight"
{"intent": "flashlight", "parameters": {"state": "on"}, "confidence": 1.0, "needsConfirmation": false, "naturalLanguageResponse": "Turning on the flashlight."}
"""

    func loadModel() async {
        guard !isModelLoaded else { return }

        #if targetEnvironment(simulator)
        if useMockResponses {
            print("🎭 SIMULATOR MODE: Using mock LLM responses for fast testing")
            print("🎭 UI and integrations will work, but using pre-defined responses")
            print("🎭 For real LLM testing, use a physical device")

            loadingProgress = 1.0
            isModelLoaded = true
            return
        } else {
            print("⚠️  SIMULATOR MODE: Real LLM will be VERY slow (5-30 seconds per query)")
            print("⚠️  Consider setting useMockResponses = true for faster testing")
        }
        #endif

        do {
            loadingProgress = 0.1

            let modelName = "mlx-community/Phi-3.5-mini-instruct-4bit"

            loadingProgress = 0.3

            let modelConfig = ModelConfiguration.phi3_5MiniInstruct4bit
            self.modelConfiguration = modelConfig

            loadingProgress = 0.5

            let loadedModel = try await LLMModel.load(configuration: modelConfig)
            self.model = loadedModel

            loadingProgress = 0.8

            let loadedTokenizer = try await loadConfiguration(modelName: modelName).tokenizer
            self.tokenizer = loadedTokenizer

            loadingProgress = 1.0
            isModelLoaded = true

        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            print("Error loading model: \(error)")
        }
    }

    func generate(userInput: String, conversationHistory: [ConversationMessage] = []) async throws -> String {
        #if targetEnvironment(simulator)
        if useMockResponses {
            print("🎭 Mock LLM response for: \"\(userInput)\"")
            return mockResponse(for: userInput)
        }
        #endif

        guard isModelLoaded, let model = model, let tokenizer = tokenizer else {
            throw LLMError.modelNotLoaded
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]

        for message in conversationHistory.suffix(5) {
            messages.append([
                "role": message.isUser ? "user" : "assistant",
                "content": message.text
            ])
        }

        messages.append(["role": "user", "content": userInput])

        let prompt = try formatChatPrompt(messages: messages, tokenizer: tokenizer)

        let tokens = tokenizer.encode(text: prompt)

        var generatedTokens: [Int] = []
        let maxTokens = 512

        let parameters = GenerateParameters(
            temperature: 0.1,
            topP: 0.9,
            repetitionPenalty: 1.1
        )

        for try await token in model.generate(promptTokens: tokens, parameters: parameters) {
            generatedTokens.append(token)

            if generatedTokens.count >= maxTokens {
                break
            }

            if token == tokenizer.eosTokenId {
                break
            }
        }

        let response = tokenizer.decode(tokens: generatedTokens)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        #if targetEnvironment(simulator)
        print("🐌 Simulator LLM took \(Int(elapsed))ms (would be ~\(Int(elapsed/20))ms on device)")
        #else
        print("⚡️ LLM inference took \(Int(elapsed))ms")
        #endif

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mockResponse(for input: String) -> String {
        let lowercased = input.lowercased()

        if lowercased.contains("timer") && lowercased.contains("minute") {
            let minutes = extractNumber(from: input) ?? 5
            return """
            {
              "intent": "timer",
              "parameters": {"duration": \(minutes * 60), "label": null},
              "confidence": 0.95,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Starting a \(minutes)-minute timer."
            }
            """
        } else if lowercased.contains("flashlight") || lowercased.contains("flash") {
            let state = lowercased.contains("off") ? "off" : "on"
            return """
            {
              "intent": "flashlight",
              "parameters": {"state": "\(state)"},
              "confidence": 0.99,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Turning \(state) the flashlight."
            }
            """
        } else if lowercased.contains("time") && !lowercased.contains("timer") {
            return """
            {
              "intent": "dateTime",
              "parameters": {"query": "time"},
              "confidence": 0.95,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Let me tell you the current time."
            }
            """
        } else if lowercased.contains("date") && !lowercased.contains("update") {
            return """
            {
              "intent": "dateTime",
              "parameters": {"query": "date"},
              "confidence": 0.95,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Let me tell you today's date."
            }
            """
        } else if lowercased.contains("remind") {
            return """
            {
              "intent": "reminder",
              "parameters": {"title": "Task", "date": null, "time": null, "priority": "medium"},
              "confidence": 0.85,
              "needsConfirmation": false,
              "naturalLanguageResponse": "I'll create a reminder for you."
            }
            """
        } else if lowercased.contains("calendar") || lowercased.contains("event") {
            return """
            {
              "intent": "calendar",
              "parameters": {"title": "Event", "date": null, "time": null, "duration": 60},
              "confidence": 0.85,
              "needsConfirmation": false,
              "naturalLanguageResponse": "I'll create a calendar event."
            }
            """
        } else if lowercased.contains("message") || lowercased.contains("text") {
            return """
            {
              "intent": "message",
              "parameters": {"recipient": "contact", "body": "message text"},
              "confidence": 0.85,
              "needsConfirmation": true,
              "naturalLanguageResponse": "I'll send that message."
            }
            """
        } else if lowercased.contains("email") {
            return """
            {
              "intent": "email",
              "parameters": {"recipient": "contact", "subject": "Subject", "body": "Body"},
              "confidence": 0.85,
              "needsConfirmation": true,
              "naturalLanguageResponse": "I'll compose that email."
            }
            """
        } else if lowercased.contains("call") {
            return """
            {
              "intent": "call",
              "parameters": {"recipient": "contact", "video": false},
              "confidence": 0.90,
              "needsConfirmation": true,
              "naturalLanguageResponse": "I'll make that call."
            }
            """
        } else if lowercased.contains("camera") {
            return """
            {
              "intent": "camera",
              "parameters": {"action": "open"},
              "confidence": 0.95,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Opening the camera."
            }
            """
        } else if lowercased.contains("brightness") {
            let change = lowercased.contains("increase") || lowercased.contains("up") ? "up" :
                        lowercased.contains("decrease") || lowercased.contains("down") ? "down" : "up"
            return """
            {
              "intent": "brightness",
              "parameters": {"change": "\(change)"},
              "confidence": 0.90,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Adjusting brightness."
            }
            """
        } else if lowercased.contains("volume") {
            let change = lowercased.contains("increase") || lowercased.contains("up") ? "up" :
                        lowercased.contains("decrease") || lowercased.contains("down") ? "down" : "up"
            return """
            {
              "intent": "volume",
              "parameters": {"change": "\(change)"},
              "confidence": 0.90,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Adjusting volume."
            }
            """
        } else if lowercased.contains("calculate") || lowercased.contains("plus") || lowercased.contains("times") || lowercased.contains("divided") {
            return """
            {
              "intent": "calculation",
              "parameters": {"expression": "5+5"},
              "confidence": 0.80,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Let me calculate that."
            }
            """
        } else if lowercased.contains("weather") {
            return """
            {
              "intent": "weather",
              "parameters": {"location": null, "when": "now"},
              "confidence": 0.90,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Let me check the weather."
            }
            """
        } else if lowercased.contains("convert") {
            return """
            {
              "intent": "unitConversion",
              "parameters": {"value": 100, "from": "miles", "to": "kilometers"},
              "confidence": 0.75,
              "needsConfirmation": false,
              "naturalLanguageResponse": "Converting units."
            }
            """
        } else {
            return """
            {
              "intent": "unknown",
              "parameters": {},
              "confidence": 0.4,
              "needsConfirmation": false,
              "naturalLanguageResponse": "I'm not sure how to help with that. This is a simulated response for testing."
            }
            """
        }
    }

    private func extractNumber(from text: String) -> Int? {
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        let numberWords = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                          "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]

        for word in words {
            if let number = numberWords[word] {
                return number
            }
            if let number = Int(word) {
                return number
            }
        }
        return nil
    }

    private func formatChatPrompt(messages: [[String: String]], tokenizer: Tokenizer) throws -> String {
        var prompt = ""

        for message in messages {
            guard let role = message["role"], let content = message["content"] else {
                continue
            }

            switch role {
            case "system":
                prompt += "<|system|>\n\(content)<|end|>\n"
            case "user":
                prompt += "<|user|>\n\(content)<|end|>\n"
            case "assistant":
                prompt += "<|assistant|>\n\(content)<|end|>\n"
            default:
                break
            }
        }

        prompt += "<|assistant|>\n"

        return prompt
    }

    func parseResponse(_ rawResponse: String) throws -> AssistantResponse {
        let jsonString = extractJSON(from: rawResponse)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw LLMError.invalidResponse
        }

        let decoder = JSONDecoder()
        let response = try decoder.decode(AssistantResponse.self, from: jsonData)

        return response
    }

    private func extractJSON(from text: String) -> String {
        if let jsonStart = text.range(of: "{"),
           let jsonEnd = text.range(of: "}", options: .backwards) {
            return String(text[jsonStart.lowerBound...jsonEnd.upperBound])
        }

        return text
    }
}

enum LLMError: LocalizedError {
    case modelNotLoaded
    case invalidResponse
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model is not loaded. Please wait for initialization."
        case .invalidResponse:
            return "Failed to parse model response."
        case .generationFailed:
            return "Failed to generate response."
        }
    }
}
