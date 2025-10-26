import Foundation
import AVFoundation
import UIKit

@MainActor
class DeviceIntegration {
    private var flashlightOn = false

    func controlFlashlight(params: [String: Any]) async throws -> ExecutionResult {
        guard let state = params["state"] as? String else {
            throw IntegrationError.missingParameter("state")
        }

        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            throw IntegrationError.executionFailed("Flashlight not available on this device")
        }

        do {
            try device.lockForConfiguration()

            let shouldTurnOn: Bool
            switch state.lowercased() {
            case "on":
                shouldTurnOn = true
            case "off":
                shouldTurnOn = false
            case "toggle":
                shouldTurnOn = !flashlightOn
            default:
                throw IntegrationError.executionFailed("Invalid flashlight state: \(state)")
            }

            if shouldTurnOn {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                flashlightOn = true
            } else {
                device.torchMode = .off
                flashlightOn = false
            }

            device.unlockForConfiguration()

            return ExecutionResult(
                success: true,
                message: "Flashlight turned \(shouldTurnOn ? "on" : "off")"
            )
        } catch {
            throw IntegrationError.executionFailed("Failed to control flashlight: \(error.localizedDescription)")
        }
    }

    func openCamera(params: [String: Any]) async throws -> ExecutionResult {
        guard let action = params["action"] as? String else {
            throw IntegrationError.missingParameter("action")
        }

        var urlString: String
        switch action.lowercased() {
        case "open", "photo":
            urlString = "camera://"
        case "video":
            urlString = "camera://video"
        default:
            throw IntegrationError.executionFailed("Invalid camera action: \(action)")
        }

        guard let url = URL(string: urlString) else {
            throw IntegrationError.executionFailed("Invalid camera URL")
        }

        if await UIApplication.shared.canOpenURL(url) {
            await UIApplication.shared.open(url)
            return ExecutionResult(
                success: true,
                message: "Opening camera"
            )
        } else {
            throw IntegrationError.executionFailed("Cannot open camera")
        }
    }

    func adjustVolume(params: [String: Any]) async throws -> ExecutionResult {
        let level = params["level"] as? Int
        let change = params["change"] as? String

        if let change = change {
            return ExecutionResult(
                success: true,
                message: "Volume \(change). (Note: Programmatic volume control requires MPVolumeView and is limited on iOS)",
                data: ["change": change]
            )
        } else if let level = level {
            return ExecutionResult(
                success: true,
                message: "Volume set to \(level)%. (Note: Programmatic volume control requires MPVolumeView and is limited on iOS)",
                data: ["level": level]
            )
        } else {
            throw IntegrationError.missingParameter("level or change")
        }
    }

    func adjustBrightness(params: [String: Any]) async throws -> ExecutionResult {
        let level = params["level"] as? Int
        let change = params["change"] as? String

        if let change = change {
            let currentBrightness = await UIScreen.main.brightness
            var newBrightness = currentBrightness

            switch change.lowercased() {
            case "up":
                newBrightness = min(1.0, currentBrightness + 0.1)
            case "down":
                newBrightness = max(0.0, currentBrightness - 0.1)
            default:
                throw IntegrationError.executionFailed("Invalid brightness change: \(change)")
            }

            await MainActor.run {
                UIScreen.main.brightness = newBrightness
            }

            return ExecutionResult(
                success: true,
                message: "Brightness adjusted \(change)"
            )
        } else if let level = level {
            let brightness = CGFloat(level) / 100.0
            await MainActor.run {
                UIScreen.main.brightness = max(0.0, min(1.0, brightness))
            }

            return ExecutionResult(
                success: true,
                message: "Brightness set to \(level)%"
            )
        } else {
            throw IntegrationError.missingParameter("level or change")
        }
    }

    func toggleWiFi(params: [String: Any]) async throws -> ExecutionResult {
        guard let state = params["state"] as? String else {
            throw IntegrationError.missingParameter("state")
        }

        if let url = URL(string: "App-prefs:root=WIFI") {
            if await UIApplication.shared.canOpenURL(url) {
                await UIApplication.shared.open(url)
                return ExecutionResult(
                    success: true,
                    message: "Opening Wi-Fi settings. (Note: Direct Wi-Fi toggle is not available via iOS APIs, opening settings instead)"
                )
            }
        }

        throw IntegrationError.executionFailed("Cannot open Wi-Fi settings")
    }

    func toggleBluetooth(params: [String: Any]) async throws -> ExecutionResult {
        guard let state = params["state"] as? String else {
            throw IntegrationError.missingParameter("state")
        }

        if let url = URL(string: "App-prefs:root=Bluetooth") {
            if await UIApplication.shared.canOpenURL(url) {
                await UIApplication.shared.open(url)
                return ExecutionResult(
                    success: true,
                    message: "Opening Bluetooth settings. (Note: Direct Bluetooth toggle is not available via iOS APIs, opening settings instead)"
                )
            }
        }

        throw IntegrationError.executionFailed("Cannot open Bluetooth settings")
    }
}
