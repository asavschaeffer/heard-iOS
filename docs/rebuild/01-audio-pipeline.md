# Audio Pipeline: End-to-End Deep Dive

## Overview

The audio pipeline handles bidirectional voice communication between the user's microphone and Gemini Live API. Audio flows in two directions:
- **Capture**: Microphone → resample → PCM16 → base64 → WebSocket → Gemini
- **Playback**: Gemini → WebSocket → base64 → PCM16 → AVAudioPlayerNode → speaker

## Current Architecture

The voice stack is no longer owned directly by `ChatViewModel`. It is now split into the `VoiceCore` module under `Modules/VoiceCore/Sources/VoiceCore/`:
- `VoiceCallCoordinator`: Owns call lifecycle, route adaptation, CallKit wiring, and call-facing state publication.
- `VoiceAudioSessionController`: Owns `AVAudioSession` category, mode, route descriptions, and route/interruption interpretation.
- `VoiceCaptureEngine`: Owns microphone capture, resampling to 16 kHz PCM16, mute-aware chunk emission, and voice-processing fallback.
- `VoicePlaybackEngine`: Owns playback graph setup, 24 kHz PCM playout, queue tracking, and restart-after-route-change behavior.
- `VoiceDiagnostics`: Gates verbose voice logs to debug builds while still allowing faults in release builds.

`ChatViewModel` now acts as the bridge between Gemini transport events and the voice subsystem. It still owns chat messages, transcripts, reconnect scheduling, and other UI-facing state.

The subsystem tests now live under `Modules/VoiceCore/Tests/VoiceCoreTests/` and should remain the primary automated logic surface for voice behavior.

## Current State (Implemented)

The two historical correctness fixes remain in place:
- Capture is explicitly resampled to 16 kHz PCM16 before being sent to Gemini.
- Playback is configured for Gemini's 24 kHz response audio instead of 16 kHz.
- Receiver and speaker flips rebuild the local capture/playback graphs when the route change requires it, while preserving the active Gemini websocket session.

## Historical Bugs (Fixed)

### Bug A: Capture sends wrong sample rate

**File**: `app/Views/Chat/ChatViewModel.swift` lines 435-491

The capture tap uses `inputNode.outputFormat(forBus: 0)` which returns the **device's native sample rate** (typically 44.1kHz or 48kHz). The `convertToPCM16()` function converts float32 → Int16 but **does not resample**. The WebSocket declares `audio/pcm;rate=16000`, so Gemini receives 48kHz audio labeled as 16kHz — garbled input.

```swift
// Current (broken):
let format = inputNode.outputFormat(forBus: 0)  // ← 44.1kHz or 48kHz
inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
    self?.processAudioBuffer(buffer)
}

// convertToPCM16 just clips float→Int16, no resampling:
private func convertToPCM16(buffer: AVAudioPCMBuffer) -> Data {
    guard let channelData = buffer.floatChannelData?[0] else { return Data() }
    let frameLength = Int(buffer.frameLength)
    var pcmData = Data(capacity: frameLength * 2)
    for i in 0..<frameLength {
        let sample = Int16(max(-1, min(1, channelData[i])) * Float(Int16.max))
        withUnsafeBytes(of: sample.littleEndian) { pcmData.append(contentsOf: $0) }
    }
    return pcmData
}
```

### Bug B: Playback configured at wrong rate

**File**: `app/Views/Chat/ChatViewModel.swift` lines 531-551

Playback engine is configured at 16kHz but Gemini Live API returns audio at **24kHz**.

```swift
// Current (wrong rate):
let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)
```

Playing 24kHz audio at 16kHz makes everything sound slow and distorted.

## The Fix

### Capture: Add AVAudioConverter for resampling

```swift
private var audioConverter: AVAudioConverter?
private var targetFormat: AVAudioFormat?

private func startAudioCapture() {
    if audioEngine?.isRunning == true { return }

    audioEngine = AVAudioEngine()
    guard let audioEngine = audioEngine else { return }

    let inputNode = audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    // Create target format: 16kHz, mono, Int16
    let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                sampleRate: 16000, channels: 1,
                                interleaved: false)!
    targetFormat = target
    audioConverter = AVAudioConverter(from: inputFormat, to: target)

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
        self?.processAudioBuffer(buffer)
    }

    do {
        try audioEngine.start()
    } catch {
        print("Audio Engine Start Error: \(error)")
    }
}
```

### Capture: Resample in processAudioBuffer

```swift
private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData?[0] else { return }
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return }

    // 1. Audio level for UI
    var sum: Float = 0
    for i in 0..<frameLength { sum += abs(channelData[i]) }
    let average = sum / Float(frameLength)
    Task { @MainActor in
        self.callState.audioLevel = min(1.0, average * 10)
    }

    // 2. Resample to 16kHz PCM16 and send
    guard let converter = audioConverter, let target = targetFormat else { return }
    let ratio = target.sampleRate / buffer.format.sampleRate
    let capacity = UInt32(Double(buffer.frameLength) * ratio)
    guard capacity > 0,
          let convertedBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

    var error: NSError?
    var inputConsumed = false
    converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
        if inputConsumed {
            outStatus.pointee = .noDataNow
            return nil
        }
        inputConsumed = true
        outStatus.pointee = .haveData
        return buffer
    }

    if let error { print("Audio conversion error: \(error)"); return }

    // Extract Int16 data from converted buffer
    let data = Data(bytes: convertedBuffer.int16ChannelData![0],
                    count: Int(convertedBuffer.frameLength) * 2)
    geminiService?.sendAudio(data: data)
}
```

### Playback: Fix sample rate to 24kHz

```swift
private func setupPlaybackEngineIfNeeded() {
    if playbackEngine != nil { return }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)

    // Gemini Live API outputs 24kHz PCM16 mono
    let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                               sampleRate: 24_000, channels: 1,
                               interleaved: false)
    engine.connect(player, to: engine.mainMixerNode, format: format)

    do {
        try engine.start()
    } catch {
        print("Audio Playback Engine Error: \(error)")
        return
    }

    playbackEngine = engine
    playbackNode = player
    playbackFormat = format
}
```

### Mute: Flag-based instead of engine restart

```swift
private var isMuted = false

func toggleMute() {
    isMuted.toggle()
    callState.isListening = !isMuted
    // Don't stop/start the engine — just skip sending packets
}

private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
    // Still compute audio level for UI even when muted
    // ...

    guard !isMuted else { return }  // Skip sending when muted

    // Resample and send...
}
```

## Reference SDK Patterns

### swift-gemini-api
- Uses `AVAudioConverter` for format conversion
- Encapsulates PCM format specs to prevent rate mismatches
- May batch audio frames to reduce WebSocket overhead

### GetStream (stream-video-swift)
- Uses `AVAudioConverter` for resampling between device and network formats
- Maintains separate capture and playback engines
- Handles audio route changes gracefully

### LiveKit (client-sdk-swift)
- `AudioManager` class controls audio engine lifecycle
- Automatic `AVAudioSession` configuration (can be disabled for CallKit)
- `AudioEngineObserver` chains for processing audio

### 100ms (hms-roomkit-ios)
- Automatic audio session management by default
- Toggle methods: `toggleMic()`, `toggleCamera()`, `leaveSession()`
- Audio session lifecycle tied to room state

## Verification

After fixing:
1. Start a voice call
2. Speak — Gemini should understand you clearly (no garbled input)
3. Gemini responds — audio should sound at normal speed/pitch (not slow)
4. Mute toggle should be instant (no audio engine restart delay)
5. Check audio levels UI still updates while muted
