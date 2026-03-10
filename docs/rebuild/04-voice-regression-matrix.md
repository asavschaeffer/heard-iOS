# Voice Regression Matrix

Use this checklist before merging voice-stack changes.

## Receiver and Speaker

- Start a call on receiver, speak, wait for a response, switch to speaker, speak again, and confirm Gemini audio plays on speaker.
- Start a call on speaker, speak, wait for a response, switch to receiver, speak again, and confirm Gemini audio plays on receiver.
- Repeat receiver/speaker toggles while Gemini is actively speaking.
- Repeat receiver/speaker toggles while the user is actively speaking.
- Toggle mute on and off during both receiver and speaker playback.

## Route Changes

- Connect a Bluetooth headset during a call and confirm capture and playback move to the headset.
- Disconnect Bluetooth during a call and confirm capture and playback recover on the built-in route.
- Plug in and unplug a wired headset during a call if hardware is available.
- Open the system route picker and switch away from and back to the built-in route.

## Call Lifecycle

- Start a call, background the app, return to the app, and confirm the call still captures and plays audio.
- Trigger a real interruption if possible and confirm the call resumes capture/playback afterward.
- Use Control Center or the system call UI to mute and unmute, and confirm the in-app state stays in sync.
- End a call while Gemini is speaking and confirm local playback is torn down cleanly.

## Logs

- In debug builds, confirm `VoiceDiagnostics` still logs route changes, CallKit activation/deactivation, capture starts/stops, playback starts/stops, and Gemini websocket lifecycle.
- In release builds, confirm verbose voice logs are absent and only faults/errors remain.
