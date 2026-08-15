"""Extract redacted receipts from local transcripts. Never print bodies."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .errors import DriverError

_OK = {"succeeded", "ok", "success", "completed", "done"}
_FAIL = {"failed", "error", "cancelled", "canceled", "stopped", "orphaned"}


def _status(raw: Any) -> str:
    text = str(raw or "").strip().lower()
    if text in _OK:
        return "ok"
    if text in _FAIL:
        return "failed"
    return text or "unknown"


def _tool_name(entry: dict[str, Any]) -> tuple[str, str | None]:
    kind = str(entry.get("kind") or "")
    title = str(entry.get("title") or "")
    qualified = str(entry.get("qualifiedToolName") or "")
    blob = f"{kind} {title} {qualified}".lower()
    identity = None
    if "left" in blob:
        identity = "LEFT"
    elif "right" in blob:
        identity = "RIGHT"
    elif " one" in f" {blob}" or blob.endswith("one") or "echo one" in blob:
        identity = "ONE"
    elif " two" in f" {blob}" or "echo two" in blob:
        identity = "TWO"
    elif "three" in blob:
        identity = "THREE"
    if "wait_all" in blob or "wait all" in blob:
        return "wait_all", identity
    if (
        "spawn" in blob
        or "subagent" in blob
        or (
            identity in {"LEFT", "RIGHT"}
            and (
                "child" in blob
                or ("echo" not in blob and "/bin/" not in blob)
            )
        )
    ):
        return "spawn_subagent", identity
    if "terminal" in blob or "bash" in blob or "shell" in blob or "execute" in blob or "/bin/" in blob:
        return "terminal", identity
    if "update_plan" in blob or "update plan" in blob:
        return "update_plan", identity
    name = kind or qualified or title.split()[0] if title else "unknown"
    return name, identity


def extract_receipt(
    packet: dict[str, Any],
    identities: dict[str, str],
    transcripts_dir: Path,
) -> dict[str, Any]:
    tab_id = identities["tabId"]
    path = transcripts_dir / f"{tab_id}.json"
    if not path.exists():
        raise DriverError(f"transcript missing for tab {tab_id}")
    envelope = json.loads(path.read_text(encoding="utf-8"))
    messages = _turn_messages(envelope.get("messages") or [], packet["marker"])
    tools: list[dict[str, Any]] = []
    workers: list[dict[str, Any]] = []
    retries: list[dict[str, Any]] = []
    usage = {
        "input": 0,
        "output": 0,
        "total": 0,
        "cached": 0,
        "reasoning": 0,
    }
    cost = 0
    generation = 1
    model = packet["model"]
    for message in messages:
        if not isinstance(message, dict):
            continue
        trace = message.get("assistantTrace") or {}
        for tool in trace.get("tools") or []:
            if not isinstance(tool, dict):
                continue
            name, identity = _tool_name(tool)
            tools.append(
                {
                    "name": name,
                    "identity": identity,
                    "status": _status(tool.get("status")),
                    "order": len(tools) + 1,
                }
            )
        checkpoint = trace.get("checkpoint") or {}
        if not isinstance(checkpoint, dict):
            continue
        if checkpoint.get("processGeneration"):
            generation = int(checkpoint["processGeneration"])
        if checkpoint.get("modelID"):
            model = str(checkpoint["modelID"])
        if checkpoint.get("parentBackendSessionID"):
            identities["backendId"] = str(checkpoint["parentBackendSessionID"])
        usage_receipt = checkpoint.get("usageReceipt") or {}
        if usage_receipt.get("totalTokens") is not None:
            usage = {
                "input": int(usage_receipt.get("inputTokens") or 0),
                "output": int(usage_receipt.get("outputTokens") or 0),
                "total": int(usage_receipt.get("totalTokens") or 0),
                "cached": int(usage_receipt.get("cachedReadTokens") or 0),
                "reasoning": int(usage_receipt.get("reasoningTokens") or 0),
            }
            cost = int(usage_receipt.get("costUsdTicks") or 0)
        for worker in checkpoint.get("workerReceipts") or checkpoint.get("workers") or []:
            if not isinstance(worker, dict):
                continue
            title = str(worker.get("title") or worker.get("id") or "")
            role = None
            if "LEFT" in title.upper() or title.upper().endswith("LEFT"):
                role = "LEFT"
            elif "RIGHT" in title.upper():
                role = "RIGHT"
            workers.append(
                {
                    "role": role or title or "child",
                    "childId": worker.get("childBackendSessionID") or "",
                    "status": _status(worker.get("status")),
                }
            )
    if packet["explicitRetryBoundary"] is not None:
        terminal = [tool for tool in tools if tool["name"] == "terminal"]
        if len(terminal) >= 2 and terminal[0]["status"] != "ok" and terminal[1]["status"] == "ok":
            retries.append({"tool": "terminal", "status": "ok"})
    child_ids = [worker["childId"] for worker in workers if worker.get("childId")]
    return {
        "packetId": packet["id"],
        "marker": packet["marker"],
        "promptHash": packet["promptReceipt"]["sha256"],
        "tabId": tab_id,
        "backendId": identities["backendId"],
        "childIds": child_ids,
        "route": packet["routeKind"],
        "effectiveModel": model,
        "processGeneration": generation,
        "toolReceipts": tools,
        "workerReceipts": workers,
        "retryReceipts": retries,
        "tokenSplit": usage,
        "costTicks": cost,
        "outcome": "accepted",
        "evidencePath": str(path),
        "cleanupResult": "none",
    }


def _turn_messages(messages: list[Any], marker: str) -> list[dict[str, Any]]:
    """Keep only the user/assistant pair whose prompt contains this packet marker."""
    start = None
    for index, message in enumerate(messages):
        if not isinstance(message, dict):
            continue
        role = str(message.get("role") or "").lower()
        content = message.get("content")
        if role in {"user", "human"} and isinstance(content, str) and marker in content:
            start = index
    if start is None:
        return [message for message in messages if isinstance(message, dict)]
    selected: list[dict[str, Any]] = []
    for message in messages[start:]:
        if not isinstance(message, dict):
            continue
        role = str(message.get("role") or "").lower()
        if selected and role in {"user", "human"}:
            break
        selected.append(message)
    return selected
