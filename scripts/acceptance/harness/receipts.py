"""Load and evaluate structured redacted receipts against a manifest."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from . import ANOMALY_CEILING_ACTUAL_TOKENS
from .errors import ReceiptError

REQUIRED_RECEIPT = (
    "packetId",
    "marker",
    "promptHash",
    "tabId",
    "backendId",
    "childIds",
    "route",
    "effectiveModel",
    "processGeneration",
    "toolReceipts",
    "workerReceipts",
    "retryReceipts",
    "tokenSplit",
    "costTicks",
    "outcome",
    "evidencePath",
    "cleanupResult",
)
TOKEN_FIELDS = ("input", "output", "total", "cached", "reasoning")


def load_ledger(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    text = path.read_text(encoding="utf-8")
    for line_no, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ReceiptError(f"ledger line {line_no} is not JSON") from exc
        if not isinstance(row, dict):
            raise ReceiptError(f"ledger line {line_no} must be an object")
        missing = [key for key in REQUIRED_RECEIPT if key not in row]
        if missing:
            raise ReceiptError(f"missing receipt fields {missing} on line {line_no}")
        rows.append(row)
    return rows


def evaluate(manifest: dict[str, Any], receipts: list[dict[str, Any]]) -> dict[str, Any]:
    packets = manifest["packets"]
    if len(receipts) < len(packets):
        missing_ids = [packet["id"] for packet in packets[len(receipts) :]]
        raise ReceiptError(f"missing receipts: {missing_ids}")
    if len(receipts) > len(packets):
        raise ReceiptError("ledger has more receipts than packets")

    by_id = {row.get("packetId"): row for row in receipts}
    if len(by_id) != len(receipts):
        raise ReceiptError("reordered receipts: duplicate or missing packetId")

    ordered_ids = [packet["id"] for packet in packets]
    ledger_ids = [row["packetId"] for row in receipts]
    if ledger_ids != ordered_ids:
        raise ReceiptError(
            f"reordered receipts: expected {ordered_ids}, found {ledger_ids}"
        )

    total_tokens = 0
    continuation_backends: dict[str, str] = {}
    continuation_tabs: dict[str, str] = {}
    for packet, row in zip(packets, receipts):
        _evaluate_packet(
            packet,
            row,
            continuation_backends=continuation_backends,
            continuation_tabs=continuation_tabs,
        )
        total_tokens += int(row["tokenSplit"]["total"])
        if total_tokens > ANOMALY_CEILING_ACTUAL_TOKENS:
            raise ReceiptError(
                f"ceiling breach: cumulative actual tokens {total_tokens} exceed {ANOMALY_CEILING_ACTUAL_TOKENS}"
            )
    return {
        "packets": len(packets),
        "actualTokens": total_tokens,
        "outcome": "accepted",
    }


def _evaluate_packet(
    packet: dict[str, Any],
    row: dict[str, Any],
    *,
    continuation_backends: dict[str, str],
    continuation_tabs: dict[str, str],
) -> None:
    packet_id = packet["id"]
    if row["marker"] != packet["marker"]:
        raise ReceiptError(f"{packet_id}: marker mismatch")
    expected_hash = packet["promptReceipt"]["sha256"]
    if row["promptHash"] != expected_hash:
        raise ReceiptError(f"{packet_id}: prompt hash mismatch")
    if not _models_match(packet, str(row["effectiveModel"])):
        raise ReceiptError(
            f"wrong model: {packet_id} expected {packet['model']}, found {row['effectiveModel']}"
        )
    if row["route"] != packet["routeKind"]:
        raise ReceiptError(f"{packet_id}: route mismatch")
    if not str(row["tabId"]).strip() or not str(row["backendId"]).strip():
        raise ReceiptError(f"{packet_id}: tabId and backendId are required")
    if int(row["processGeneration"]) < 1:
        raise ReceiptError(f"{packet_id}: processGeneration must be >= 1")

    token_split = row["tokenSplit"]
    if not isinstance(token_split, dict) or any(field not in token_split for field in TOKEN_FIELDS):
        raise ReceiptError(f"{packet_id}: tokenSplit is incomplete")
    if int(token_split["total"]) < 0:
        raise ReceiptError(f"{packet_id}: tokenSplit.total is invalid")

    if row.get("interrupted"):
        raise ReceiptError(f"interrupted horizon: {packet_id}")

    tools = row["toolReceipts"]
    workers = row["workerReceipts"]
    retries = row["retryReceipts"]
    if not isinstance(tools, list) or not isinstance(workers, list) or not isinstance(retries, list):
        raise ReceiptError(f"{packet_id}: tool/worker/retry receipts must be lists")

    _check_tool_order(packet, tools)
    _check_tool_failures(packet, tools)
    _check_children(packet, row, workers)
    _check_retry(packet, retries)
    _check_receipt_classes(packet, row)
    _check_continuation(packet, row, continuation_backends, continuation_tabs)


def _models_match(packet: dict[str, Any], effective: str) -> bool:
    expected = packet["model"]
    if effective == expected:
        return True
    if packet["routeKind"] == "nativeXAI" and effective in {expected, f"{expected}-build"}:
        return True
    return expected.replace("/", "-") == effective.replace("/", "-")


def _tool_names(tools: list[dict[str, Any]]) -> list[str]:
    names = []
    for tool in tools:
        if not isinstance(tool, dict) or "name" not in tool:
            raise ReceiptError("tool receipt missing name")
        identity = tool.get("identity")
        names.append(f"{tool['name']}:{identity}" if identity else tool["name"])
    return names


def _check_tool_order(packet: dict[str, Any], tools: list[dict[str, Any]]) -> None:
    observed = _tool_names(tools)
    for group in packet["orderedGroups"]:
        positions = []
        for expected in group:
            if expected not in observed:
                raise ReceiptError(f"missing receipts: {packet['id']} missing ordered tool {expected}")
            positions.append(observed.index(expected))
        if positions != sorted(positions):
            raise ReceiptError(
                f"reordered receipts: {packet['id']} ordered group {group} observed {observed}"
            )


def _check_tool_failures(packet: dict[str, Any], tools: list[dict[str, Any]]) -> None:
    required = set(packet["requiredTools"])
    retry = packet.get("explicitRetryBoundary") or {}
    retry_tool = retry.get("tool")
    ok_required: set[str] = set()
    for tool in tools:
        name = tool["name"]
        status = str(tool.get("status", ""))
        if name in packet["forbiddenTools"] or name == "update_plan":
            raise ReceiptError(f"{packet['id']}: forbidden tool {name}")
        if name in required and status == "ok":
            ok_required.add(name)
        if name in required and status != "ok" and name != retry_tool:
            raise ReceiptError(f"partial tool failure: {packet['id']} {name} status {status}")
    missing = required - ok_required
    if missing:
        raise ReceiptError(f"missing receipts: {packet['id']} required tools {sorted(missing)}")


def _check_children(
    packet: dict[str, Any],
    row: dict[str, Any],
    workers: list[dict[str, Any]],
) -> None:
    topology = packet["childTopology"]
    if topology is None:
        if workers:
            raise ReceiptError(f"{packet['id']}: unexpected workers")
        return
    by_role = {}
    for worker in workers:
        if not isinstance(worker, dict) or "role" not in worker:
            raise ReceiptError(f"{packet['id']}: worker receipt missing role")
        by_role[worker["role"]] = worker
    for role in topology["roles"]:
        worker = by_role.get(role)
        if worker is None:
            raise ReceiptError(f"missing receipts: {packet['id']} missing child {role}")
        if str(worker.get("status")) != "ok":
            raise ReceiptError(
                f"partial child failure: {packet['id']} {role} status {worker.get('status')}"
            )
        child_id = str(worker.get("childId") or "").strip()
        if not child_id:
            raise ReceiptError(f"{packet['id']}: {role} lacks an exact child identity")
    child_ids = row.get("childIds") or []
    if len(child_ids) != 2:
        raise ReceiptError(f"missing receipts: {packet['id']} needs two childIds")


def _check_retry(packet: dict[str, Any], retries: list[dict[str, Any]]) -> None:
    boundary = packet["explicitRetryBoundary"]
    if boundary is None:
        return
    if not retries:
        raise ReceiptError(f"missing receipts: {packet['id']} missing explicit retry")
    matched = False
    for retry in retries:
        if retry.get("tool") == boundary["tool"] and retry.get("status") == "ok":
            matched = True
    if boundary["failedThenSucceeded"] and not matched:
        raise ReceiptError(f"{packet['id']}: explicit retry did not succeed")


def _check_receipt_classes(packet: dict[str, Any], row: dict[str, Any]) -> None:
    observed: list[str] = []
    if row.get("outcome") == "accepted":
        observed.append("parent-complete")
    for worker in row["workerReceipts"]:
        role = str(worker.get("role", "")).lower()
        observed.append(f"child-{role}")
    for tool in row["toolReceipts"]:
        name = tool["name"]
        identity = tool.get("identity")
        if name == "wait_all":
            observed.append("collection-wait_all")
        elif identity:
            observed.append(f"tool-{name}:{identity}")
        else:
            observed.append(f"tool-{name}")
    for retry in row["retryReceipts"]:
        observed.append(f"retry-{retry.get('tool')}")
    if packet["continuation"] is not None:
        observed.append("continuation")
    expected = packet["expectedReceiptClasses"]
    missing = [item for item in expected if item not in observed]
    if missing:
        raise ReceiptError(f"missing receipts: {packet['id']} classes {missing}")


def _check_continuation(
    packet: dict[str, Any],
    row: dict[str, Any],
    continuation_backends: dict[str, str],
    continuation_tabs: dict[str, str],
) -> None:
    continuation = packet["continuation"]
    if continuation is None:
        return
    group = continuation["group"]
    turn = int(continuation["turn"])
    total = int(continuation["of"])
    backend = str(row["backendId"])
    tab = str(row["tabId"])
    if turn == 1:
        continuation_backends[group] = backend
        continuation_tabs[group] = tab
        return
    expected_backend = continuation_backends.get(group)
    expected_tab = continuation_tabs.get(group)
    if expected_backend is None:
        raise ReceiptError(f"interrupted horizon: {packet['id']} missing earlier continuation")
    if continuation.get("resumeAfterQuit") and (backend != expected_backend):
        raise ReceiptError(
            f"resume mismatch: {packet['id']} backend {backend} != {expected_backend}"
        )
    if not continuation.get("resumeAfterQuit") and (
        backend != expected_backend or tab != expected_tab
    ):
        raise ReceiptError(
            f"resume mismatch: {packet['id']} identity drifted before the quit boundary"
        )
    if turn != total and row.get("horizonClosed"):
        raise ReceiptError(f"interrupted horizon: {packet['id']}")
