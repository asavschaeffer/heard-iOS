# WebSocket Protocol: Gemini Live API Deep Dive

## Overview

The Gemini Live API uses a bidirectional WebSocket for real-time audio streaming. The protocol has distinct phases: setup, streaming, and tool calling.

## Connection URL

```
wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=API_KEY
```

## Protocol Flow

### Phase 1: Setup Handshake

```
Client → Server:
{
  "setup": {
    "model": "models/gemini-2.5-flash-native-audio-preview-12-2025",
    "generation_config": {
      "response_modalities": ["AUDIO"],
      "speech_config": {
        "voice_config": {
          "prebuilt_voice_config": {
            "voice_name": "Aoede"
          }
        }
      }
    },
    "system_instruction": {
      "parts": [{"text": "system prompt here"}]
    },
    "tools": [
      {"function_declarations": [...]}
    ],
    "output_audio_transcription": {}
  }
}

Server → Client:
{"setupComplete": {}}
```

**Available voices**: Aoede, Charon, Fenrir, Kore, Puck

**Current code** (GeminiService.swift:186-216): Structure is correct. The `output_audio_transcription: {}` key enables text transcription of AI audio output.

### Phase 2: Audio Streaming

**Sending audio** (continuous, during call):
```json
{
  "realtime_input": {
    "media_chunks": [
      {
        "mime_type": "audio/pcm;rate=16000",
        "data": "base64-encoded-PCM16-mono"
      }
    ]
  }
}
```

**Sending text** (during call):
```json
{
  "client_content": {
    "turns": [
      {
        "role": "user",
        "parts": [{"text": "message text"}]
      }
    ],
    "turn_complete": true
  }
}
```

**Sending images** (during call):
```json
{
  "client_content": {
    "turns": [
      {
        "role": "user",
        "parts": [
          {"text": "what's this?"},
          {"inline_data": {"mime_type": "image/jpeg", "data": "base64..."}}
        ]
      }
    ],
    "turn_complete": true
  }
}
```

**Sending video frames** (live camera feed):
```json
{
  "realtime_input": {
    "media_chunks": [
      {
        "mime_type": "image/jpeg",
        "data": "base64-jpeg-frame"
      }
    ]
  }
}
```

### Phase 3: Server Responses

**Input transcript** (what the user said — server-side STT):
```json
{
  "serverContent": {
    "inputTranscript": "do I have any eggs left?"
  }
}
```

**Model turn** (AI response — may contain audio, text, and transcript):
```json
{
  "serverContent": {
    "modelTurn": {
      "parts": [
        {
          "inlineData": {
            "mime_type": "audio/pcm;rate=24000",
            "data": "base64-audio-chunk"
          }
        },
        {
          "transcript": "Just two left in the fridge, chef."
        }
      ]
    }
  }
}
```

**Turn complete** (AI finished responding):
```json
{
  "serverContent": {
    "turnComplete": true
  }
}
```

### Phase 4: Tool Calls

**Server requests a tool call**:
```json
{
  "toolCall": {
    "functionCalls": [
      {
        "id": "call-id-123",
        "name": "add_ingredient",
        "args": {
          "name": "eggs",
          "quantity": 12,
          "unit": "count",
          "location": "fridge"
        }
      }
    ]
  }
}
```

**Client sends tool result**:
```json
{
  "toolResponse": {
    "functionResponses": [
      {
        "id": "call-id-123",
        "name": "add_ingredient",
        "response": {
          "success": true,
          "message": "Added 12 count of eggs to the fridge",
          "ingredient": {"name": "eggs", "quantity": 12, "unit": "count"}
        }
      }
    ]
  }
}
```

## Current Implementation Analysis

### What's correct:
- Setup message structure (GeminiService.swift:186-216) ✓
- Audio send format (GeminiService.swift:283-300) ✓
- Server content parsing (GeminiService.swift:691-771) ✓
- Tool call handling (GeminiService.swift:775-810) ✓
- Text/image send via WebSocket (GeminiService.swift:305-401) ✓

### Potential issues:

1. **Model name**: `gemini-2.5-flash-native-audio-preview-12-2025` — Google rotates preview model names frequently. If setup never completes, this is the first thing to check.

2. **No reconnection backoff**: In `geminiServiceDidDisconnect`, the ViewModel immediately calls `connect()` again. Should use exponential backoff (1s, 2s, 4s, 8s, max 30s).

3. **Acceptance timeout at 6s**: May be too short for cold starts. Consider 10s.

4. **No ping/pong**: The WebSocket has no keep-alive mechanism. Apple's `URLSessionWebSocketTask` handles TCP-level pings automatically, but application-level heartbeats aren't sent.

### VAD (Voice Activity Detection)

The current implementation relies entirely on **server-side VAD** — Gemini decides when the user has stopped speaking. This works but can feel laggy.

**What swift-gemini-api adds**: Client-side VAD that detects silence and can pre-emptively signal turn completion. This makes conversations feel more responsive.

For now, server-side VAD is acceptable. Client-side VAD is an optimization for later.

## Reference Patterns

### swift-gemini-api
- `GeminiLiveClient` wraps the WebSocket lifecycle
- Handles setup/setupComplete handshake
- Provides callbacks: `onAudioReceived`, `onTextReceived`, `onToolCall`
- Manages VAD state
- Auto-reconnection with backoff

### pipecat-client-ios-gemini-live-websocket
- Transport layer abstraction over the WebSocket
- Can pipe audio through other services before hitting Gemini
- More complex agentic workflow support
- Not needed for direct Gemini communication

## Recommended Improvements

1. **Exponential backoff for reconnection**:
```swift
private var reconnectDelay: TimeInterval = 1.0
private let maxReconnectDelay: TimeInterval = 30.0

func handleDisconnect() {
    if callState.isPresented {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
            connect(mode: .audio)
            reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
        }
    }
}

// Reset on successful connection:
func handleConnect() {
    reconnectDelay = 1.0
}
```

2. **Verify model name on each release** — add a config constant that's easy to update.

3. **Consider increasing acceptance timeout** to 10s for reliability.

## Verification

1. Start voice call → WebSocket connects → `setupComplete` received within 6-10s
2. Speak → `inputTranscript` events appear (user's words)
3. AI responds → `modelTurn` with `inlineData` (audio) and `transcript`
4. `turnComplete` fires after AI finishes speaking
5. Tool calls work: say "add eggs to my pantry" → tool call chip appears → result sent back → AI acknowledges
6. Disconnect WiFi → reconnection attempts with backoff → reconnects when network returns
