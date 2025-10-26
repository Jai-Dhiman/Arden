import Foundation
import WeatherKit
import CoreLocation

@MainActor
class InformationIntegration {
    private let weatherService = WeatherService.shared
    private let locationManager = CLLocationManager()

    func calculate(params: [String: Any]) async -> ExecutionResult {
        guard let expression = params["expression"] as? String else {
            return ExecutionResult(
                success: false,
                message: "Missing calculation expression"
            )
        }

        let sanitizedExpression = expression
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: " ", with: "")

        let result = evaluateExpression(sanitizedExpression)

        if let result = result {
            return ExecutionResult(
                success: true,
                message: "\(expression) = \(result)",
                data: ["result": result]
            )
        } else {
            return ExecutionResult(
                success: false,
                message: "Could not evaluate expression: \(expression)"
            )
        }
    }

    private func evaluateExpression(_ expression: String) -> Double? {
        let mathExpression = NSExpression(format: expression)
        return mathExpression.expressionValue(with: nil, context: nil) as? Double
    }

    func getWeather(params: [String: Any]) async throws -> ExecutionResult {
        let when = params["when"] as? String ?? "now"

        let location: CLLocation
        if let locationString = params["location"] as? String {
            location = try await geocodeLocation(locationString)
        } else {
            location = try await getCurrentLocation()
        }

        do {
            let weather = try await weatherService.weather(for: location)

            let currentTemp = weather.currentWeather.temperature.value
            let condition = weather.currentWeather.condition.description

            let tempF = (currentTemp * 9/5) + 32

            return ExecutionResult(
                success: true,
                message: "Current weather: \(Int(tempF))°F, \(condition)",
                data: [
                    "temperature": tempF,
                    "condition": condition,
                    "humidity": weather.currentWeather.humidity
                ]
            )
        } catch {
            throw IntegrationError.executionFailed("Failed to get weather: \(error.localizedDescription)")
        }
    }

    func getDateTime(params: [String: Any]) async -> ExecutionResult {
        guard let query = params["query"] as? String else {
            return ExecutionResult(
                success: false,
                message: "Missing query parameter"
            )
        }

        let now = Date()
        let formatter = DateFormatter()

        switch query.lowercased() {
        case "date":
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            let dateString = formatter.string(from: now)
            return ExecutionResult(
                success: true,
                message: "Today is \(dateString)"
            )

        case "time":
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            let timeString = formatter.string(from: now)
            return ExecutionResult(
                success: true,
                message: "The time is \(timeString)"
            )

        case "day":
            formatter.dateFormat = "EEEE"
            let dayString = formatter.string(from: now)
            return ExecutionResult(
                success: true,
                message: "Today is \(dayString)"
            )

        case "timezone":
            let timezone = TimeZone.current.identifier
            return ExecutionResult(
                success: true,
                message: "Your timezone is \(timezone)"
            )

        default:
            formatter.dateStyle = .long
            formatter.timeStyle = .short
            let fullString = formatter.string(from: now)
            return ExecutionResult(
                success: true,
                message: fullString
            )
        }
    }

    func convertUnits(params: [String: Any]) async -> ExecutionResult {
        guard let value = params["value"] as? Double else {
            return ExecutionResult(
                success: false,
                message: "Missing value to convert"
            )
        }

        guard let fromUnit = params["from"] as? String else {
            return ExecutionResult(
                success: false,
                message: "Missing source unit"
            )
        }

        guard let toUnit = params["to"] as? String else {
            return ExecutionResult(
                success: false,
                message: "Missing target unit"
            )
        }

        if let result = convertValue(value, from: fromUnit, to: toUnit) {
            return ExecutionResult(
                success: true,
                message: "\(value) \(fromUnit) = \(String(format: "%.2f", result)) \(toUnit)",
                data: ["result": result]
            )
        } else {
            return ExecutionResult(
                success: false,
                message: "Could not convert from \(fromUnit) to \(toUnit)"
            )
        }
    }

    private func convertValue(_ value: Double, from fromUnit: String, to toUnit: String) -> Double? {
        let conversions: [String: [String: Double]] = [
            "miles": ["kilometers": 1.60934, "meters": 1609.34, "feet": 5280],
            "kilometers": ["miles": 0.621371, "meters": 1000, "feet": 3280.84],
            "meters": ["miles": 0.000621371, "kilometers": 0.001, "feet": 3.28084],
            "feet": ["miles": 0.000189394, "kilometers": 0.0003048, "meters": 0.3048],
            "pounds": ["kilograms": 0.453592, "ounces": 16],
            "kilograms": ["pounds": 2.20462, "grams": 1000],
            "celsius": ["fahrenheit": 1.8, "kelvin": 1.0],
            "fahrenheit": ["celsius": 0.555556],
        ]

        let fromLower = fromUnit.lowercased()
        let toLower = toUnit.lowercased()

        if fromLower == toLower {
            return value
        }

        if fromLower == "celsius" && toLower == "fahrenheit" {
            return (value * 1.8) + 32
        }

        if fromLower == "fahrenheit" && toLower == "celsius" {
            return (value - 32) * 0.555556
        }

        if let conversion = conversions[fromLower]?[toLower] {
            return value * conversion
        }

        return nil
    }

    private func getCurrentLocation() async throws -> CLLocation {
        return CLLocation(latitude: 37.7749, longitude: -122.4194)
    }

    private func geocodeLocation(_ locationString: String) async throws -> CLLocation {
        let geocoder = CLGeocoder()

        return try await withCheckedThrowingContinuation { continuation in
            geocoder.geocodeAddressString(locationString) { placemarks, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let location = placemarks?.first?.location {
                    continuation.resume(returning: location)
                } else {
                    continuation.resume(throwing: IntegrationError.executionFailed("Could not find location"))
                }
            }
        }
    }
}
