"""Strict Slice 4 billable-campaign schema.

Version 2 is intentionally separate from the historical v1 harness so old
receipts remain reproducible while the paid lane gets hard reserve accounting,
one-attempt packets, and structured route/cost expectations.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from copy import deepcopy
from pathlib import Path
from typing import Any

from .errors import SchemaError

SCHEMA_VERSION = 2
CAMPAIGN_CEILING = 4_000_000
PLANNED_MAXIMUM = 3_000_000
MINIMUM_RESERVE = 1_000_000
RUN_ID_LIVE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")
ROUTE_KINDS = {"nativeXAI", "directProvider", "brokeredOpenRouter", "localEndpoint", "unavailable"}
WORKLOADS = {"noTool", "orderedMultiTool", "twoChildCoordination", "continuation", "recovery"}
FORBIDDEN_BYTES = {9, 10, 13, 92}

ROOT_FIELDS = {
    "schemaVersion",
    "runId",
    "campaignTokenCeiling",
    "plannedTokenMaximum",
    "emergencyReserveTokens",
    "maxAttempts",
    "effort",
    "parentAgent",
    "forbiddenToolsDefault",
    "packets",
}
PACKET_FIELDS = {
    "id",
    "marker",
    "prompt",
    "selectorModelID",
    "effectiveModelID",
    "expectedModelUsageIDs",
    "routeReceipt",
    "tokenAllocation",
    "maxModelCalls",
    "maxAttempts",
    "workload",
    "allowedTools",
    "requiredTools",
    "forbiddenTools",
    "requiredResponseTerms",
    "orderedGroups",
    "childTopology",
    "continuation",
    "frozenPricing",
}
ROUTE_FIELDS = {
    "kind",
    "selectedModelID",
    "providerName",
    "appProviderID",
    "officialProviderID",
    "endpointIdentity",
    "providerModelID",
    "apiBackend",
    "authBoundary",
    "modelIsPinned",
    "servingProviderIsProven",
    "appFallbackEnabled",
}


def _strings(value: Any, where: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise SchemaError(f"{where}: expected non-empty strings")
    return value


def _integer(value: Any, where: str, *, minimum: int | None = None) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise SchemaError(f"{where}: expected an integer")
    if minimum is not None and value < minimum:
        raise SchemaError(f"{where}: must be at least {minimum}")
    return value


def _number(value: Any, where: str, *, minimum: float | None = None) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise SchemaError(f"{where}: expected a number")
    result = float(value)
    if not math.isfinite(result):
        raise SchemaError(f"{where}: must be finite")
    if minimum is not None and result < minimum:
        raise SchemaError(f"{where}: must be at least {minimum}")
    return result


def _required_string(value: Any, where: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise SchemaError(f"{where}: expected a non-empty string")
    return value


def _exact_fields(value: dict[str, Any], expected: set[str], where: str) -> None:
    missing = sorted(expected - set(value))
    extra = sorted(set(value) - expected)
    if missing or extra:
        raise SchemaError(f"{where}: missing={missing} extra={extra}")


def load_manifest(path: Path, *, run_id: str | None = None) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SchemaError(f"v2 manifest is unreadable: {exc}") from exc
    if not isinstance(raw, dict):
        raise SchemaError("v2 manifest must be an object")
    _exact_fields(raw, ROOT_FIELDS, "manifest")
    if raw["schemaVersion"] != SCHEMA_VERSION:
        raise SchemaError("v2 manifest requires schemaVersion 2")
    if _integer(raw["campaignTokenCeiling"], "campaignTokenCeiling") != CAMPAIGN_CEILING:
        raise SchemaError("campaignTokenCeiling must be exactly 4000000")
    planned_maximum = _integer(raw["plannedTokenMaximum"], "plannedTokenMaximum", minimum=1)
    reserve = _integer(raw["emergencyReserveTokens"], "emergencyReserveTokens", minimum=1)
    if planned_maximum > PLANNED_MAXIMUM:
        raise SchemaError("plannedTokenMaximum may not exceed 3000000")
    if reserve < MINIMUM_RESERVE:
        raise SchemaError("emergencyReserveTokens must be at least 1000000")
    if planned_maximum + reserve > CAMPAIGN_CEILING:
        raise SchemaError("planned maximum plus reserve exceeds campaign ceiling")
    if raw["maxAttempts"] != 1:
        raise SchemaError("campaign maxAttempts must be exactly 1")
    if raw["effort"] != "low" or raw["parentAgent"] != "default":
        raise SchemaError("campaign effort must be low and parentAgent default")
    if "update_plan" not in _strings(raw["forbiddenToolsDefault"], "forbiddenToolsDefault"):
        raise SchemaError("forbiddenToolsDefault must include update_plan")
    if not isinstance(raw["packets"], list) or not raw["packets"]:
        raise SchemaError("packets must be a non-empty list")

    manifest = deepcopy(raw)
    manifest["runId"] = run_id or str(raw["runId"])
    seen_ids: set[str] = set()
    seen_markers: set[str] = set()
    allocation = 0
    for index, packet in enumerate(manifest["packets"]):
        if not isinstance(packet, dict):
            raise SchemaError(f"packets[{index}] must be an object")
        _exact_fields(packet, PACKET_FIELDS, f"packets[{index}]")
        packet_id = _required_string(packet["id"], f"packets[{index}].id")
        if not packet_id or packet_id in seen_ids:
            raise SchemaError(f"duplicate or empty packet id {packet_id!r}")
        seen_ids.add(packet_id)
        marker = _required_string(packet["marker"], f"{packet_id}.marker").replace("{runId}", manifest["runId"])
        if not marker or marker in seen_markers:
            raise SchemaError(f"duplicate or empty marker {marker!r}")
        seen_markers.add(marker)
        prompt = _required_string(packet["prompt"], f"{packet_id}.prompt").replace("{runId}", manifest["runId"]).replace("{marker}", marker)
        encoded = prompt.encode("utf-8")
        if any(byte in FORBIDDEN_BYTES for byte in encoded):
            raise SchemaError(f"{packet_id}: prompt contains forbidden control/escape bytes")
        if prompt.count(marker) != 1:
            raise SchemaError(f"{packet_id}: prompt must contain its marker exactly once")
        packet["marker"] = marker
        packet["prompt"] = prompt
        packet["promptHash"] = hashlib.sha256(encoded).hexdigest()
        if packet["maxAttempts"] != 1:
            raise SchemaError(f"{packet_id}: maxAttempts must be exactly 1")
        packet_allocation = _integer(packet["tokenAllocation"], f"{packet_id}.tokenAllocation", minimum=1)
        allocation += packet_allocation
        _integer(packet["maxModelCalls"], f"{packet_id}.maxModelCalls", minimum=1)
        if packet["workload"] not in WORKLOADS:
            raise SchemaError(f"{packet_id}: unsupported workload")
        expected_usage = _strings(packet["expectedModelUsageIDs"], f"{packet_id}.expectedModelUsageIDs")
        if len(set(expected_usage)) != len(expected_usage):
            raise SchemaError(f"{packet_id}: duplicate expectedModelUsageIDs")
        route = packet["routeReceipt"]
        if not isinstance(route, dict):
            raise SchemaError(f"{packet_id}: routeReceipt must be an object")
        _exact_fields(route, ROUTE_FIELDS, f"{packet_id}.routeReceipt")
        if route["kind"] not in ROUTE_KINDS or route["appFallbackEnabled"] is not False:
            raise SchemaError(f"{packet_id}: invalid route kind or app fallback")
        if route["selectedModelID"] != packet["selectorModelID"]:
            raise SchemaError(f"{packet_id}: configured route selector mismatch")
        for key in ("selectedModelID", "providerName", "providerModelID"):
            _required_string(route[key], f"{packet_id}.routeReceipt.{key}")
        for key in ("appProviderID", "officialProviderID", "endpointIdentity", "apiBackend"):
            if route[key] is not None and (not isinstance(route[key], str) or not route[key].strip()):
                raise SchemaError(f"{packet_id}: routeReceipt.{key} must be a non-empty string or null")
        if route["authBoundary"] not in {"nativeSession", "officialHelper", "none"}:
            raise SchemaError(f"{packet_id}: invalid auth boundary")
        for key in ("modelIsPinned", "servingProviderIsProven"):
            if not isinstance(route[key], bool):
                raise SchemaError(f"{packet_id}: routeReceipt.{key} must be boolean")
        allowed = _strings(packet["allowedTools"], f"{packet_id}.allowedTools")
        required = _strings(packet["requiredTools"], f"{packet_id}.requiredTools")
        forbidden = _strings(packet["forbiddenTools"], f"{packet_id}.forbiddenTools")
        _strings(packet["requiredResponseTerms"], f"{packet_id}.requiredResponseTerms")
        if "update_plan" not in forbidden or set(allowed) & set(forbidden):
            raise SchemaError(f"{packet_id}: invalid tool allow/deny sets")
        if not set(required).issubset(allowed):
            raise SchemaError(f"{packet_id}: required tools must be allowed")
        if not isinstance(packet["orderedGroups"], list):
            raise SchemaError(f"{packet_id}: orderedGroups must be a list")
        for group in packet["orderedGroups"]:
            _strings(group, f"{packet_id}.orderedGroups[]")
        _validate_topology(packet_id, packet["childTopology"])
        _validate_continuation(packet_id, packet["continuation"])
        _validate_pricing(packet_id, packet["frozenPricing"])

    if allocation > planned_maximum:
        raise SchemaError(f"packet allocations {allocation} exceed plannedTokenMaximum")
    _validate_continuation_groups(manifest["packets"])
    manifest["plannedAllocation"] = allocation
    return manifest


def _validate_topology(packet_id: str, topology: Any) -> None:
    if topology is None:
        return
    if not isinstance(topology, dict) or set(topology) != {"count", "roles", "collection", "maxSimultaneous"}:
        raise SchemaError(f"{packet_id}: invalid childTopology")
    if topology != {"count": 2, "roles": ["LEFT", "RIGHT"], "collection": "wait_all", "maxSimultaneous": 2}:
        raise SchemaError(f"{packet_id}: childTopology must be exact LEFT/RIGHT wait_all")


def _validate_continuation(packet_id: str, continuation: Any) -> None:
    if continuation is None:
        return
    if not isinstance(continuation, dict) or set(continuation) != {"group", "turn", "of", "resumeAfterQuit"}:
        raise SchemaError(f"{packet_id}: invalid continuation")
    _required_string(continuation["group"], f"{packet_id}.continuation.group")
    turn = _integer(continuation["turn"], f"{packet_id}.continuation.turn", minimum=1)
    count = _integer(continuation["of"], f"{packet_id}.continuation.of", minimum=1)
    if not isinstance(continuation["resumeAfterQuit"], bool):
        raise SchemaError(f"{packet_id}: resumeAfterQuit must be boolean")
    if turn > count:
        raise SchemaError(f"{packet_id}: invalid continuation ordinal")


def _validate_continuation_groups(packets: list[dict[str, Any]]) -> None:
    groups: dict[str, list[tuple[int, dict[str, Any]]]] = {}
    for index, packet in enumerate(packets):
        continuation = packet["continuation"]
        if continuation is not None:
            groups.setdefault(continuation["group"], []).append((index, continuation))
    for group, indexed_rows in groups.items():
        indices = [index for index, _ in indexed_rows]
        rows = [row for _, row in indexed_rows]
        counts = {row["of"] for row in rows}
        if len(counts) != 1:
            raise SchemaError(f"continuation group {group}: inconsistent turn count")
        count = next(iter(counts))
        if len(rows) != count or sorted(row["turn"] for row in rows) != list(range(1, count + 1)):
            raise SchemaError(f"continuation group {group}: turns must be complete and contiguous")
        if indices != list(range(indices[0], indices[0] + count)) or [row["turn"] for row in rows] != list(range(1, count + 1)):
            raise SchemaError(f"continuation group {group}: manifest order must be adjacent 1 through N")
        if rows[0]["resumeAfterQuit"]:
            raise SchemaError(f"continuation group {group}: first turn cannot resume after quit")


def _validate_pricing(packet_id: str, pricing: Any) -> None:
    if pricing is None:
        return
    expected = {"currency", "promptUsdPerMillion", "completionUsdPerMillion", "cacheTreatment", "source"}
    if not isinstance(pricing, dict) or set(pricing) != expected or pricing["currency"] != "USD":
        raise SchemaError(f"{packet_id}: invalid frozenPricing")
    if pricing["cacheTreatment"] != "uncachedUpperBound":
        raise SchemaError(f"{packet_id}: frozenPricing must label cached input as an uncached upper bound")
    _number(pricing["promptUsdPerMillion"], f"{packet_id}.frozenPricing.promptUsdPerMillion", minimum=0)
    _number(pricing["completionUsdPerMillion"], f"{packet_id}.frozenPricing.completionUsdPerMillion", minimum=0)
    _required_string(pricing["source"], f"{packet_id}.frozenPricing.source")


def require_live_run_id(run_id: str) -> None:
    if not RUN_ID_LIVE.fullmatch(run_id):
        raise SchemaError("billable runId must be UTC like 20260817T170000Z")


def dry_run_plan(manifest: dict[str, Any]) -> dict[str, Any]:
    return {
        "schemaVersion": 2,
        "runId": manifest["runId"],
        "campaignTokenCeiling": manifest["campaignTokenCeiling"],
        "plannedAllocation": manifest["plannedAllocation"],
        "emergencyReserveTokens": manifest["emergencyReserveTokens"],
        "packets": [
            {
                "id": packet["id"],
                "marker": packet["marker"],
                "selectorModelID": packet["selectorModelID"],
                "effectiveModelID": packet["effectiveModelID"],
                "tokenAllocation": packet["tokenAllocation"],
                "maxModelCalls": packet["maxModelCalls"],
                "maxAttempts": packet["maxAttempts"],
                "routeReceipt": packet["routeReceipt"],
                "promptHash": packet["promptHash"],
            }
            for packet in manifest["packets"]
        ],
    }
