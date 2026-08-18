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
FULL_CLI_BUILD = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)? \([0-9a-f]{7,40}\)$")
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
    "expectedCLIBuild",
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
    "readFixtures",
    "childTopology",
    "continuation",
    "frozenPricing",
    "hardBudget",
}
READ_FIXTURE_FIELDS = {"identity", "workspacePath", "sha256", "expectedStatus"}
READ_FIXTURE_ROOT = "scripts/acceptance/fixtures/.slice4-native-tools/"
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
HARD_BUDGET_FIELDS = {"allocationID", "route"}
HARD_BUDGET_ROUTE_FIELDS = {
    "model", "endpointSha256", "apiBackend", "requestBoundTokens",
    "maxPayloadBytes", "maxOutputTokens", "boundProvenanceSha256",
}


def _strings(value: Any, where: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise SchemaError(f"{where}: expected non-empty strings")
    return value


def _native_tool_ids(value: Any, where: str) -> list[str]:
    tools = _strings(value, where)
    if any(not tool.startswith("GrokBuild:") or tool == "GrokBuild:" for tool in tools):
        raise SchemaError(f"{where}: tools must be exact qualified GrokBuild IDs")
    return tools


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
    _validate_exact_cli_build(raw["expectedCLIBuild"])
    if "GrokBuild:update_plan" not in _native_tool_ids(raw["forbiddenToolsDefault"], "forbiddenToolsDefault"):
        raise SchemaError("forbiddenToolsDefault must include GrokBuild:update_plan")
    if not isinstance(raw["packets"], list) or not raw["packets"]:
        raise SchemaError("packets must be a non-empty list")

    manifest = deepcopy(raw)
    manifest["runId"] = run_id or str(raw["runId"])
    seen_ids: set[str] = set()
    seen_markers: set[str] = set()
    seen_allocation_ids: set[str] = set()
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
        allowed = _native_tool_ids(packet["allowedTools"], f"{packet_id}.allowedTools")
        required = _native_tool_ids(packet["requiredTools"], f"{packet_id}.requiredTools")
        forbidden = _native_tool_ids(packet["forbiddenTools"], f"{packet_id}.forbiddenTools")
        _strings(packet["requiredResponseTerms"], f"{packet_id}.requiredResponseTerms")
        if "GrokBuild:update_plan" not in forbidden or set(allowed) & set(forbidden):
            raise SchemaError(f"{packet_id}: invalid tool allow/deny sets")
        if not set(required).issubset(allowed):
            raise SchemaError(f"{packet_id}: required tools must be allowed")
        if not isinstance(packet["orderedGroups"], list):
            raise SchemaError(f"{packet_id}: orderedGroups must be a list")
        for group in packet["orderedGroups"]:
            _strings(group, f"{packet_id}.orderedGroups[]")
        _validate_read_fixtures(path, packet_id, packet["readFixtures"])
        _validate_native_read_workload(packet_id, packet)
        _validate_topology(packet_id, packet["childTopology"])
        _validate_continuation(packet_id, packet["continuation"])
        _validate_pricing(packet_id, packet["frozenPricing"])
        _validate_hard_budget(packet_id, packet, raw["expectedCLIBuild"])
        allocation_id = packet["hardBudget"]["allocationID"]
        if allocation_id in seen_allocation_ids:
            raise SchemaError(f"{packet_id}: duplicate hard-budget allocationID")
        seen_allocation_ids.add(allocation_id)

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
    if topology != {"count": 2, "roles": ["LEFT", "RIGHT"], "collection": "GrokBuild:wait_tasks", "maxSimultaneous": 2}:
        raise SchemaError(f"{packet_id}: childTopology must be exact LEFT/RIGHT GrokBuild:wait_tasks")


def _validate_read_fixtures(manifest_path: Path, packet_id: str, fixtures: Any) -> None:
    if not isinstance(fixtures, list):
        raise SchemaError(f"{packet_id}: readFixtures must be a list")
    seen_paths: set[str] = set()
    seen_identities: set[str] = set()
    repo_root = manifest_path.parents[3]
    fixture_root = (repo_root / READ_FIXTURE_ROOT).resolve()
    for index, fixture in enumerate(fixtures):
        where = f"{packet_id}.readFixtures[{index}]"
        if not isinstance(fixture, dict):
            raise SchemaError(f"{where}: expected an object")
        _exact_fields(fixture, READ_FIXTURE_FIELDS, where)
        identity = _required_string(fixture["identity"], f"{where}.identity")
        workspace_path = _required_string(fixture["workspacePath"], f"{where}.workspacePath")
        status = fixture["expectedStatus"]
        if status not in {"succeeded", "failed"}:
            raise SchemaError(f"{where}.expectedStatus must be succeeded or failed")
        if identity in seen_identities or workspace_path in seen_paths:
            raise SchemaError(f"{where}: duplicate read fixture identity or path")
        seen_identities.add(identity)
        seen_paths.add(workspace_path)
        if not workspace_path.startswith(READ_FIXTURE_ROOT) or Path(workspace_path).is_absolute():
            raise SchemaError(f"{where}.workspacePath must stay under the tracked native fixture root")
        resolved = (repo_root / workspace_path).resolve()
        if fixture_root not in resolved.parents:
            raise SchemaError(f"{where}.workspacePath escapes the tracked native fixture root")
        sha = fixture["sha256"]
        if status == "succeeded":
            if not isinstance(sha, str) or re.fullmatch(r"[0-9a-f]{64}", sha) is None:
                raise SchemaError(f"{where}.sha256 must be a SHA-256 for a successful read")
            try:
                actual = hashlib.sha256(resolved.read_bytes()).hexdigest()
            except OSError as exc:
                raise SchemaError(f"{where}: tracked read fixture is unavailable") from exc
            if actual != sha:
                raise SchemaError(f"{where}: tracked read fixture SHA-256 mismatch")
        else:
            if sha is not None:
                raise SchemaError(f"{where}.sha256 must be null for a missing-path read")
            if resolved.exists():
                raise SchemaError(f"{where}: missing-path fixture must remain absent")


def _validate_native_read_workload(packet_id: str, packet: dict[str, Any]) -> None:
    fixtures = packet["readFixtures"]
    if not fixtures:
        if packet["workload"] in {"orderedMultiTool", "recovery"}:
            raise SchemaError(f"{packet_id}: native read workload requires tracked readFixtures")
        return
    if packet["allowedTools"] != ["GrokBuild:read_file"] or packet["requiredTools"] != ["GrokBuild:read_file"]:
        raise SchemaError(f"{packet_id}: native read workload must allow and require only GrokBuild:read_file")
    if len(packet["orderedGroups"]) != 1:
        raise SchemaError(f"{packet_id}: native read workload requires exactly one ordered group")
    identities = [fixture["identity"] for fixture in fixtures]
    if packet["orderedGroups"][0] != identities:
        raise SchemaError(f"{packet_id}: ordered read identities must match tracked fixture order")
    statuses = [fixture["expectedStatus"] for fixture in fixtures]
    if packet["workload"] == "orderedMultiTool" and any(status != "succeeded" for status in statuses):
        raise SchemaError(f"{packet_id}: ordered native reads must all succeed")
    if packet["workload"] == "recovery" and statuses != ["failed", "succeeded"]:
        raise SchemaError(f"{packet_id}: native recovery must be missing-path failure then successful read")


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


def _validate_hard_budget(packet_id: str, packet: dict[str, Any], expected_cli_build: Any) -> None:
    _validate_exact_cli_build(expected_cli_build)
    value = packet["hardBudget"]
    if not isinstance(value, dict):
        raise SchemaError(f"{packet_id}: hardBudget must be an object")
    _exact_fields(value, HARD_BUDGET_FIELDS, f"{packet_id}.hardBudget")
    allocation_id = _required_string(value["allocationID"], f"{packet_id}.hardBudget.allocationID")
    if re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", allocation_id) is None:
        raise SchemaError(f"{packet_id}: hardBudget allocationID is not CLI-safe")
    route = value["route"]
    if not isinstance(route, dict):
        raise SchemaError(f"{packet_id}: hardBudget.route must be an object")
    _exact_fields(route, HARD_BUDGET_ROUTE_FIELDS, f"{packet_id}.hardBudget.route")
    if route["model"] != packet["effectiveModelID"]:
        raise SchemaError(f"{packet_id}: hard-budget model must equal effectiveModelID")
    if route["apiBackend"] not in {"chat_completions", "responses", "messages"}:
        raise SchemaError(f"{packet_id}: hard-budget API backend is unsupported")
    for key in ("endpointSha256", "boundProvenanceSha256"):
        if not isinstance(route[key], str) or re.fullmatch(r"[0-9a-f]{64}", route[key]) is None:
            raise SchemaError(f"{packet_id}: hard-budget {key} must be SHA-256")
    request_bound = _integer(route["requestBoundTokens"], f"{packet_id}.hardBudget.route.requestBoundTokens", minimum=1)
    payload_bound = _integer(route["maxPayloadBytes"], f"{packet_id}.hardBudget.route.maxPayloadBytes", minimum=1)
    output_bound = _integer(route["maxOutputTokens"], f"{packet_id}.hardBudget.route.maxOutputTokens", minimum=1)
    if payload_bound + output_bound > request_bound or request_bound > packet["tokenAllocation"]:
        raise SchemaError(f"{packet_id}: invalid conservative hard-budget bounds")


def _validate_exact_cli_build(value: Any) -> None:
    build = _required_string(value, "expectedCLIBuild")
    if FULL_CLI_BUILD.fullmatch(build) is None:
        raise SchemaError(
            "expectedCLIBuild must be the exact installed xai_grok_version full_version "
            "(for example 1.0.5 (abcdef0)); generic labels and placeholders are forbidden"
        )


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
