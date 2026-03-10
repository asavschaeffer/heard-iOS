# Findings

## Official Documentation

Google's cookbook examples (`Get_started_LiveAPI.py`, `Get_started_LiveAPI_NativeAudio.py`) explicitly state:

> **Important:** Use headphones. This script uses the system default audio input and output, which often won't include echo cancellation. So to prevent the model from interrupting itself it is important that you use headphones.

The root cause: VAD (Voice Activity Detection) on the server can't distinguish between the user speaking and the model's own audio leaking back through the mic. It treats echo as a user interruption and cancels the ongoing generation.

## Solutions (ranked by practicality for our iOS app)

1. **iOS AEC via `.voiceChat` mode** — Use `AVAudioSession` with `.voiceChat` mode + `.defaultToSpeaker`. Check `isEchoCancelledInputAvailable` at runtime. This is the native platform solution.
2. **Client-side mic suppression** — Stop sending audio frames to the WebSocket while playback is active. Resume ~200-500ms after playback stops. Simple half-duplex approach, but prevents user barge-in.
3. **`NO_INTERRUPTION` activity handling** — Set `activityHandling: NO_INTERRUPTION` in the setup config. Model continues speaking even if VAD fires. Downside: user can't interrupt at all.
4. **Disable auto-VAD + manual control** — Set `automaticActivityDetection.disabled: true`, then send `ActivityStart`/`ActivityEnd` manually. Since we know when playback is happening, we can suppress activity signals during echo.
5. **Tune VAD sensitivity** — Set `startOfSpeechSensitivity: LOW` to raise the trigger threshold. Reduces false positives but community reports this alone is insufficient for speakerphone.
6. **Proactive Audio (preview)** — New feature where the model distinguishes speech directed at the device vs background audio. Could help ignore echo, but unconfirmed and in preview.

## Key Community Links

- https://github.com/google-gemini/live-api-web-console/issues/117 — model stopping mid-sentence
- https://discuss.ai.google.dev/t/disable-interruptions-for-audio-streaming-for-multimodal-live-api/61689
- https://discuss.ai.google.dev/t/how-do-i-prevent-the-live-api-from-discarding-audio-when-its-given-audio-while-it-speaks/73795
- https://community.openai.com/t/realtime-api-starts-to-answer-itself-with-mic-speaker-setup/977801

## Recommended Layered Strategy for Heard

1. Ensure we're using `.voiceChat` audio session mode (enables hardware AEC)
2. Tune VAD sensitivity to `LOW` as a baseline
3. Consider disabling auto-VAD and implementing echo-aware manual turn detection — we already know when playback is active
4. Fall back to mic suppression during playback if AEC proves insufficient on speakerphone
