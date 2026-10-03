#!/usr/bin/env python3
"""One short, real call to each external API, to confirm the integrations work.

  OPENAI_API_KEY=... ANTHROPIC_API_KEY=... python3 scripts/smoke_api.py [--record]

Calls (each skipped if its key is unset):
  1. POST /v1/audio/transcriptions — gpt-4o-transcribe-diarize, diarized_json,
     chunking_strategy=auto, with the two reference clips, on Fixtures/sample-lesson.m4a
     (~1 minute of audio: well under one US cent).
  2. POST /v1/responses — a tiny strict-JSON-schema request.
  3. POST /v1/messages (Anthropic) — the same tiny request with output_config.format.

The requests mirror what the app builds in PassaggioCore (OpenAITranscriptionClient,
OpenAIProvider, AnthropicProvider). With --record, responses are written to
Packages/PassaggioCore/Tests/PassaggioCoreTests/Fixtures/live_*.json so the unit
tests can be pointed at real responses. Standard library only.
"""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "Fixtures"
TEST_FIXTURES = ROOT / "Packages/PassaggioCore/Tests/PassaggioCoreTests/Fixtures"
OPENAI_TEXT_MODEL = os.environ.get("OPENAI_MODEL", "gpt-6.1-sol")
ANTHROPIC_MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-opus-5")

SCHEMA = {
    "type": "object",
    "properties": {"points": {"type": "array", "items": {
        "type": "object",
        "properties": {"theme": {"type": "string", "enum": ["registration_mix", "tension_habits", "breath_support"]},
                       "summary": {"type": "string"}, "segment": {"type": "integer"}},
        "required": ["segment", "summary", "theme"], "additionalProperties": False}}},
    "required": ["points"], "additionalProperties": False,
}
PROMPT = ("Teacher's lines:\n[0] You're pushing chest voice too high around the C, let it tip into the mix earlier.\n"
          "[1] Keep your jaw loose, it clamps on the top note.\nExtract each piece of feedback.")
SYSTEM = "You organise a singing teacher's feedback. Never add advice the teacher did not give."


def post(url: str, headers: dict[str, str], body: bytes) -> tuple[int, dict]:
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b"{}")


def multipart(fields: list[tuple[str, str]], file_field: str, filename: str, data: bytes) -> tuple[bytes, str]:
    boundary = f"passaggio-{uuid.uuid4()}"
    out = bytearray()
    for name, value in fields:
        out += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{value}\r\n".encode()
    out += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{file_field}\"; filename=\"{filename}\"\r\n"
            f"Content-Type: audio/mp4\r\n\r\n").encode() + data + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={boundary}"


def data_url(path: Path) -> str:
    return "data:audio/wav;base64," + base64.b64encode(path.read_bytes()).decode()


def transcription(key: str) -> dict:
    fields = [("model", "gpt-4o-transcribe-diarize"), ("response_format", "diarized_json"), ("chunking_strategy", "auto"),
              ("known_speaker_names[]", "teacher"), ("known_speaker_references[]", data_url(FIXTURES / "teacher-reference.wav")),
              ("known_speaker_names[]", "me"), ("known_speaker_references[]", data_url(FIXTURES / "student-reference.wav"))]
    body, content_type = multipart(fields, "file", "sample-lesson.m4a", (FIXTURES / "sample-lesson.m4a").read_bytes())
    status, response = post("https://api.openai.com/v1/audio/transcriptions",
                            {"Authorization": f"Bearer {key}", "Content-Type": content_type}, body)
    check("transcription", status, response)
    for segment in response.get("segments", []):
        print(f"    {segment['start']:6.1f}–{segment['end']:6.1f}  {segment['speaker']:>8}: {segment['text']}")
    print(f"    usage: {response.get('usage')}")
    return response


def openai_text(key: str) -> dict:
    body = {"model": OPENAI_TEXT_MODEL, "instructions": SYSTEM, "input": PROMPT, "store": False,
            "text": {"format": {"type": "json_schema", "name": "lesson_key_points", "schema": SCHEMA, "strict": True}}}
    status, response = post("https://api.openai.com/v1/responses",
                            {"Authorization": f"Bearer {key}", "Content-Type": "application/json"}, json.dumps(body).encode())
    check(f"openai {OPENAI_TEXT_MODEL}", status, response)
    texts = [part["text"] for item in response.get("output", []) if item.get("type") == "message"
             for part in item.get("content", []) if part.get("type") == "output_text"]
    print("    " + json.dumps(json.loads(texts[0]))[:300])
    return response


def anthropic_text(key: str) -> dict:
    body = {"model": ANTHROPIC_MODEL, "max_tokens": 16000, "system": SYSTEM,
            "messages": [{"role": "user", "content": PROMPT}],
            "output_config": {"format": {"type": "json_schema", "schema": SCHEMA}}}
    headers = {"x-api-key": key, "anthropic-version": "2023-06-01", "Content-Type": "application/json"}
    if ANTHROPIC_MODEL.startswith(("claude-opus-5", "claude-fable", "claude-mythos")):
        body["fallbacks"] = "default"
        headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
    status, response = post("https://api.anthropic.com/v1/messages", headers, json.dumps(body).encode())
    check(f"anthropic {ANTHROPIC_MODEL}", status, response)
    text = "".join(block.get("text", "") for block in response.get("content", []) if block.get("type") == "text")
    print(f"    stop_reason={response.get('stop_reason')}  " + json.dumps(json.loads(text))[:300])
    return response


def check(name: str, status: int, response: dict) -> None:
    if status != 200:
        sys.exit(f"✗ {name}: HTTP {status}: {json.dumps(response)[:500]}")
    print(f"✓ {name}")


def main() -> None:
    record = "--record" in sys.argv
    ran = False
    if key := os.environ.get("OPENAI_API_KEY"):
        ran = True
        results = {"live_diarized_lesson": transcription(key), "live_openai_responses": openai_text(key)}
        if record:
            for name, data in results.items():
                (TEST_FIXTURES / f"{name}.json").write_text(json.dumps(data, indent=2))
    else:
        print("– OPENAI_API_KEY not set: skipping transcription and OpenAI text")
    if key := os.environ.get("ANTHROPIC_API_KEY"):
        ran = True
        response = anthropic_text(key)
        if record:
            (TEST_FIXTURES / "live_anthropic_messages.json").write_text(json.dumps(response, indent=2))
    else:
        print("– ANTHROPIC_API_KEY not set: skipping Anthropic")
    if not ran:
        sys.exit("No API keys set; nothing was called.")


if __name__ == "__main__":
    main()
