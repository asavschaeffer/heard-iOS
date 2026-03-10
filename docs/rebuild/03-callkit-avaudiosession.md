# CallKit + AVAudioSession: Deep Dive

## Overview

For a native "phone call" experience, three Apple frameworks work together:
- **AVAudioSession**: Configures the audio hardware (mic input, speaker output, routing)
- **CallKit**: Integrates with the iOS system call UI (shows call in recents, interruption handling, mute from Control Center)
- **ActivityKit (Live Activity)**: Shows call status in Dynamic Island when the app is backgrounded

## Current Architecture

CallKit and `AVAudioSession` ownership now live behind `VoiceCallCoordinator` and `VoiceAudioSessionController` instead of sitting directly in `ChatViewModel`.
- `CallKitManager` remains closure-based and is consumed only by `VoiceCallCoordinator`.
- `VoiceAudioSessionController` is the only place that sets `.playAndRecord`, `.voiceChat`, preferred input, or output overrides.
- `VoiceCallCoordinator` owns route-change handling, interruption handling, and the decision to rebuild local audio graphs on receiver/speaker transitions.
- `ChatViewModel` no longer talks to `AVAudioSession`, `AVAudioEngine`, or `CallKitManager` directly.

## Current Implementation

### AVAudioSession Setup

**Files**: `app/Services/Voice/VoiceAudioSessionController.swift`, `app/Services/Voice/VoiceCallCoordinator.swift`

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
try session.setActive(true)
```

This is correct. The key options:
- `.playAndRecord`: Enables simultaneous mic input and speaker output
- `.voiceChat`: Optimizes for voice (reduces latency, enables echo cancellation)
- `.defaultToSpeaker`: Routes to loudspeaker by default (FaceTime behavior)
- `.allowBluetoothHFP`: Allows Bluetooth headsets (HFP profile for calls)

### Speakerphone Toggle

Speaker preference is now routed through `VoiceCallCoordinator.toggleSpeaker()`. The coordinator reasserts the correct CallKit session when CallKit owns audio, and route overrides are treated as local graph-reconfiguration events instead of pure UI state changes.

### CallKit Integration

**File**: `app/Services/CallKitManager.swift`

The implementation remains intentionally small:

```
startCall() → CXStartCallAction → system registers call
                                 → didActivate(audioSession:) callback
                                     → onStartAudio closure fires
                                         → VoiceCallCoordinator.handleCallKitDidActivate()
                                             → VoiceAudioSessionController.configureActiveCallKitSession()
                                             → VoiceCaptureEngine.start()

endCall() → CXEndCallAction → system deregisters call
                             → didDeactivate(audioSession:) callback
                                 → onStopAudio closure fires
                                     → stopAudioCapture()

Mute from Control Center → CXSetMutedCallAction
                          → onMuteChanged(isMuted) callback
```

### Current Behavior

1. `reportConnected()` is now triggered from the coordinator after Gemini transport connects, so the coordinator is the single CallKit consumer.
2. CallKit-owned route overrides preserve `voiceChat` mode and may rebuild the local audio graphs when the output route changes.
3. Verbose CallKit and route logs are now funneled through `VoiceDiagnostics`, which keeps them in debug builds and quiets them in release builds.

### What's Missing

1. **Incoming call support**: Not applicable for the AI call model, but the app still only supports the outgoing-call path.

2. **Broader automated coverage**: The new subsystem adds unit coverage for coordinator and session policy decisions, but physical route validation is still required for receiver, speaker, Bluetooth, and interruption behavior.

3. **Live Activity**: `LiveActivityManager` is still a stub, so there is no Dynamic Island presence when the app backgrounds during a call.

## The Call Lifecycle (How It Should Work)

### Starting a Call

```
1. User taps phone icon in nav bar
2. ChatView: callPresentationStyle = .fullScreen
3. CallView appears → .onAppear triggers startVoiceSession()
4. startVoiceSession():
   a. callState.isPresented = true
   b. liveActivityManager.startCallActivity()  → Dynamic Island appears
   c. callKitManager.startCall() → System registers outgoing call
   d. connect(mode: .audio) → WebSocket connection begins
