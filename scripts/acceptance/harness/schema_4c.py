"""Slice 4C bounded paid-matrix schema.

Version 4 is the locked official-provider route matrix. It is not schema-3
fresh-process continuation and it is not the historical 4M v2 campaign.
Live bind hashes stay out of this committed file; authority fills them at
arm time. Paid Send stays locked until a later unlock commit confirms prices
and narrows the ceiling predicate.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from copy import deepcopy
from pathlib import Path
from typing import Any

from .errors import HarnessError, SchemaError

SCHEMA_VERSION = 4
FROZEN_CAMPAIGN_ID = "slice4c-bounded-paid"
EXPECTED_CLI_BUILD = "1.0.5 (8226242)"
STAGED_SOURCE_SHA = "822624291de2b544605f439ad1349ae6bdc3cf10"
CAMPAIGN_CEILING = 20_000_000
PLANNED_MAXIMUM = 19_000_000
EMERGENCY_RESERVE = 1_000_000
REQUIRED_PACKET_COUNT = 3
REQUIRED_PACKET_KINDS = ("nativeXAI", "directProvider", "brokeredOpenRouter")
# Projection excludes only live runId. Recompute after any other committed edit.
FROZEN_MANIFEST_SHA256 = "934506fac65bc58c2d17ff373a71835cfbe53f862204d9f1c6c99ab38d0967e5"
RUN_ID_LIVE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")
FORBIDDEN_BYTES = {9, 10, 13, 92}

ROOT_FIELDS = {
    "schemaVersion",
    "campaignId",
    "runId",
    "campaignTokenCeiling",
    "plannedTokenMaximum",
    "emergencyReserveTokens",
    "maxAttempts",
    "effort",
    "parentAgent",
    "expectedCLIBuild",
    "pricingConfirmed",
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
    "model",
    "apiBackend",
    "requestBoundTokens",
    "maxPayloadBytes",
    "maxOutputTokens",
}
LIVE_BIND_FIELDS = {"endpointSha256", "boundProvenanceSha256"}
PRICING_FIELDS = {
    "currency",
    "promptUsdPerMillion",
    "completionUsdPerMillion",
    "cacheTreatment",
    "source",
    "campaignConfirmed",
}


def committed_identity_digest(*, path: Path | None = None, raw: dict[str, Any] | None = None) -> str:
    if raw is None:
        if path is None:
            raise SchemaError("4C identity digest needs a path or object")
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise SchemaError(f"4C manifest is unreadable: {exc}") from exc
    if not isinstance(raw, dict):
        raise SchemaError("4C identity projection must be an object")
    projected = {key: value for key, value in raw.items() if key != "runId"}
    encoded = json.dumps(projected, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def require_4c_paid_identity(manifest: dict[str, Any], *, source_path: Path | None = None) -> None:
    """Unlock-predicate helper. Not wired into require_absolute_ceiling_support()."""
    if manifest.get("campaignId") != FROZEN_CAMPAIGN_ID:
        raise SchemaError("4C campaignId must be the frozen product id slice4c-bounded-paid")
    if _integer(manifest.get("campaignTokenCeiling"), "campaignTokenCeiling") != CAMPAIGN_CEILING:
        raise SchemaError("4C campaignTokenCeiling must be 20000000")
    if _integer(manifest.get("plannedTokenMaximum"), "plannedTokenMaximum") != PLANNED_MAXIMUM:
        raise SchemaError("4C plannedTokenMaximum must be 19000000")
    if _integer(manifest.get("emergencyReserveTokens"), "emergencyReserveTokens") != EMERGENCY_RESERVE:
        raise SchemaError("4C emergencyReserveTokens must be 1000000")
    packets = manifest.get("packets")
    if not isinstance(packets, list) or len(packets) != REQUIRED_PACKET_COUNT:
        raise SchemaError("4C day-one matrix requires exactly three packets")
    kinds = []
    for packet in packets:
        route = packet.get("routeReceipt") if isinstance(packet, dict) else None
        kinds.append(route.get("kind") if isinstance(route, dict) else None)
    if tuple(kinds) != REQUIRED_PACKET_KINDS:
        raise SchemaError("4C packets must be nativeXAI then directProvider then brokeredOpenRouter")
    if source_path is not None:
        digest = committed_identity_digest(path=source_path)
        if digest != FROZEN_MANIFEST_SHA256:
            raise SchemaError("4C manifest identity hash mismatch")


def require_4c_send_ready(manifest: dict[str, Any]) -> None:
    """Refuse Send until catalog prices are campaign-confirmed. Ceiling still wins first."""
    if manifest.get("pricingConfirmed") is not True:
        raise HarnessError("4C paid Send remains locked: catalog prices are not campaign-confirmed")
    packets = manifest.get("packets")
    if not isinstance(packets, list):
        raise HarnessError("4C packets are missing")
    for packet in packets:
        if packet.get("continuation") is not None:
            raise HarnessError("4C packets must not continue a session")
        pricing = packet.get("frozenPricing")
        if pricing is None:
            continue
        if pricing.get("campaignConfirmed") is not True:
            raise HarnessError("4C paid Send remains locked: packet prices are not campaign-confirmed")


def validate_4c_document(raw: dict[str, Any]) -> None:
    _exact_fields(raw, ROOT_FIELDS, "manifest")
    if raw["schemaVersion"] != SCHEMA_VERSION:
        raise SchemaError("4C manifest requires schemaVersion 4")
    if raw["campaignId"] != FROZEN_CAMPAIGN_ID:
        raise SchemaError("4C campaignId must be the frozen product id slice4c-bounded-paid")
    if _integer(raw["campaignTokenCeiling"], "campaignTokenCeiling") != CAMPAIGN_CEILING:
        raise SchemaError("campaignTokenCeiling must be exactly 20000000")
    planned_maximum = _integer(raw["plannedTokenMaximum"], "plannedTokenMaximum", minimum=1)
    reserve = _integer(raw["emergencyReserveTokens"], "emergencyReserveTokens", minimum=1)
    if planned_maximum != PLANNED_MAXIMUM:
        raise SchemaError("plannedTokenMaximum must be exactly 19000000")
    if reserve != EMERGENCY_RESERVE:
        raise SchemaError("emergencyReserveTokens must be exactly 1000000")
    if planned_maximum + reserve != CAMPAIGN_CEILING:
        raise SchemaError("planned maximum plus reserve must equal the 4C campaign ceiling")
    if raw["maxAttempts"] != 1:
        raise SchemaError("campaign maxAttempts must be exactly 1")
    if raw["effort"] != "low" or raw["parentAgent"] != "default":
        raise SchemaError("campaign effort must be low and parentAgent default")
    if raw["expectedCLIBuild"] != EXPECTED_CLI_BUILD:
        raise SchemaError("expectedCLIBuild must be exactly 1.0.5 (8226242)")
    if raw["pricingConfirmed"] is not False:
        raise SchemaError("committed 4C pricingConfirmed must stay false until the unlock commit")
    if "GrokBuild:update_plan" not in _native_tool_ids(raw["forbiddenToolsDefault"], "forbiddenToolsDefault"):
        raise SchemaError("forbiddenToolsDefault must include GrokBuild:update_plan")
    if not isinstance(raw["packets"], list) or len(raw["packets"]) != REQUIRED_PACKET_COUNT:
        raise SchemaError("4C day-one matrix requires exactly three packets")


def load_manifest(path: Path, *, run_id: str | None = None) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SchemaError(f"4C manifest is unreadable: {exc}") from exc
    if not isinstance(raw, dict):
        raise SchemaError("4C manifest must be an object")
    digest = committed_identity_digest(raw=raw)
    if digest != FROZEN_MANIFEST_SHA256:
        raise SchemaError("4C manifest identity hash mismatch")
    validate_4c_document(raw)

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
        if packet_id in seen_ids:
            raise SchemaError(f"duplicate packet id {packet_id!r}")
        seen_ids.add(packet_id)
        marker = _required_string(packet["marker"], f"{packet_id}.marker").replace("{runId}", manifest["runId"])
        if marker in seen_markers:
            raise SchemaError(f"duplicate marker {marker!r}")
        seen_markers.add(marker)
        prompt = (
            _required_string(packet["prompt"], f"{packet_id}.prompt")
            .replace("{runId}", manifest["runId"])
            .replace("{marker}", marker)
        )
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
        if packet["workload"] != "noTool":
            raise SchemaError(f"{packet_id}: day-one 4C packets must be noTool")
        if packet["continuation"] is not None:
            raise SchemaError(f"{packet_id}: 4C day-one packets must set continuation to null")
        packet_allocation = _integer(packet["tokenAllocation"], f"{packet_id}.tokenAllocation", minimum=1)
        allocation += packet_allocation
        _integer(packet["maxModelCalls"], f"{packet_id}.maxModelCalls", minimum=1)
        expected_usage = _strings(packet["expectedModelUsageIDs"], f"{packet_id}.expectedModelUsageIDs")
        if len(set(expected_usage)) != len(expected_usage):
            raise SchemaError(f"{packet_id}: duplicate expectedModelUsageIDs")
        _validate_route(packet_id, packet, REQUIRED_PACKET_KINDS[index])
        _validate_tools(packet_id, packet)
        if packet["readFixtures"] != [] or packet["orderedGroups"] != [] or packet["childTopology"] is not None:
            raise SchemaError(f"{packet_id}: day-one 4C packets cannot carry tools, fixtures, or children")
        _validate_pricing(packet_id, packet)
        _validate_hard_budget(packet_id, packet)
        allocation_id = packet["hardBudget"]["allocationID"]
        if allocation_id in seen_allocation_ids:
            raise SchemaError(f"{packet_id}: duplicate hard-budget allocationID")
        seen_allocation_ids.add(allocation_id)

    if allocation > PLANNED_MAXIMUM:
        raise SchemaError(f"packet allocations {allocation} exceed plannedTokenMaximum")
    require_4c_paid_identity(manifest, source_path=path)
    manifest["plannedAllocation"] = allocation
    return manifest


def require_live_run_id(run_id: str) -> None:
    if not RUN_ID_LIVE.fullmatch(run_id):
        raise SchemaError("billable runId must be UTC like 20260819T210000Z")


def dry_run_plan(manifest: dict[str, Any]) -> dict[str, Any]:
    return {
        "mode": "dry-run",
        "schemaVersion": 4,
        "campaignId": manifest["campaignId"],
        "runId": manifest["runId"],
        "campaignTokenCeiling": manifest["campaignTokenCeiling"],
        "plannedTokenMaximum": manifest["plannedTokenMaximum"],
        "plannedAllocation": manifest["plannedAllocation"],
        "emergencyReserveTokens": manifest["emergencyReserveTokens"],
        "expectedCLIBuild": manifest["expectedCLIBuild"],
        "pricingConfirmed": False,
        "billable": False,
        "continuation": None,
        "launch": "four-arg armed launch_installed",
        "packets": [
            {
                "id": packet["id"],
                "marker": packet["marker"],
                "selectorModelID": packet["selectorModelID"],
                "effectiveModelID": packet["effectiveModelID"],
                "routeKind": packet["routeReceipt"]["kind"],
                "tokenAllocation": packet["tokenAllocation"],
                "maxModelCalls": packet["maxModelCalls"],
                "maxAttempts": packet["maxAttempts"],
                "campaignConfirmed": (
                    None
                    if packet["frozenPricing"] is None
                    else packet["frozenPricing"]["campaignConfirmed"]
                ),
                "promptHash": packet["promptHash"],
            }
            for packet in manifest["packets"]
        ],
    }


def _validate_route(packet_id: str, packet: dict[str, Any], expected_kind: str) -> None:
    route = packet["routeReceipt"]
    if not isinstance(route, dict):
        raise SchemaError(f"{packet_id}: routeReceipt must be an object")
    _exact_fields(route, ROUTE_FIELDS, f"{packet_id}.routeReceipt")
    if route["kind"] != expected_kind:
        raise SchemaError(f"{packet_id}: route kind must be {expected_kind}")
    if route["appFallbackEnabled"] is not False:
        raise SchemaError(f"{packet_id}: app fallback must stay disabled")
    if route["selectedModelID"] != packet["selectorModelID"]:
        raise SchemaError(f"{packet_id}: configured route selector mismatch")
    for key in ("selectedModelID", "providerName", "providerModelID"):
        _required_string(route[key], f"{packet_id}.routeReceipt.{key}")
    for key in ("appProviderID", "officialProviderID", "endpointIdentity", "apiBackend"):
        if route[key] is not None and (not isinstance(route[key], str) or not route[key].strip()):
            raise SchemaError(f"{packet_id}: routeReceipt.{key} must be a non-empty string or null")
    if expected_kind == "nativeXAI":
        if route["authBoundary"] != "nativeSession" or route["officialProviderID"] is not None:
            raise SchemaError(f"{packet_id}: native route must use nativeSession without a managed provider")
    else:
        if route["authBoundary"] != "officialHelper":
            raise SchemaError(f"{packet_id}: provider packets must use officialHelper")
    for key in ("modelIsPinned", "servingProviderIsProven"):
        if not isinstance(route[key], bool):
            raise SchemaError(f"{packet_id}: routeReceipt.{key} must be boolean")


def _validate_tools(packet_id: str, packet: dict[str, Any]) -> None:
    allowed = _native_tool_ids(packet["allowedTools"], f"{packet_id}.allowedTools")
    required = _native_tool_ids(packet["requiredTools"], f"{packet_id}.requiredTools")
    forbidden = _native_tool_ids(packet["forbiddenTools"], f"{packet_id}.forbiddenTools")
    _strings(packet["requiredResponseTerms"], f"{packet_id}.requiredResponseTerms")
    if allowed or required:
        raise SchemaError(f"{packet_id}: day-one 4C packets cannot allow tools")
    if "GrokBuild:update_plan" not in forbidden or set(allowed) & set(forbidden):
        raise SchemaError(f"{packet_id}: invalid tool allow/deny sets")


def _validate_pricing(packet_id: str, packet: dict[str, Any]) -> None:
    pricing = packet["frozenPricing"]
    if packet["routeReceipt"]["kind"] == "nativeXAI":
        if pricing is not None:
            raise SchemaError(f"{packet_id}: native 4C pricing must be null")
        return
    if not isinstance(pricing, dict) or set(pricing) != PRICING_FIELDS or pricing["currency"] != "USD":
        raise SchemaError(f"{packet_id}: invalid frozenPricing")
    if pricing["cacheTreatment"] != "uncachedUpperBound":
        raise SchemaError(f"{packet_id}: frozenPricing must label cached input as an uncached upper bound")
    if pricing["campaignConfirmed"] is not False:
        raise SchemaError(f"{packet_id}: committed 4C campaignConfirmed must stay false until unlock")
    _number(pricing["promptUsdPerMillion"], f"{packet_id}.frozenPricing.promptUsdPerMillion", minimum=0)
    _number(pricing["completionUsdPerMillion"], f"{packet_id}.frozenPricing.completionUsdPerMillion", minimum=0)
    _required_string(pricing["source"], f"{packet_id}.frozenPricing.source")


def _validate_hard_budget(packet_id: str, packet: dict[str, Any]) -> None:
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
    extra_live = sorted(set(route) & LIVE_BIND_FIELDS)
    if extra_live:
        raise SchemaError(
            f"{packet_id}: committed 4C hardBudget must not freeze live bind fields {extra_live}"
        )
    _exact_fields(route, HARD_BUDGET_ROUTE_FIELDS, f"{packet_id}.hardBudget.route")
    if route["model"] != packet["effectiveModelID"]:
        raise SchemaError(f"{packet_id}: hard-budget model must equal effectiveModelID")
    if route["apiBackend"] not in {"chat_completions", "responses", "messages"}:
        raise SchemaError(f"{packet_id}: hard-budget API backend is unsupported")
    request_bound = _integer(route["requestBoundTokens"], f"{packet_id}.hardBudget.route.requestBoundTokens", minimum=1)
    payload_bound = _integer(route["maxPayloadBytes"], f"{packet_id}.hardBudget.route.maxPayloadBytes", minimum=1)
    output_bound = _integer(route["maxOutputTokens"], f"{packet_id}.hardBudget.route.maxOutputTokens", minimum=1)
    if payload_bound + output_bound > request_bound or request_bound > packet["tokenAllocation"]:
        raise SchemaError(f"{packet_id}: invalid conservative hard-budget bounds")


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
