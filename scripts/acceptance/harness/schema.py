"""Load and validate versioned acceptance manifests without extra packages."""

from __future__ import annotations

import hashlib
import json
import re
from copy import deepcopy
from pathlib import Path
from typing import Any

from . import ALLOWED_ANOMALY_CEILINGS, SCHEMA_VERSION
from .errors import SchemaError

REQUIRED_ROOT = (
    "schemaVersion",
    "runId",
    "anomalyCeilingActualTokens",
    "effort",
    "parentAgent",
    "forbiddenToolsDefault",
    "packets",
)
REQUIRED_PACKET = (
    "id",
    "marker",
    "prompt",
    "model",
    "routeKind",
    "effort",
    "parentAgent",
    "allowedTools",
    "requiredTools",
    "forbiddenTools",
    "orderedGroups",
    "parallelGroups",
    "childTopology",
    "checkpointCount",
    "turnCount",
    "continuation",
    "explicitRetryBoundary",
    "expectedReceiptClasses",
    "cleanupIdentities",
)
ROUTE_KINDS = {"nativeXAI", "direct", "openrouterPinned"}
RUN_ID_LIVE = re.compile(r"^[0-9]{8}T[0-9]{6}Z$")
FORBIDDEN_BYTES = {9, 10, 13, 92}


def prompt_receipt(prompt: str, marker: str) -> dict[str, Any]:
    raw = prompt.encode("utf-8")
    return {
        "bytes": len(raw),
        "sha256": hashlib.sha256(raw).hexdigest(),
        "markerCount": prompt.count(marker),
        "forbiddenBytes": sum(1 for byte in raw if byte in FORBIDDEN_BYTES),
    }


def _require_keys(obj: dict[str, Any], keys: tuple[str, ...], *, where: str) -> None:
    missing = [key for key in keys if key not in obj]
    if missing:
        raise SchemaError(f"{where}: missing fields {missing}")


