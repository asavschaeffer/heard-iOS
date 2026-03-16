"""Heard Chef — FastAPI backend with ADK agent and voice relay."""

import asyncio
import json
import logging
import os
import uuid

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from google.adk.runners import Runner
from google.adk.sessions import InMemorySessionService
from google.genai import types

from cooking_agent.agent import cooking_agent, SYSTEM_PROMPT, LIVE_AUDIO_ADDENDUM
from cooking_agent.tools import set_user_id, TOOL_DECLARATIONS_JSON

logger = logging.getLogger("heard-backend")
logging.basicConfig(level=logging.INFO)

app = FastAPI(title="Heard Chef Backend")
session_service = InMemorySessionService()
runner = Runner(agent=cooking_agent, app_name="heard_chef", session_service=session_service)

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {"status": "ok", "service": "heard-backend"}


# ---------------------------------------------------------------------------
# Text Chat — POST /chat
# ---------------------------------------------------------------------------

@app.post("/chat")
async def chat(body: dict):
    message = body.get("message", "")
    session_id = body.get("session_id") or str(uuid.uuid4())
    user_id = body.get("user_id", "default")

    # Set the active user for Firestore tool calls
    set_user_id(user_id)

    # Get or create session
    session = await session_service.get_session(
        app_name="heard_chef", user_id=user_id, session_id=session_id
    )
    if session is None:
        session = await session_service.create_session(
            app_name="heard_chef", user_id=user_id, session_id=session_id
        )

    # Run the agent
    user_content = types.Content(
        role="user", parts=[types.Part.from_text(text=message)]
    )

    final_text = ""
    try:
        async for event in runner.run_async(
            user_id=user_id, session_id=session_id, new_message=user_content
        ):
            if event.is_final_response():
                for part in event.content.parts:
                    if part.text:
                        final_text += part.text
    except Exception as exc:
        logger.exception("[chat] Agent run failed")
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    return {"reply": final_text, "session_id": session_id}


# ---------------------------------------------------------------------------
# Photo Chat — POST /chat-with-photo
# ---------------------------------------------------------------------------

@app.post("/chat-with-photo")
async def chat_with_photo(body: dict):
    """Text + optional image chat. Image is base64 JPEG in the 'image' field."""
    message = body.get("message", "")
    image_b64 = body.get("image")  # base64-encoded JPEG
    session_id = body.get("session_id") or str(uuid.uuid4())
    user_id = body.get("user_id", "default")

    set_user_id(user_id)

    session = await session_service.get_session(
        app_name="heard_chef", user_id=user_id, session_id=session_id
    )
    if session is None:
        session = await session_service.create_session(
            app_name="heard_chef", user_id=user_id, session_id=session_id
        )

    # Build multimodal parts
    parts = []
    if message:
        parts.append(types.Part.from_text(text=message))
    if image_b64:
        import base64

        image_bytes = base64.b64decode(image_b64)
        parts.append(
            types.Part.from_bytes(data=image_bytes, mime_type="image/jpeg")
        )

    if not parts:
        raise HTTPException(status_code=400, detail="No message or image provided")

    user_content = types.Content(role="user", parts=parts)

    final_text = ""
    try:
        async for event in runner.run_async(
            user_id=user_id, session_id=session_id, new_message=user_content
        ):
            if event.is_final_response():
                for part in event.content.parts:
                    if part.text:
                        final_text += part.text
    except Exception as exc:
        logger.exception("[chat-with-photo] Agent run failed")
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    return {"reply": final_text, "session_id": session_id}


# ---------------------------------------------------------------------------
# Voice Relay — WS /voice
# ---------------------------------------------------------------------------

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_WS_URL = (
    "wss://generativelanguage.googleapis.com/ws/"
    "google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent"
)


def _build_voice_setup(user_id: str = "default") -> dict:
    """Build the Gemini Live API setup message with system prompt, tools, and voice config."""
    return {
        "setup": {
            "model": "models/gemini-2.5-flash-native-audio-preview-12-2025",
            "systemInstruction": {
                "parts": [{"text": SYSTEM_PROMPT + "\n\n" + LIVE_AUDIO_ADDENDUM}]
            },
            "tools": [{"functionDeclarations": TOOL_DECLARATIONS_JSON}],
            "generationConfig": {
                "responseModalities": ["AUDIO"],
                "speechConfig": {
                    "voiceConfig": {
                        "prebuiltVoiceConfig": {
                            "voiceName": "Aoede"
                        }
                    }
                },
            },
            "realtimeInputConfig": {
                "automaticActivityDetection": {
                    "startOfSpeechSensitivity": "START_SENSITIVITY_LOW",
                    "endOfSpeechSensitivity": "END_SENSITIVITY_LOW",
                    "prefixPaddingMs": 40,
                    "silenceDurationMs": 500,
                }
            },
            "outputAudioTranscription": {},
            "inputAudioTranscription": {},
        }
    }