5. CallKit: didActivate(audioSession:) fires → onStartAudio callback
   a. configureAudioSessionForCall() → AVAudioSession configured
   b. startAudioCapture() → AVAudioEngine starts, tap installed
   c. callState.isListening = true
6. WebSocket: setupComplete received → geminiServiceDidConnect()
   a. connectionState = .connected
   b. startCallTimer()
   c. callKitManager.reportConnected() → System shows "connected"
   d. flushPendingMessages()
7. Audio flows bidirectionally
```

### During a Call

```
User speaks → AVAudioEngine tap → resample → WebSocket → Gemini
Gemini responds → WebSocket → audio data → AVAudioPlayerNode → speaker
User toggles mute → isMuted flag → audio packets stop/resume
User changes audio route → AVRoutePickerView → system handles routing
App backgrounded → Dynamic Island shows call status
Dynamic Island tapped → app foregrounded, call screen shown
```

### Ending a Call

```
1. User taps End button
2. Show "Call Ended" overlay (1.5s)
3. stopVoiceSession():
   a. callState.isPresented = false
   b. liveActivityManager.endCallActivity() → Dynamic Island dismisses
   c. callKitManager.endCall() → CXEndCallAction
   d. CallKit: didDeactivate(audioSession:) → onStopAudio → stopAudioCapture()
   e. geminiService.disconnect() → WebSocket closes
   f. resetCallTimer()
4. Dismiss call screen
```

### Dismissing Without Ending (Audio-Only)

For audio calls, when the user swipes down or navigates away:
- The call continues in the background
- Dynamic Island shows call indicator with duration
- Tapping Dynamic Island returns to call screen
- This requires ActivityKit implementation (currently stubbed)

## CallKit + AVAudioSession Interaction

### Critical: AVAudioSession is owned by CallKit during a call

When CallKit is active, **CallKit owns the audio session**. This means:
- You should NOT call `setCategory()` or `setActive()` yourself
- Wait for `didActivate(audioSession:)` before starting your audio engine
- The system may change the sample rate — always check after activation

```swift
func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    // The system activated the audio session — NOW start your engine
    // The sample rate may have changed from what you expected
    let actualRate = audioSession.sampleRate
    print("Activated with sample rate: \(actualRate)")
    onStartAudio?()
}
```

### What GetStream/100ms do

Both SDKs:
1. Disable automatic audio session configuration when CallKit is used
2. Let CallKit manage the audio session lifecycle
3. Create their audio engine AFTER `didActivate` fires
4. Destroy their audio engine on `didDeactivate`

### Route Change Handling

```swift
// Already implemented in ChatViewModel.observeAudioSession()
// Watches AVAudioSession.routeChangeNotification
// Updates callState.isListening based on output availability
```

This is correct but could be enhanced to detect specific route changes (Bluetooth connected/disconnected, headphones plugged/unplugged).

## Live Activity (Dynamic Island) — TODO

**File**: `app/Services/LiveActivityManager.swift` — All stubs

Needs ActivityKit implementation:
1. Define an `ActivityAttributes` struct for call state
2. Start activity when call begins (shows in Dynamic Island)
3. Update with call duration every second
4. End activity when call ends
5. Handle tap gesture to return to call screen

This is required for the "dismiss call screen but keep calling" behavior.

## Reference Patterns

### GetStream
- CallKit integration built into their `Call` object
- Audio session management through `AudioSessionManager`
- Automatic handling of interruptions and route changes

### 100ms
- Audio session auto-configured by default
- Can be disabled for manual CallKit control
- `toggleMic()` and `toggleCamera()` as simple state toggles

### LiveKit
- `AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false` for CallKit
- `AudioEngineObserver` chains for audio processing
- Separate audio session lifecycle from video

## Verification

1. Start call → appears in system call log (Recents tab in Phone app)
2. During call, open Control Center → mute button works → syncs with app UI
3. Real phone call comes in → call is interrupted → resumes after
4. Bluetooth headset connects during call → audio routes to headset
5. (After Live Activity) Background app → Dynamic Island shows call → tap returns
