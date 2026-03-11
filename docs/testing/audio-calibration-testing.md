# Audio Calibration Testing

## Context

Speakerphone calls suffer from self-interruption: the model's audio output leaks back through the mic, server-side VAD detects it as user speech, and the model interrupts itself mid-sentence. Fixing this without breaking barge-in (user intentionally interrupting the model) is a calibration problem.

Simulator tests can validate payload contracts and protocol conformance. Real audio behavior — AEC effectiveness, VAD sensitivity, barge-in responsiveness — is hardware truth and requires device testing.

## Current calibration (2026-03-11)

```swift
// GeminiService.swift — setup payload, audio mode
"realtimeInputConfig": [
    "automaticActivityDetection": [
        "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
        "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
        "prefixPaddingMs": 40,
        "silenceDurationMs": 500
    ]
]
// No proactiveAudio — suppresses valid barge-in when stacked with LOW start sensitivity
```

Plus explicit AEC preference (`setPrefersEchoCancelledInput(true)`, iOS 18.2+) and `v1alpha` endpoint.

### Parameter reference

| Parameter | Default | Current | Effect |
|---|---|---|---|
| `startOfSpeechSensitivity` | HIGH | LOW | How much audio evidence before VAD triggers. LOW = harder to trigger = rejects echo but makes barge-in slightly harder. |
| `endOfSpeechSensitivity` | HIGH | LOW | How quickly VAD decides speech ended. LOW = tolerant of brief silences, prevents echo decay from splitting into phantom speech events. |
| `prefixPaddingMs` | 20 | 40 | Audio included before detected speech onset. Gives AEC more time to cancel before VAD evaluates. |
| `silenceDurationMs` | 100 | 500 | Silence required before utterance is considered complete. Catches echo decay tails. Makes turn-taking ~400ms slower. |
| `proactiveAudio` | off | off | Model-level judgment about whether audio is directed speech. Smart but suppresses barge-in during model playback. |

### Tested combinations

| Config | Self-interruption | Barge-in | Notes |
|---|---|---|---|
| No VAD tuning (baseline) | Bad | Good | Original problem |
| LOW start + LOW end + proactiveAudio | Good | Broken | Over-filtered, double-gated |
| LOW end only | Bad | Good | Not enough echo rejection |
| **LOW start + LOW end** | **Good** | **Slightly harder** | Current — working |

### Untested combinations (TODO)

- `proactiveAudio` alone (no LOW start) — model intelligence without blunt threshold
- `proactiveAudio` + LOW end only — swap model intelligence for start sensitivity
- `silenceDurationMs` at 300 (instead of 500) — faster turn-taking, may be enough
- `prefixPaddingMs` at 30 — marginal, unlikely perceptible

## Manual device test protocol

### Equipment
- iPhone with speakerphone (no headphones)
- Quiet room, then noisy room if available

### Test cases

1. **Self-interruption (speakerphone)**
   - Start a voice call on speaker
   - Let the model speak a long response (ask it to explain something)
   - Pass: model completes its response without cutting itself off
   - Fail: model stops mid-sentence, restarts, or goes silent

2. **Barge-in (speakerphone)**
   - Start a voice call on speaker
   - While the model is speaking, interrupt with a clear sentence
   - Pass: model stops and responds to your interruption
   - Fail: model ignores you and keeps talking

3. **Barge-in (earpiece/headphones)**
   - Same as above but with earpiece or wired/bluetooth headphones
   - Pass: should be easier than speakerphone — no echo to filter
   - This is a regression check: VAD tuning should not hurt non-speaker modes

4. **Turn-taking latency**
   - Have a normal back-and-forth conversation
   - Note the pause between when you stop speaking and the model responds
   - Baseline expectation: ~500ms pause (from `silenceDurationMs`)
   - If noticeably sluggish, consider reducing to 300ms

5. **Background noise**
   - Play music or TV in the background during a call
   - Pass: model does not self-interrupt from ambient noise
   - This tests whether LOW sensitivity + AEC handles non-echo noise

## Future: automated audio fixture harness

### Goal
Replace subjective manual testing with repeatable, measurable device tests.

### Fixtures needed
- Clean speech at various volumes (whisper, normal, loud)
- Simulated speaker bleed (model output re-recorded through speaker+mic)
- Overlapping speech + playback (barge-in scenario)
- Background room noise (TV, kitchen, outdoor)

### Harness design
- Plays a fixture through the speaker output
- Records what the mic captures after AEC processing
- Sends captured audio to Gemini via the Live API
- Logs whether VAD triggered (server sent interruption event)
- Writes structured results (JSON) for comparison across calibration runs

### Metrics to track
- **Self-interruption rate**: play model output on speaker, count false VAD triggers
- **Barge-in latency**: time from speech onset to model interruption acknowledgment
- **Barge-in success rate**: percentage of intentional interruptions that register
- **Turn-taking latency**: time from user silence to model response onset

### Constraints
- Must run on physical device (simulator AEC is not representative)
- Results will vary by device model, case, room acoustics
- Useful for A/B comparison between configs, not absolute thresholds
