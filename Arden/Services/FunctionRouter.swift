import Foundation

struct ExecutionResult {
    let success: Bool
    let message: String
    let data: [String: Any]?

    init(success: Bool, message: String, data: [String: Any]? = nil) {
        self.success = success
        self.message = message
        self.data = data
    }
}

@MainActor
class FunctionRouter {
    private let productivityIntegration = ProductivityIntegration()
    private let deviceIntegration = DeviceIntegration()
    private let communicationIntegration = CommunicationIntegration()
    private let informationIntegration = InformationIntegration()

    func execute(intent: IntentType, parameters: [String: AnyCodable]) async throws -> ExecutionResult {
        let params = parameters.mapValues { $0.value }

        switch intent {
        case .calendar:
            return try await productivityIntegration.createCalendarEvent(params: params)

        case .reminder:
            return try await productivityIntegration.createReminder(params: params)

        case .timer:
            return try await productivityIntegration.startTimer(params: params)

        case .note:
            return try await productivityIntegration.createNote(params: params)

        case .alarm:
            return try await productivityIntegration.createAlarm(params: params)

        case .message:
            return try await communicationIntegration.sendMessage(params: params)

        case .email:
            return try await communicationIntegration.composeEmail(params: params)

        case .call:
            return try await communicationIntegration.makeCall(params: params)

        case .flashlight:
            return try await deviceIntegration.controlFlashlight(params: params)

        case .camera:
            return try await deviceIntegration.openCamera(params: params)

        case .volume:
            return try await deviceIntegration.adjustVolume(params: params)

        case .brightness:
            return try await deviceIntegration.adjustBrightness(params: params)

        case .wifi:
            return try await deviceIntegration.toggleWiFi(params: params)

        case .bluetooth:
            return try await deviceIntegration.toggleBluetooth(params: params)

        case .calculation:
            return await informationIntegration.calculate(params: params)

        case .weather:
            return try await informationIntegration.getWeather(params: params)

        case .dateTime:
            return await informationIntegration.getDateTime(params: params)

        case .unitConversion:
            return await informationIntegration.convertUnits(params: params)

        case .unknown:
            return ExecutionResult(
                success: false,
                message: "I'm not sure how to help with that. Could you rephrase?"
            )
        }
    }

    func extractParameter<T>(_ params: [String: Any], key: String, type: T.Type) throws -> T {
        guard let value = params[key] as? T else {
            throw RouterError.missingParameter(key)
        }
        return value
    }

    func extractOptionalParameter<T>(_ params: [String: Any], key: String, type: T.Type) -> T? {
        return params[key] as? T
    }
}

enum RouterError: LocalizedError {
    case missingParameter(String)
    case invalidParameter(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .invalidParameter(let param):
            return "Invalid parameter value: \(param)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}
