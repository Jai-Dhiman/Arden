import Foundation

struct AssistantResponse: Codable {
    let intent: String
    let parameters: [String: AnyCodable]
    let confidence: Double
    let needsConfirmation: Bool
    let naturalLanguageResponse: String
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Unsupported type"
                )
            )
        }
    }
}

enum IntentType: String, Codable {
    case calendar
    case reminder
    case timer
    case note
    case alarm
    case message
    case email
    case call
    case flashlight
    case camera
    case volume
    case brightness
    case wifi
    case bluetooth
    case calculation
    case weather
    case dateTime
    case unitConversion
    case unknown
}

struct ConversationMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
    let intent: IntentType?
    let requiresConfirmation: Bool

    init(text: String, isUser: Bool, intent: IntentType? = nil, requiresConfirmation: Bool = false) {
        self.text = text
        self.isUser = isUser
        self.timestamp = Date()
        self.intent = intent
        self.requiresConfirmation = requiresConfirmation
    }
}

struct IntentConfidence {
    let intent: IntentType
    let confidence: Double
    let parameters: [String: Any]
}
