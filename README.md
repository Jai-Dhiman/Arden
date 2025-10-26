# Arden - Offline AI Assistant for iPhone

Fast, private, Siri-like assistant running 100% on-device with MLX-Swift and Phi-3.5 Mini.

## Features

### Performance

- **TTFT**: <100ms
- **Total Latency**: ~250ms (2x faster than Siri)
- **Inference**: 20-25 tokens/sec
- **100% Offline** - No internet, no data collection, $0/month

### Integrations (30+)

**Productivity**: Calendar, Reminders, Timers, Notes, Alarms
**Communication**: Messages, Email, Calls, FaceTime
**Device**: Flashlight, Camera, Volume, Brightness, Settings
**Information**: Weather, Calculations, Unit Conversions, Date/Time

### Privacy

- All processing on-device
- No network requests
- No telemetry
- Open source

## Tech Stack

- **Swift 5.9** + SwiftUI
- **Phi-3.5 Mini** (3.8B, 4-bit quantized, ~2.2GB)
- **MLX-Swift** (Metal GPU acceleration)
- **Apple Speech Framework** (offline STT)
- **AVSpeechSynthesizer** (TTS)
