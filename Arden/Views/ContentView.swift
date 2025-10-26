import SwiftUI

struct ContentView: View {
    @EnvironmentObject var assistantService: AssistantService
    @EnvironmentObject var speechService: SpeechService

    @State private var isListening = false
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !assistantService.isModelLoaded {
                        ModelLoadingView(progress: assistantService.loadingProgress)
                    } else {
                        ConversationView()

                        Divider()

                        ControlPanel(isListening: $isListening)
                            .padding()
                    }
                }
            }
            .navigationTitle("Arden Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .onAppear {
            Task {
                await requestPermissions()
            }
        }
    }

    private func requestPermissions() async {
        _ = await speechService.requestAuthorization()
    }
}

struct ModelLoadingView: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Loading AI Model")
                .font(.title2)
                .fontWeight(.semibold)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 200)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}

struct ConversationView: View {
    @EnvironmentObject var assistantService: AssistantService

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if assistantService.conversationHistory.isEmpty {
                        EmptyStateView()
                    } else {
                        ForEach(assistantService.conversationHistory) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if assistantService.isProcessing {
                        TypingIndicator()
                    }
                }
                .padding()
            }
            .onChange(of: assistantService.conversationHistory.count) { _ in
                if let lastMessage = assistantService.conversationHistory.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue.opacity(0.6))

            Text("Ready to assist")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Press the microphone button and start speaking")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
    }
}

struct MessageBubble: View {
    @EnvironmentObject var assistantService: AssistantService
    let message: ConversationMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                Text(message.text)
                    .padding(12)
                    .background(message.isUser ? Color.blue : Color(UIColor.secondarySystemGroupedBackground))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(16)

                if message.requiresConfirmation {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                await assistantService.confirmPendingAction()
                            }
                        }) {
                            Text("Confirm")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.green)
                                .cornerRadius(8)
                        }

                        Button(action: {
                            assistantService.cancelPendingAction()
                        }) {
                            Text("Cancel")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                    }
                }

                if let intent = message.intent {
                    IntentBadge(intent: intent)
                }
            }
            .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser {
                Spacer()
            }
        }
    }
}

struct IntentBadge: View {
    let intent: IntentType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption)

            Text(intent.rawValue.capitalized)
                .font(.caption)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .cornerRadius(8)
    }

    var iconName: String {
        switch intent {
        case .calendar: return "calendar"
        case .reminder: return "bell.fill"
        case .timer: return "timer"
        case .note: return "note.text"
        case .alarm: return "alarm.fill"
        case .message: return "message.fill"
        case .email: return "envelope.fill"
        case .call: return "phone.fill"
        case .flashlight: return "flashlight.on.fill"
        case .camera: return "camera.fill"
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .wifi: return "wifi"
        case .bluetooth: return "bluetooth"
        case .calculation: return "function"
        case .weather: return "cloud.sun.fill"
        case .dateTime: return "clock.fill"
        case .unitConversion: return "arrow.left.arrow.right"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct TypingIndicator: View {
    @State private var animationAmount = 0.0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationAmount == Double(index) ? 1.2 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: animationAmount
                    )
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .onAppear {
            animationAmount = 1.0
        }
    }
}

struct ControlPanel: View {
    @EnvironmentObject var assistantService: AssistantService
    @EnvironmentObject var speechService: SpeechService
    @Binding var isListening: Bool

    var body: some View {
        VStack(spacing: 16) {
            if speechService.isListening {
                Text(speechService.transcription.isEmpty ? "Listening..." : speechService.transcription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            }

            HStack(spacing: 20) {
                Button(action: {
                    assistantService.clearHistory()
                }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(.red)
                        .frame(width: 50, height: 50)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }

                Button(action: {
                    toggleListening()
                }) {
                    ZStack {
                        Circle()
                            .fill(speechService.isListening ? Color.red : Color.blue)
                            .frame(width: 70, height: 70)

                        if speechService.isListening {
                            Circle()
                                .stroke(Color.red.opacity(0.3), lineWidth: 4)
                                .frame(width: 85, height: 85)
                                .scaleEffect(isListening ? 1.2 : 1.0)
                                .opacity(isListening ? 0.0 : 1.0)
                                .animation(
                                    Animation.easeInOut(duration: 1.5)
                                        .repeatForever(autoreverses: false),
                                    value: isListening
                                )
                        }

                        Image(systemName: speechService.isListening ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }
                .onAppear {
                    isListening = true
                }

                Button(action: {
                }) {
                    Image(systemName: "keyboard")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 50, height: 50)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }
            }
        }
    }

    private func toggleListening() {
        if speechService.isListening {
            speechService.stopListening()
        } else {
            do {
                try speechService.startListening { transcription in
                    Task {
                        await assistantService.processUserInput(transcription)

                        if let lastMessage = assistantService.conversationHistory.last,
                           !lastMessage.isUser {
                            await speechService.speak(text: lastMessage.text)
                        }
                    }
                }
            } catch {
                print("Failed to start listening: \(error)")
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("Model")
                        Spacer()
                        Text("Phi-3.5 Mini (4-bit)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Model Size")
                        Spacer()
                        Text("~2.2 GB")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Mode")
                        Spacer()
                        Text("Offline")
                            .foregroundColor(.green)
                    }
                } header: {
                    Text("Model Information")
                }

                Section {
                    HStack {
                        Image(systemName: "calendar")
                        Text("Calendar & Reminders")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Image(systemName: "message.fill")
                        Text("Messages & Email")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Image(systemName: "flashlight.on.fill")
                        Text("Device Controls")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Image(systemName: "cloud.sun.fill")
                        Text("Weather & Information")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                } header: {
                    Text("Integrations")
                }

                Section {
                    Text("Arden Assistant is a fully offline AI assistant running on your device. All processing happens locally, ensuring your privacy and data security.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AssistantService())
        .environmentObject(SpeechService())
}