async def _handle_gemini_function_calls(
    gemini_ws, parts: list, user_id: str
) -> None:
    """Execute function calls from Gemini against Firestore, send results back."""
    from cooking_agent.tools import execute_tool

    set_user_id(user_id)

    tool_responses = []
    for part in parts:
        fc = part.get("functionCall")
        if not fc:
            continue
        name = fc.get("name", "")
        args = fc.get("args", {})
        logger.info(f"[voice] Function call: {name}({args})")
        result = await execute_tool(name, args)
        tool_responses.append({
            "functionResponse": {
                "name": name,
                "response": result,
            }
        })

    if tool_responses:
        msg = {"toolResponse": {"functionResponses": tool_responses}}
        await gemini_ws.send(json.dumps(msg))


@app.websocket("/voice")
async def voice_relay(ws: WebSocket):
    """Relay audio frames between iOS client and Gemini Live API."""
    await ws.accept()

    # Read optional query params
    user_id = ws.query_params.get("user_id", "default")
    voice_name = ws.query_params.get("voice", "Aoede")

    logger.info(f"[voice] Client connected user={user_id} voice={voice_name}")

    import websockets

    gemini_url = f"{GEMINI_WS_URL}?key={GEMINI_API_KEY}"

    try:
        async with websockets.connect(
            gemini_url,
            additional_headers={"Content-Type": "application/json"},
            max_size=None,
            ping_interval=30,
            ping_timeout=10,
        ) as gemini_ws:
            # Send setup message
            setup = _build_voice_setup(user_id)
            setup["setup"]["generationConfig"]["speechConfig"]["voiceConfig"][
                "prebuiltVoiceConfig"
            ]["voiceName"] = voice_name
            await gemini_ws.send(json.dumps(setup))

            # Wait for setup complete from Gemini
            setup_response = await gemini_ws.recv()
            setup_data = json.loads(setup_response)
            logger.info(f"[voice] Gemini setup response: {list(setup_data.keys())}")

            # Forward setup complete to client
            await ws.send_text(setup_response)

            # Bidirectional relay
            async def client_to_gemini():
                """Forward client frames to Gemini."""
                try:
                    while True:
                        data = await ws.receive()
                        if data.get("text"):
                            await gemini_ws.send(data["text"])
                        elif data.get("bytes"):
                            await gemini_ws.send(data["bytes"])
                except WebSocketDisconnect:
                    logger.info("[voice] Client disconnected")
                except Exception as e:
                    logger.error(f"[voice] Client→Gemini error: {e}")

            async def gemini_to_client():
                """Forward Gemini frames to client, intercepting function calls."""
                try:
                    async for message in gemini_ws:
                        if isinstance(message, str):
                            msg_data = json.loads(message)

                            # Check for function calls — handle server-side
                            server_content = msg_data.get("serverContent") or {}
                            parts = []
                            if "modelTurn" in server_content:
                                parts = server_content["modelTurn"].get("parts", [])

                            has_function_calls = any(
                                "functionCall" in p for p in parts
                            )

                            if has_function_calls:
                                # Execute tools server-side, don't forward to client
                                await _handle_gemini_function_calls(
                                    gemini_ws, parts, user_id
                                )
                            else:
                                # Forward everything else to client
                                await ws.send_text(message)
                        else:
                            # Binary frames (audio) — pass through
                            await ws.send_bytes(message)
                except websockets.exceptions.ConnectionClosed:
                    logger.info("[voice] Gemini connection closed")
                except Exception as e:
                    logger.error(f"[voice] Gemini→Client error: {e}")

            # Run both directions concurrently
            done, pending = await asyncio.wait(
                [
                    asyncio.create_task(client_to_gemini()),
                    asyncio.create_task(gemini_to_client()),
                ],
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()

    except Exception as e:
        logger.error(f"[voice] Connection error: {e}")
    finally:
        logger.info("[voice] Session ended")
