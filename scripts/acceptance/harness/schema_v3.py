"""Slice 4B.4 fresh-process continuation contract.

Legacy `resumeAfterQuit` / `session/resume` / `resume_saved_task` continuation is
refused at schema. T1 creates the backend. T2 and T3 must load that same backend
through ACP `session/load` after their own fresh allocated process. Ordinary
consumer Resume current task stays outside acceptance.
"""

from __future__ import annotations

import re
from typing import Any

from .errors import SchemaError

LOAD_METHOD = "session/load"
FORBIDDEN_LOAD_METHODS = {"session/resume", "resume_saved_task"}
CONTINUATION_FIELDS = {
    "group",
    "turn",
    "of",
    "predecessorPacketID",
    "predecessorBackendDigest",
    "expectedLocalTab",
    "freshAppLaunchEpoch",
    "freshProcessGeneration",
    "freshAllocation",
    "sharedCampaignManifest",
    "sharedCampaignLedger",
    "loadMethod",
}
_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_TAB = re.compile(r"^[A-Za-z0-9_.-]{1,128}$")


def validate_fresh_process_continuation(packets: list[dict[str, Any]]) -> None:
    groups: dict[str, list[tuple[int, dict[str, Any], dict[str, Any]]]] = {}
    for index, packet in enumerate(packets):
        continuation = packet.get("continuation")
        if continuation is None:
            continue
        _reject_legacy_continuation(packet.get("id") or f"packets[{index}]", continuation)
        groups.setdefault(continuation["group"], []).append((index, packet, continuation))
    for group, rows in groups.items():
        _validate_group(group, rows)


def _reject_legacy_continuation(packet_id: str, continuation: Any) -> None:
    if not isinstance(continuation, dict):
        raise SchemaError(f"{packet_id}: continuation must be an object")
    if "resumeAfterQuit" in continuation:
        raise SchemaError(f"{packet_id}: resumeAfterQuit is rejected; use freshProcessLoad session/load")
    missing = CONTINUATION_FIELDS - set(continuation)
    extra = set(continuation) - CONTINUATION_FIELDS
    if missing or extra:
        raise SchemaError(f"{packet_id}: invalid continuation missing={sorted(missing)} extra={sorted(extra)}")
    load_method = continuation["loadMethod"]
    if load_method in FORBIDDEN_LOAD_METHODS:
        raise SchemaError(f"{packet_id}: {load_method} is rejected; loadMethod must be session/load")
    if load_method != LOAD_METHOD:
        raise SchemaError(f"{packet_id}: loadMethod must be session/load")


def _validate_group(group: str, rows: list[tuple[int, dict[str, Any], dict[str, Any]]]) -> None:
    indices = [index for index, _, _ in rows]
    continuations = [row for _, _, row in rows]
    packets = [packet for _, packet, _ in rows]
    counts = {row["of"] for row in continuations}
    if len(counts) != 1:
        raise SchemaError(f"continuation group {group}: inconsistent turn count")
    count = next(iter(counts))
    if not isinstance(count, int) or count != 3:
        raise SchemaError(f"continuation group {group}: fresh-process groups must be exactly three turns")
    if len(rows) != 3 or [row["turn"] for row in continuations] != [1, 2, 3]:
        raise SchemaError(f"continuation group {group}: turns must be adjacent 1 through 3")
    if indices != list(range(indices[0], indices[0] + 3)):
        raise SchemaError(f"continuation group {group}: manifest order must be adjacent 1 through 3")

    tab = continuations[0]["expectedLocalTab"]
    if not isinstance(tab, str) or _TAB.fullmatch(tab) is None:
        raise SchemaError(f"continuation group {group}: expectedLocalTab is invalid")
    allocations = [packet.get("hardBudget", {}).get("allocationID") or packet.get("allocationID") for packet in packets]
    if any(not isinstance(item, str) or not item for item in allocations) or len(set(allocations)) != 3:
        raise SchemaError(f"continuation group {group}: each turn needs its own allocation")

    for offset, (packet, continuation) in enumerate(zip(packets, continuations), start=1):
        packet_id = packet["id"]
        if continuation["group"] != group or continuation["turn"] != offset or continuation["of"] != 3:
            raise SchemaError(f"{packet_id}: continuation ordinal mismatch")
        for key in (
            "freshAppLaunchEpoch",
            "freshProcessGeneration",
            "freshAllocation",
            "sharedCampaignManifest",
            "sharedCampaignLedger",
        ):
            if continuation[key] is not True:
                raise SchemaError(f"{packet_id}: {key} must be true")
        if continuation["expectedLocalTab"] != tab:
            raise SchemaError(f"{packet_id}: expectedLocalTab must stay the retained tab")
        if offset == 1:
            if continuation["predecessorPacketID"] is not None or continuation["predecessorBackendDigest"] is not None:
                raise SchemaError(f"{packet_id}: T1 cannot name a predecessor")
            continue
        predecessor = packets[offset - 2]
        if continuation["predecessorPacketID"] != predecessor["id"]:
            raise SchemaError(f"{packet_id}: predecessorPacketID must be the previous packet")
        digest = continuation["predecessorBackendDigest"]
        if not isinstance(digest, str) or _SHA256.fullmatch(digest) is None:
            raise SchemaError(f"{packet_id}: predecessorBackendDigest must be SHA-256")
