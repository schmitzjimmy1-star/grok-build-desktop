"""Slice 4B.4 fresh-process continuation contract.

Legacy `resumeAfterQuit` / `session/resume` / `resume_saved_task` continuation is
refused at schema. T1 creates the backend. T2 and T3 must load that same backend
through ACP `session/load` after their own fresh allocated process. Ordinary
consumer Resume current task stays outside acceptance.
"""

from __future__ import annotations

import json
import re
from copy import deepcopy
from pathlib import Path
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
SCHEMA_VERSION = 3
CAMPAIGN_CEILING = 20_000_000
PLANNED_ALLOCATION = 19_000_000
EMERGENCY_RESERVE = 1_000_000
ROOT_FIELDS = {
    "schemaVersion",
    "runId",
    "campaignTokenCeiling",
    "plannedAllocation",
    "emergencyReserveTokens",
    "packets",
}
PACKET_FIELDS = {
    "id",
    "allocationID",
    "selectorModelID",
    "prompt",
    "marker",
    "continuation",
}


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


def load_manifest(path: Path, run_id: str | None = None) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SchemaError(f"v3 manifest is unreadable: {exc}") from exc
    if not isinstance(raw, dict):
        raise SchemaError("v3 manifest must be an object")
    missing = ROOT_FIELDS - set(raw)
    extra = set(raw) - ROOT_FIELDS
    if missing or extra:
        raise SchemaError(f"invalid v3 manifest missing={sorted(missing)} extra={sorted(extra)}")
    if raw["schemaVersion"] != SCHEMA_VERSION:
        raise SchemaError("v3 manifest requires schemaVersion 3")
    if raw["campaignTokenCeiling"] != CAMPAIGN_CEILING:
        raise SchemaError("v3 campaignTokenCeiling must be 20000000")
    if raw["plannedAllocation"] != PLANNED_ALLOCATION:
        raise SchemaError("v3 plannedAllocation must be 19000000")
    if raw["emergencyReserveTokens"] != EMERGENCY_RESERVE:
        raise SchemaError("v3 emergencyReserveTokens must be 1000000")
    manifest = deepcopy(raw)
    if run_id:
        manifest["runId"] = run_id
    packets = manifest["packets"]
    if not isinstance(packets, list) or not packets:
        raise SchemaError("v3 packets must be a non-empty list")
    for packet in packets:
        packet_id = packet.get("id") if isinstance(packet, dict) else "packet"
        if not isinstance(packet, dict) or set(packet) != PACKET_FIELDS:
            raise SchemaError(f"{packet_id}: invalid v3 packet fields")
        for key in ("id", "allocationID", "selectorModelID", "prompt", "marker"):
            if not isinstance(packet[key], str) or not packet[key].strip():
                raise SchemaError(f"{packet['id']}: {key} must be a non-empty string")
        if packet.get("continuation") is None:
            raise SchemaError(f"{packet['id']}: v3 continuation runner requires continuation on every packet")
    validate_fresh_process_continuation(packets)
    return manifest


def dry_run_plan(manifest: dict[str, Any]) -> dict[str, Any]:
    return {
        "mode": "dry-run",
        "schemaVersion": 3,
        "runId": manifest["runId"],
        "campaignTokenCeiling": manifest["campaignTokenCeiling"],
        "plannedAllocation": manifest["plannedAllocation"],
        "emergencyReserveTokens": manifest["emergencyReserveTokens"],
        "billable": False,
        "continuation": {
            "loadMethod": LOAD_METHOD,
            "turns": 3,
            "allocations": 3,
            "ledgers": 1,
            "t1": "session/new",
            "t2t3": "governed_fresh_process_load",
            "cleanupAfter": "T3",
        },
        "packets": [
            {
                "id": packet["id"],
                "allocationID": packet["allocationID"],
                "selectorModelID": packet["selectorModelID"],
                "marker": packet["marker"],
                "turn": packet["continuation"]["turn"],
                "loadMethod": packet["continuation"]["loadMethod"],
            }
            for packet in manifest["packets"]
        ],
    }