def _as_str_list(value: Any, *, where: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise SchemaError(f"{where}: expected a list of non-empty strings")
    return value


def materialize_text(value: str, *, run_id: str, marker: str) -> str:
    return value.replace("{runId}", run_id).replace("{marker}", marker)


def load_manifest(path: Path, *, run_id: str | None = None) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SchemaError(f"manifest is not JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise SchemaError("manifest must be an object")
    _require_keys(data, REQUIRED_ROOT, where="manifest")
    if data["schemaVersion"] != SCHEMA_VERSION:
        raise SchemaError(f"unsupported schemaVersion {data['schemaVersion']}")
    if data["anomalyCeilingActualTokens"] not in ALLOWED_ANOMALY_CEILINGS:
        raise SchemaError("anomalyCeilingActualTokens must be 250000 or 1500000")
    if data["effort"] != "low":
        raise SchemaError("effort must be low")
    if data["parentAgent"] != "default":
        raise SchemaError("parentAgent must be default")
    forbidden_default = _as_str_list(data["forbiddenToolsDefault"], where="forbiddenToolsDefault")
    if "update_plan" not in forbidden_default:
        raise SchemaError("forbiddenToolsDefault must include update_plan")
    packets = data["packets"]
    if not isinstance(packets, list) or not packets:
        raise SchemaError("packets must be a non-empty list")

    resolved_run_id = run_id or str(data["runId"])
    materialized = deepcopy(data)
    materialized["runId"] = resolved_run_id
    seen_markers: set[str] = set()
    seen_ids: set[str] = set()
    for index, packet in enumerate(materialized["packets"]):
        if not isinstance(packet, dict):
            raise SchemaError(f"packets[{index}] must be an object")
        _require_keys(packet, REQUIRED_PACKET, where=f"packets[{index}]")
        packet_id = packet["id"]
        if packet_id in seen_ids:
            raise SchemaError(f"duplicate packet id: {packet_id}")
        seen_ids.add(packet_id)
        marker_template = str(packet["marker"])
        marker = materialize_text(marker_template, run_id=resolved_run_id, marker="")
        if marker in seen_markers:
            raise SchemaError(f"duplicate marker: {marker}")
        seen_markers.add(marker)
        packet["marker"] = marker
        prompt = materialize_text(str(packet["prompt"]), run_id=resolved_run_id, marker=marker)
        receipt = prompt_receipt(prompt, marker)
        if receipt["forbiddenBytes"]:
            raise SchemaError(f"{packet_id}: prompt contains CR/LF/TAB/backslash bytes")
        if receipt["markerCount"] < 1:
            raise SchemaError(f"{packet_id}: prompt must contain its marker")
        packet["prompt"] = prompt
        packet["promptReceipt"] = receipt
        if packet["routeKind"] not in ROUTE_KINDS:
            raise SchemaError(f"{packet_id}: unknown routeKind")
        if packet["effort"] != "low" or packet["parentAgent"] != "default":
            raise SchemaError(f"{packet_id}: effort must be low and parentAgent default")
        allowed = _as_str_list(packet["allowedTools"], where=f"{packet_id}.allowedTools")
        required = _as_str_list(packet["requiredTools"], where=f"{packet_id}.requiredTools")
        forbidden = _as_str_list(packet["forbiddenTools"], where=f"{packet_id}.forbiddenTools")
        if "update_plan" not in forbidden:
            raise SchemaError(f"{packet_id}: forbiddenTools must include update_plan")
        extra_required = [tool for tool in required if tool not in allowed]
        if extra_required:
            raise SchemaError(f"{packet_id}: required tools must be allowed: {extra_required}")
        overlap = set(allowed) & set(forbidden)
        if overlap:
            raise SchemaError(f"{packet_id}: tools cannot be both allowed and forbidden: {sorted(overlap)}")
        _validate_groups(packet, index=index)
        _validate_child_topology(packet)
        _validate_continuation(packet)
        _validate_retry(packet)
        _validate_cleanup_slots(packet)
        _validate_deliberate_stop(packet)
        if int(packet["checkpointCount"]) < 1 or int(packet["turnCount"]) < 1:
            raise SchemaError(f"{packet_id}: checkpointCount and turnCount must be >= 1")
    return materialized


def _validate_groups(packet: dict[str, Any], *, index: int) -> None:
    for field in ("orderedGroups", "parallelGroups"):
        groups = packet[field]
        if not isinstance(groups, list):
            raise SchemaError(f"packets[{index}].{field} must be a list")
        for group in groups:
            _as_str_list(group, where=f"packets[{index}].{field} item")


def _validate_child_topology(packet: dict[str, Any]) -> None:
    topology = packet["childTopology"]
    if topology is None:
        return
    if not isinstance(topology, dict):
        raise SchemaError(f"{packet['id']}: childTopology must be an object or null")
    if topology.get("count") != 2:
        raise SchemaError(f"{packet['id']}: childTopology.count must be 2")
    roles = topology.get("roles")
    if roles != ["LEFT", "RIGHT"]:
        raise SchemaError(f"{packet['id']}: childTopology.roles must be LEFT then RIGHT")
    if topology.get("collection") != "wait_all":
        raise SchemaError(f"{packet['id']}: childTopology.collection must be wait_all")


def _validate_continuation(packet: dict[str, Any]) -> None:
    continuation = packet["continuation"]
    if continuation is None:
        return
    if not isinstance(continuation, dict):
        raise SchemaError(f"{packet['id']}: continuation must be an object or null")
    for key in ("group", "turn", "of", "resumeAfterQuit"):
        if key not in continuation:
            raise SchemaError(f"{packet['id']}: continuation missing {key}")
    if int(continuation["turn"]) < 1 or int(continuation["of"]) < 1:
        raise SchemaError(f"{packet['id']}: continuation turn/of must be >= 1")
    if int(continuation["turn"]) > int(continuation["of"]):
        raise SchemaError(f"{packet['id']}: continuation turn exceeds of")


def _validate_retry(packet: dict[str, Any]) -> None:
    retry = packet["explicitRetryBoundary"]
    if retry is None:
        return
    if not isinstance(retry, dict) or "tool" not in retry or "failedThenSucceeded" not in retry:
        raise SchemaError(f"{packet['id']}: explicitRetryBoundary is invalid")


def _validate_cleanup_slots(packet: dict[str, Any]) -> None:
    slots = packet["cleanupIdentities"]
    if not isinstance(slots, dict):
        raise SchemaError(f"{packet['id']}: cleanupIdentities must be an object")
    for key in ("tabId", "backendId", "childIds"):
        if key not in slots:
            raise SchemaError(f"{packet['id']}: cleanupIdentities missing {key}")
    if slots["tabId"] is not None and not isinstance(slots["tabId"], str):
        raise SchemaError(f"{packet['id']}: tabId must be string or null")
    if slots["backendId"] is not None and not isinstance(slots["backendId"], str):
        raise SchemaError(f"{packet['id']}: backendId must be string or null")
    _as_str_list(slots["childIds"], where=f"{packet['id']}.childIds")


def _validate_deliberate_stop(packet: dict[str, Any]) -> None:
    if "deliberateStop" not in packet:
        return
    if not isinstance(packet["deliberateStop"], bool):
        raise SchemaError(f"{packet['id']}: deliberateStop must be a boolean")


def require_live_run_id(run_id: str) -> None:
    if not RUN_ID_LIVE.fullmatch(run_id):
        raise SchemaError("billable runId must be UTC like 20260814T180000Z")


def dry_run_plan(manifest: dict[str, Any]) -> dict[str, Any]:
    packets = []
    for packet in manifest["packets"]:
        packets.append(
            {
                "id": packet["id"],
                "marker": packet["marker"],
                "model": packet["model"],
                "routeKind": packet["routeKind"],
                "effort": packet["effort"],
                "parentAgent": packet["parentAgent"],
                "promptReceipt": packet["promptReceipt"],
                "prompt": packet["prompt"],
                "allowedTools": packet["allowedTools"],
                "requiredTools": packet["requiredTools"],
                "forbiddenTools": packet["forbiddenTools"],
                "orderedGroups": packet["orderedGroups"],
                "parallelGroups": packet["parallelGroups"],
                "childTopology": packet["childTopology"],
                "checkpointCount": packet["checkpointCount"],
                "turnCount": packet["turnCount"],
                "continuation": packet["continuation"],
                "explicitRetryBoundary": packet["explicitRetryBoundary"],
                "deliberateStop": bool(packet.get("deliberateStop")),
                "expectedReceiptClasses": packet["expectedReceiptClasses"],
                "cleanupIdentities": packet["cleanupIdentities"],
            }
        )
    return {
        "mode": "dry-run",
        "schemaVersion": manifest["schemaVersion"],
        "runId": manifest["runId"],
        "anomalyCeilingActualTokens": manifest["anomalyCeilingActualTokens"],
        "billable": False,
        "packets": packets,
    }
