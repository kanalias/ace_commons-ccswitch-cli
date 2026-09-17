#!/usr/bin/env python3
"""Small Anthropic Messages -> Kimi OpenAI-compatible local adapter."""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


KIMI_KEY = os.environ.get("KIMI_API_KEY") or os.environ.get("MOONSHOT_API_KEY") or os.environ.get("ANTHROPIC_AUTH_TOKEN", "")
KIMI_BASE = (os.environ.get("KIMI_BASE_URL") or os.environ.get("MOONSHOT_BASE_URL") or "https://api.moonshot.ai/v1").rstrip("/")
KIMI_MODEL = os.environ.get("KIMI_MODEL") or os.environ.get("MOONSHOT_MODEL") or "kimi-k3"


class Handler(BaseHTTPRequestHandler):
    server_version = "ccswitch-kimi-adapter/1"

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def send_json(self, code: int, body: dict) -> None:
        raw = json.dumps(body, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def send_sse(self, body: dict) -> None:
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("cache-control", "no-cache")
        self.end_headers()

        msg = {
            "id": body["id"], "type": "message", "role": "assistant", "model": body["model"],
            "content": [], "stop_reason": None, "stop_sequence": None,
            "usage": {"input_tokens": body["usage"]["input_tokens"], "output_tokens": 0},
        }
        self.event("message_start", {"type": "message_start", "message": msg})
        for i, block in enumerate(body["content"]):
            if block["type"] == "text":
                self.event("content_block_start", {"type": "content_block_start", "index": i, "content_block": {"type": "text", "text": ""}})
                if block.get("text"):
                    self.event("content_block_delta", {"type": "content_block_delta", "index": i, "delta": {"type": "text_delta", "text": block["text"]}})
            else:
                self.event("content_block_start", {"type": "content_block_start", "index": i, "content_block": {"type": "tool_use", "id": block["id"], "name": block["name"], "input": {}}})
                self.event("content_block_delta", {"type": "content_block_delta", "index": i, "delta": {"type": "input_json_delta", "partial_json": json.dumps(block.get("input", {}))}})
            self.event("content_block_stop", {"type": "content_block_stop", "index": i})
        self.event("message_delta", {"type": "message_delta", "delta": {"stop_reason": body["stop_reason"], "stop_sequence": None}, "usage": {"output_tokens": body["usage"]["output_tokens"]}})
        self.event("message_stop", {"type": "message_stop"})

    def event(self, name: str, data: dict) -> None:
        self.wfile.write(f"event: {name}\ndata: {json.dumps(data, separators=(',', ':'))}\n\n".encode())
        self.wfile.flush()

    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/v1/models":
            self.send_json(200, {"data": [{"id": KIMI_MODEL, "type": "model"}]})
            return
        self.send_json(404, {"error": {"message": "not found"}})

    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/v1/messages":
            self.send_json(404, {"error": {"message": "not found"}})
            return
        if not KIMI_KEY or "<your-kimi-key>" in KIMI_KEY:
            self.send_json(401, {"error": {"message": "KIMI_API_KEY missing"}})
            return
        try:
            size = int(self.headers.get("content-length", "0"))
            req = json.loads(self.rfile.read(size).decode())
            body = self.call_kimi(self.to_openai(req))
            self.send_sse(body) if req.get("stream") else self.send_json(200, body)
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="ignore")[:1000]
            self.send_json(e.code, {"error": {"message": msg}})
        except Exception as e:
            self.send_json(500, {"error": {"message": f"{type(e).__name__}: {e}"}})

    def call_kimi(self, payload: dict) -> dict:
        data = json.dumps(payload).encode()
        req = urllib.request.Request(
            f"{KIMI_BASE}/chat/completions",
            data=data,
            headers={"Authorization": f"Bearer {KIMI_KEY}", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=120) as resp:
            out = json.loads(resp.read().decode())
        msg = out.get("choices", [{}])[0].get("message", {})
        content = []
        if msg.get("content"):
            content.append({"type": "text", "text": msg["content"]})
        for tc in msg.get("tool_calls") or []:
            fn = tc.get("function", {})
            try:
                args = json.loads(fn.get("arguments") or "{}")
            except json.JSONDecodeError:
                args = {}
            content.append({"type": "tool_use", "id": tc.get("id", "toolu_kimi"), "name": fn.get("name", ""), "input": args})
        usage = out.get("usage", {})
        return {
            "id": out.get("id", "kimi-adapter"), "type": "message", "role": "assistant", "model": payload["model"],
            "content": content or [{"type": "text", "text": ""}],
            "stop_reason": "tool_use" if any(c["type"] == "tool_use" for c in content) else "end_turn",
            "stop_sequence": None,
            "usage": {"input_tokens": usage.get("prompt_tokens", 0), "output_tokens": usage.get("completion_tokens", 0)},
        }

    def to_openai(self, req: dict) -> dict:
        out = {
            "model": req.get("model") or KIMI_MODEL,
            "messages": [],
            "temperature": req.get("temperature", 0),
            "max_tokens": req.get("max_tokens", 1024),
            "stream": False,
        }
        system = self.text(req.get("system"))
        if system:
            out["messages"].append({"role": "system", "content": system})
        for m in req.get("messages", []):
            out["messages"].extend(self.convert_message(m))
        tools = req.get("tools") or []
        if tools:
            out["tools"] = [{"type": "function", "function": {"name": t["name"], "description": t.get("description", ""), "parameters": t.get("input_schema", {"type": "object"})}} for t in tools]
            out["tool_choice"] = "auto"
        return out

    def convert_message(self, m: dict) -> list[dict]:
        role, content = m.get("role", "user"), m.get("content", "")
        if isinstance(content, str):
            return [{"role": role, "content": content}]
        if role == "assistant":
            text = self.text(content)
            tool_calls = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "tool_use":
                    tool_calls.append({"id": item.get("id"), "type": "function", "function": {"name": item.get("name", ""), "arguments": json.dumps(item.get("input", {}))}})
            msg = {"role": "assistant", "content": text or None}
            if tool_calls:
                msg["tool_calls"] = tool_calls
            return [msg]
        result, text = [], self.text([i for i in content if not (isinstance(i, dict) and i.get("type") == "tool_result")])
        if text:
            result.append({"role": role, "content": text})
        for item in content:
            if isinstance(item, dict) and item.get("type") == "tool_result":
                result.append({"role": "tool", "tool_call_id": item.get("tool_use_id", ""), "content": self.text(item.get("content", ""))})
        return result or [{"role": role, "content": ""}]

    def text(self, value) -> str:
        if isinstance(value, str):
            return value
        if isinstance(value, list):
            parts = []
            for item in value:
                if isinstance(item, dict):
                    if item.get("type") == "text":
                        parts.append(str(item.get("text", "")))
                    elif isinstance(item.get("content"), str):
                        parts.append(item["content"])
                    elif isinstance(item.get("content"), list):
                        parts.append(self.text(item["content"]))
            return "\n".join(p for p in parts if p)
        return ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=20129)
    args = ap.parse_args()
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
