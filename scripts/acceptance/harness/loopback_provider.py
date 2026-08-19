"""Test-only loopback provider for Slice 4B.5.

Binds 127.0.0.1 only. Never talks to OpenRouter, xAI, or OpenAI. Fake prices
are labeled simulated. A companion redirect-target and retry listener must stay
at zero connections when the staged pager honors one-attempt / no-redirect.
"""

from __future__ import annotations

import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

SIMULATED_USAGE = {
    "prompt_tokens": 40,
    "completion_tokens": 10,
    "total_tokens": 50,
    "simulated": True,
}

CHAT_OK = {
    "id": "s4b5-chat",
    "object": "chat.completion",
    "created": 0,
    "model": "loopback-model",
    "choices": [
        {
            "index": 0,
            "message": {"role": "assistant", "content": "pong"},
            "finish_reason": "stop",
        }
    ],
    "usage": SIMULATED_USAGE,
}

MODELS_OK = {
    "object": "list",
    "data": [{"id": "loopback-model", "object": "model"}],
}


class LoopbackCounters:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.connections = 0
        self.authorization: list[str] = []
        self.paths: list[str] = []
        self.hosts: list[str] = []
        self.methods: list[str] = []

    def record(self, handler: BaseHTTPRequestHandler) -> None:
        host = handler.headers.get("Host", "")
        auth = handler.headers.get("Authorization", "")
        with self.lock:
            self.connections += 1
            self.paths.append(handler.path)
            self.hosts.append(host)
            self.methods.append(handler.command)
            if auth:
                self.authorization.append(auth)
        cluster = getattr(handler.server, "cluster", None)
        if cluster is not None:
            cluster.write_status()

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            return {
                "connections": self.connections,
                "authorization": list(self.authorization),
                "paths": list(self.paths),
                "hosts": list(self.hosts),
                "methods": list(self.methods),
            }


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        return

    def do_GET(self) -> None:  # noqa: N802
        self.server.counters.record(self)  # type: ignore[attr-defined]
        if self.path.rstrip("/") in {"/v1/models", "/models"}:
            self._json(200, MODELS_OK)
            return
        self._json(404, {"error": {"message": "not found", "simulated": True}})

    def do_POST(self) -> None:  # noqa: N802
        self.server.counters.record(self)  # type: ignore[attr-defined]
        length = int(self.headers.get("Content-Length") or "0")
        if length > 1_048_576:
            self._json(413, {"error": {"message": "too large", "simulated": True}})
            return
        _ = self.rfile.read(length) if length else b""
        mode = getattr(self.server, "mode", "normal")
        if mode == "hold":
            getattr(self.server, "held", threading.Event()).wait(timeout=30)
            if getattr(self.server, "closed", False):
                return
        if mode == "redirect":
            location = getattr(self.server, "redirect_location", "")
            self.send_response(307)
            self.send_header("Location", location)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if self.path.rstrip("/").endswith("/chat/completions"):
            body = getattr(self.server, "chat_body", CHAT_OK)
            if callable(body):
                body = body()
            self._sse(completion_to_sse(body))
            return
        self._json(404, {"error": {"message": "not found", "simulated": True}})

    def _json(self, status: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _sse(self, payload: bytes) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        self.wfile.flush()


class LoopbackCluster:
    """Primary loopback plus redirect-target and retry listeners."""

    def __init__(
        self,
        mode: str = "normal",
        chat_body: dict[str, Any] | None = None,
        status_path: Path | None = None,
    ) -> None:
        if mode not in {"normal", "redirect", "hold", "ordered_reads", "worker", "recovery"}:
            raise ValueError("unsupported loopback mode")
        self.mode = mode
        self.status_path = status_path
        self.primary = self._server("primary", mode)
        self.redirect = self._server("redirect", "normal")
        self.retry = self._server("retry", "normal")
        self.primary.redirect_location = (  # type: ignore[attr-defined]
            f"http://127.0.0.1:{self.redirect.server_port}/v1/chat/completions"
        )
        if chat_body is not None:
            self.primary.chat_body = chat_body  # type: ignore[attr-defined]
        elif mode == "ordered_reads":
            self.primary.chat_body = self._ordered_read_script()  # type: ignore[attr-defined]
        elif mode == "worker":
            self.primary.chat_body = self._worker_script()  # type: ignore[attr-defined]
        elif mode == "recovery":
            self.primary.chat_body = self._recovery_script()  # type: ignore[attr-defined]
        self._threads: list[threading.Thread] = []

    def _server(self, name: str, mode: str) -> ThreadingHTTPServer:
        server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        server.counters = LoopbackCounters()  # type: ignore[attr-defined]
        server.mode = mode  # type: ignore[attr-defined]
        server.held = threading.Event()  # type: ignore[attr-defined]
        server.closed = False  # type: ignore[attr-defined]
        server.role = name  # type: ignore[attr-defined]
        server.chat_body = CHAT_OK  # type: ignore[attr-defined]
        server.cluster = self  # type: ignore[attr-defined]
        return server

    def write_status(self) -> None:
        if self.status_path is None:
            return
        self.status_path.write_text(json.dumps(self.snapshot(), separators=(",", ":")))

    def start(self) -> dict[str, Any]:
        for server in (self.primary, self.redirect, self.retry):
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            self._threads.append(thread)
        return self.identity()

    def close(self) -> None:
        for server in (self.primary, self.redirect, self.retry):
            server.closed = True  # type: ignore[attr-defined]
            server.held.set()  # type: ignore[attr-defined]
            server.shutdown()
            server.server_close()

    def identity(self) -> dict[str, Any]:
        return {
            "baseUrl": f"http://127.0.0.1:{self.primary.server_port}/v1",
            "redirectUrl": f"http://127.0.0.1:{self.redirect.server_port}/v1",
            "retryUrl": f"http://127.0.0.1:{self.retry.server_port}/v1",
            "mode": self.mode,
            "simulated": True,
        }

    def snapshot(self) -> dict[str, Any]:
        return {
            "primary": self.primary.counters.snapshot(),  # type: ignore[attr-defined]
            "redirect": self.redirect.counters.snapshot(),  # type: ignore[attr-defined]
            "retry": self.retry.counters.snapshot(),  # type: ignore[attr-defined]
            "identity": self.identity(),
        }

    def _ordered_read_script(self):
        calls = {"n": 0}
        files = [
            "scripts/acceptance/fixtures/.slice4-native-tools/ONE.txt",
            "scripts/acceptance/fixtures/.slice4-native-tools/TWO.txt",
            "scripts/acceptance/fixtures/.slice4-native-tools/THREE.txt",
        ]

        def next_body() -> dict[str, Any]:
            calls["n"] += 1
            index = calls["n"] - 1
            if index < len(files):
                return {
                    "id": f"s4b5-read-{calls['n']}",
                    "object": "chat.completion",
                    "created": 0,
                    "model": "loopback-model",
                    "choices": [
                        {
                            "index": 0,
                            "message": {
                                "role": "assistant",
                                "content": None,
                                "tool_calls": [
                                    {
                                        "id": f"call_read_{calls['n']}",
                                        "type": "function",
                                        "function": {
                                            "name": "GrokBuild:read_file",
                                            "arguments": json.dumps(
                                                {"path": files[index]},
                                                separators=(",", ":"),
                                            ),
                                        },
                                    }
                                ],
                            },
                            "finish_reason": "tool_calls",
                        }
                    ],
                    "usage": SIMULATED_USAGE,
                }
            return CHAT_OK

        return next_body

    def _worker_script(self):
        calls = {"n": 0}

        def next_body() -> dict[str, Any]:
            calls["n"] += 1
            if calls["n"] <= 2:
                name = "LEFT" if calls["n"] == 1 else "RIGHT"
                return _tool_call(
                    f"s4b5-task-{calls['n']}",
                    f"call_task_{calls['n']}",
                    "GrokBuild:task",
                    {"description": name, "prompt": "reply pong"},
                )
            if calls["n"] == 3:
                return _tool_call(
                    "s4b5-wait-1",
                    "call_wait_1",
                    "GrokBuild:wait_tasks",
                    {},
                )
            return CHAT_OK

        return next_body

    def _recovery_script(self):
        calls = {"n": 0}
        files = [
            "scripts/acceptance/fixtures/.slice4-native-tools/MISSING.txt",
            "scripts/acceptance/fixtures/.slice4-native-tools/RECOVERED.txt",
        ]

        def next_body() -> dict[str, Any]:
            calls["n"] += 1
            index = calls["n"] - 1
            if index < len(files):
                return _tool_call(
                    f"s4b5-recovery-{calls['n']}",
                    f"call_recovery_{calls['n']}",
                    "GrokBuild:read_file",
                    {"path": files[index]},
                )
            return CHAT_OK

        return next_body


def completion_to_sse(payload: dict[str, Any]) -> bytes:
    """Render a non-streaming chat.completion body as OpenAI SSE chunks.

    The armed sampler always sends ``stream: true`` and parses
    ``text/event-stream``. A single JSON object is accepted at HTTP level
    then decoded as no visible content.
    """
    chat_id = str(payload.get("id") or "s4b5-chat")
    model = str(payload.get("model") or "loopback-model")
    created = int(payload.get("created") or 0)
    usage = payload.get("usage") or SIMULATED_USAGE
    choices = payload.get("choices") or []
    events: list[dict[str, Any]] = []
    if choices:
        choice = choices[0]
        message = choice.get("message") or {}
        finish = choice.get("finish_reason") or "stop"
        tool_calls = message.get("tool_calls") or []
        content = message.get("content")
        if tool_calls:
            streamed = []
            for index, call in enumerate(tool_calls):
                function = call.get("function") or {}
                streamed.append(
                    {
                        "index": index,
                        "id": call.get("id"),
                        "type": call.get("type") or "function",
                        "function": {
                            "name": function.get("name"),
                            "arguments": function.get("arguments") or "",
                        },
                    }
                )
            events.append(
                {
                    "id": chat_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "delta": {
                                "role": "assistant",
                                "content": None,
                                "tool_calls": streamed,
                            },
                            "finish_reason": None,
                        }
                    ],
                }
            )
            events.append(
                {
                    "id": chat_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "delta": {},
                            "finish_reason": finish,
                        }
                    ],
                    "usage": usage,
                }
            )
        else:
            events.append(
                {
                    "id": chat_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [
                        {
                            "index": 0,
                            "delta": {
                                "role": "assistant",
                                "content": content or "",
                            },
                            "finish_reason": finish,
                        }
                    ],
                }
            )
            events.append(
                {
                    "id": chat_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [],
                    "usage": usage,
                }
            )
    else:
        events.append(
            {
                "id": chat_id,
                "object": "chat.completion.chunk",
                "created": created,
                "model": model,
                "choices": [],
                "usage": usage,
            }
        )
    parts = [
        f"data: {json.dumps(event, separators=(',', ':'))}\n\n" for event in events
    ]
    parts.append("data: [DONE]\n\n")
    return "".join(parts).encode()


def _tool_call(chat_id: str, call_id: str, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": chat_id,
        "object": "chat.completion",
        "created": 0,
        "model": "loopback-model",
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": None,
                    "tool_calls": [
                        {
                            "id": call_id,
                            "type": "function",
                            "function": {
                                "name": name,
                                "arguments": json.dumps(arguments, separators=(",", ":")),
                            },
                        }
                    ],
                },
                "finish_reason": "tool_calls",
            }
        ],
        "usage": SIMULATED_USAGE,
    }


def serve_stdio(mode: str = "normal", status_path: Path | None = None) -> None:
    cluster = LoopbackCluster(mode=mode, status_path=status_path)
    identity = cluster.start()
    cluster.write_status()
    print(json.dumps(identity, separators=(",", ":")), flush=True)
    try:
        os.read(0, 1)
    finally:
        print(json.dumps(cluster.snapshot(), separators=(",", ":")), flush=True)
        cluster.close()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="4B.5 test-only loopback provider")
    parser.add_argument("--mode", default="normal")
    parser.add_argument("--status-file")
    args = parser.parse_args()
    serve_stdio(args.mode, Path(args.status_file) if args.status_file else None)
