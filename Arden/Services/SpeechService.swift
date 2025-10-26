import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechService: NSObject, ObservableObject {
    @Published var isListening = false
    @Published var transcription = ""
    @Published var isAuthorized = false
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    override init() {
        super.init()
        setupAudioSession()
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.isAuthorized = status == .authorized
                    if !self.isAuthorized {
                        self.errorMessage = "Speech recognition authorization denied"
                    }
                    continuation.resume(returning: self.isAuthorized)
                }
            }
        }
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
        }
    }

    func startListening(onResult: @escaping (String) -> Void) throws {
        guard isAuthorized else {
            throw SpeechError.notAuthorized
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        if audioEngine?.isRunning == true {
            stopListening()
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.recognitionRequestFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        if speechRecognizer.supportsOnDeviceRecognition {
            recognitionRequest.requiresOnDeviceRecognition = true
        }

        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw SpeechError.audioEngineFailed
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
        transcription = ""

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            var isFinal = false

            if let result = result {
                Task { @MainActor in
                    self.transcription = result.bestTranscription.formattedString
                }
                isFinal = result.isFinal
            }

            if error != nil || isFinal {
                audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                Task { @MainActor in
                    self.isListening = false

                    if isFinal && !self.transcription.isEmpty {
                        onResult(self.transcription)
                    }
                }
            }
        }
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        isListening = false
    }

    func speak(text: String) async {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        await withCheckedContinuation { continuation in
            let delegate = SpeechSynthesizerDelegate {
                continuation.resume()
            }

            synthesizer.delegate = delegate

            synthesizer.speak(utterance)

            withExtendedLifetime(delegate) {
            }
        }
    }
}

private class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        completion()
    }
}

enum SpeechError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case recognitionRequestFailed
    case audioEngineFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition is not authorized"
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .recognitionRequestFailed:
            return "Failed to create recognition request"
        case .audioEngineFailed:
            return "Failed to initialize audio engine"
        }
    }
}
