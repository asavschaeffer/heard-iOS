# CallKit + AVAudioSession: Deep Dive

## Overview

For a native "phone call" experience, three Apple frameworks work together:
- **AVAudioSession**: Configures the audio hardware (mic input, speaker output, routing)
- **CallKit**: Integrates with the iOS system call UI (shows call in recents, interruption handling, mute from Control Center)
- **ActivityKit (Live Activity)**: Shows call status in Dynamic Island when the app is backgrounded

## Current Implementation

### AVAudioSession Setup

**File**: `ChatViewModel.swift` lines 149-157, 182-190

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

**File**: `ChatViewModel.swift` lines 192-199

```swift
private func preferSpeaker() {
    try session.overrideOutputAudioPort(.speaker)
}
```

To toggle back to earpiece:
```swift
try session.overrideOutputAudioPort(.none)  // Routes to earpiece
```

Currently `preferSpeaker()` is called once at connection time but there's no toggle exposed to the UI. The `AudioRoutePickerView` wraps `AVRoutePickerView` which shows the system audio route picker — this handles speaker/Bluetooth/earpiece selection natively.

### CallKit Integration

**File**: `app/Services/CallKitManager.swift`

The implementation is minimal but correct:

```
startCall() → CXStartCallAction → system registers call
                                 → didActivate(audioSession:) callback
                                     → onStartAudio closure fires
                                         → configureAudioSessionForCall()
                                         → startAudioCapture()

endCall() → CXEndCallAction → system deregisters call
                             → didDeactivate(audioSession:) callback
                                 → onStopAudio closure fires
                                     → stopAudioCapture()

Mute from Control Center → CXSetMutedCallAction
                          → onMuteChanged(isMuted) callback
```

### What's Missing

1. **`reportConnected()` timing**: Currently called in `geminiServiceDidConnect()`. This is correct — it tells iOS the outgoing call was answered, which updates the system UI from "Calling..." to the connected state.

2. **Incoming call support**: Not applicable (AI doesn't initiate calls), but `CXProviderConfiguration.supportsVideo = false` is set.

3. **Call interruption**: The `handleInterruption()` method handles system interruptions (e.g., real phone call comes in). When `.began`, it stops audio capture. When `.ended` with `.shouldResume`, it restarts. This is correct.

4. **Live Activity**: `LiveActivityManager` is all stubs. Without this, there's no Dynamic Island presence when the user backgrounds the app during a call.

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
