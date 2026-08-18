"""Extract one allowlisted v2 receipt from GrokBuild-owned typed checkpoints."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from .errors import DriverError


_HARD_BUDGET_PROJECTION_FIELDS = (
    "status",
    "ledgerRevision",
    "nextSequence",
    "reservationCount",
    "reason",
    "requests",
)
_HARD_BUDGET_REQUEST_FIELDS = (
    "reservationID",
    "sequence",
    "providerRequestID",
    "model",
    "endpointSHA256",
    "apiBackend",
    "payloadBytes",
    "maxOutputTokens",
    "reservedTokens",
    "actualTokens",
    "chargedTokens",
    "lifecycle",
)
_HARD_BUDGET_AUTHORITY_FIELDS = (
    "campaignID",
    "manifestSHA256",
    "allocationID",
    "packetID",
    "cliBuild",
    "routeModel",
    "endpointSHA256",
    "apiBackend",
    "requestBoundTokens",
    "maxPayloadBytes",
    "maxOutputTokens",
    "boundProvenanceSHA256",
    "preDispatchNextSequence",
    "preDispatchLedgerRevision",
    "candidateBinarySHA256",
    "candidateProvenanceSHA256",
    "candidateSourceSHA",
    "candidateTeamIdentifier",
    "candidateDesignatedRequirement",
    "candidateCodeDirectoryHash",
)


def attempt_started(packet: dict[str, Any], run_id: str, app_launch_epoch: int, identities: dict[str, str] | None = None) -> dict[str, Any]:
    identities = identities or {}
    return {
        "schemaVersion": 2,
        "rowType": "attemptStarted",
        "runId": run_id,
        "packetId": packet["id"],
        "marker": packet["marker"],
        "promptHash": packet["promptHash"],
        "attempt": 1,
        "tabId": identities.get("tabId", ""),
        "backendId": identities.get("backendId", ""),
        "processGeneration": None,
        "appLaunchEpoch": app_launch_epoch,
        "status": "reserved",
        "reservedTokens": packet["tokenAllocation"],
        "maxModelCalls": packet["maxModelCalls"],
    }


def terminal_failure(
    packet: dict[str, Any],
    run_id: str,
    reason: str,
    app_launch_epoch: int,
    identities: dict[str, str] | None = None,
) -> dict[str, Any]:
    identities = identities or {}
    return {
        "schemaVersion": 2,
        "rowType": "terminal",
        "runId": run_id,
        "packetId": packet["id"],
        "marker": packet["marker"],
        "promptHash": packet["promptHash"],
        "attempt": 1,
        "tabId": identities.get("tabId", ""),
        "backendId": identities.get("backendId", ""),
        "processGeneration": identities.get("processGeneration"),
        "appLaunchEpoch": app_launch_epoch,
        "status": "failed",
        "configuredRoute": None,
        "observedRoute": None,
        "usage": None,
        "cost": {"providerCostUsdTicks": None, "providerCostIsPartial": None, "frozenEstimateUsd": None, "reconciliation": "unavailable"},
        "toolReceipts": [],
        "workerReceipts": [],
        "coordination": None,
        "hardBudgetPreDispatchAuthority": None,
        "hardBudgetTerminalProjection": None,
        "outcome": "failed",
        "checkpointDigest": None,
        "failure": _failure_code(reason),
    }


def reject_terminal(terminal: dict[str, Any], reason: str) -> dict[str, Any]:
    """Preserve every settled paid receipt while marking acceptance rejection."""
    rejected = dict(terminal)
    rejected["status"] = "rejected"
    rejected["failure"] = _failure_code(reason)
    return rejected


def cleanup_receipt(
    packet: dict[str, Any],
    run_id: str,
    identities: dict[str, Any],
    app_launch_epoch: int,
    *,
    local_tab: str,
) -> dict[str, Any]:
    return {
        "schemaVersion": 2,
        "rowType": "cleanup",
        "runId": run_id,
        "packetId": packet["id"],
        "marker": packet["marker"],
        "promptHash": packet["promptHash"],
        "attempt": 1,
        "tabId": str(identities.get("tabId") or ""),
        "backendId": str(identities.get("backendId") or ""),
        "processGeneration": identities.get("processGeneration"),
        "appLaunchEpoch": app_launch_epoch,
        "status": "cleanup",
        "cleanup": {"localTab": local_tab, "backendSession": "retained"},
    }


def extract_terminal(
    packet: dict[str, Any],
    run_id: str,
    identities: dict[str, str],
    transcripts_dir: Path,
    app_launch_epoch: int,
) -> dict[str, Any]:
    path = transcripts_dir / f"{identities['tabId']}.json"
    try:
        envelope = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DriverError("typed transcript checkpoint unavailable") from exc
    message = _message_for_prompt(envelope.get("messages") or [], packet["prompt"], packet["marker"])
    trace = message.get("assistantTrace") or {}
    checkpoint = trace.get("checkpoint") or {}
    if checkpoint.get("isSettled") is not True:
        raise DriverError("typed checkpoint is not an authoritative settled turn")
    outcome = checkpoint.get("outcomeCode") or checkpoint.get("outcome")
    completed = outcome == "completed"
    content = str(message.get("content") or "").strip()
    if completed:
        if packet["workload"] == "noTool":
            if content != packet["marker"]:
                raise DriverError("no-tool response did not return the exact marker")
        elif packet["marker"] not in content:
            raise DriverError("assistant response omitted the exact packet marker")
        for required in packet["requiredResponseTerms"]:
            if required not in content:
                raise DriverError("assistant response omitted a required continuity term")
    configured = checkpoint.get("structuredRouteReceipt")
    observed = checkpoint.get("observedRouteReceipt")
    usage_raw = checkpoint.get("usageReceipt")
    complete_execution_receipt = (
        isinstance(configured, dict) and isinstance(observed, dict) and isinstance(usage_raw, dict)
    )
    if completed and not complete_execution_receipt:
        raise DriverError("settled checkpoint lacks typed route or usage receipt")
    if complete_execution_receipt:
        model_usage = usage_raw.get("modelUsage") or []
        usage = {
            "inputTokens": usage_raw.get("inputTokens"),
            "outputTokens": usage_raw.get("outputTokens"),
            "totalTokens": usage_raw.get("totalTokens"),
            "cachedReadTokens": usage_raw.get("cachedReadTokens"),
            "cacheCreationTokens": usage_raw.get("cacheCreationTokens"),
            "reasoningTokens": usage_raw.get("reasoningTokens"),
            "modelCalls": usage_raw.get("modelCalls"),
            "modelUsageIDs": sorted(
                str(item.get("modelID")) for item in model_usage
                if isinstance(item, dict) and item.get("modelID")
            ),
        }
        estimate = _frozen_estimate(packet.get("frozenPricing"), usage)
        provider_ticks = usage_raw.get("costUsdTicks")
        partial = usage_raw.get("costIsPartial")
        reconciliation = _cost_reconciliation(provider_ticks, partial, estimate)
        tools = _tools(trace, packet)
        workers = _workers(checkpoint, packet)
    else:
        configured = observed = usage = None
        estimate = provider_ticks = partial = None
        reconciliation = "unavailable"
        tools = workers = []
    coordination_raw = checkpoint.get("coordinationReceipt")
    coordination = None
    if complete_execution_receipt and isinstance(coordination_raw, dict):
        coordination = {
            "maximumUsefulConcurrency": coordination_raw.get("maximumUsefulConcurrency"),
        }
    hard_budget_projection = _hard_budget_terminal_projection(
        checkpoint.get("hardBudgetTerminalProjection")
    )
    hard_budget_authority = _hard_budget_pre_dispatch_authority(
        checkpoint.get("hardBudgetReceipt")
    )
    canonical = json.dumps(checkpoint, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "schemaVersion": 2,
        "rowType": "terminal",
        "runId": run_id,
        "packetId": packet["id"],
        "marker": packet["marker"],
        "promptHash": packet["promptHash"],
        "attempt": 1,
        "tabId": identities["tabId"],
        "backendId": identities["backendId"],
        "processGeneration": checkpoint.get("processGeneration"),
        "appLaunchEpoch": app_launch_epoch,
        "status": "settled" if completed else "rejected",
        "configuredRoute": configured,
        "observedRoute": observed,
        "usage": usage,
        "cost": {
            "providerCostUsdTicks": provider_ticks,
            "providerCostIsPartial": partial,
            "frozenEstimateUsd": estimate,
            "reconciliation": reconciliation,
        },
        "toolReceipts": tools,
        "workerReceipts": workers,
        "coordination": coordination,
        "hardBudgetPreDispatchAuthority": hard_budget_authority,
        "hardBudgetTerminalProjection": hard_budget_projection,
        "outcome": outcome,
        "checkpointDigest": hashlib.sha256(canonical).hexdigest(),
        "failure": None if completed else ("budget-stop" if outcome == "userStopped" else "campaign-failure"),
    }


def _hard_budget_terminal_projection(value: Any) -> Any:
    """Persist only the typed Swift terminal projection, never raw ledger material."""
    if not isinstance(value, dict):
        return value
    projection = {field: value.get(field) for field in _HARD_BUDGET_PROJECTION_FIELDS}
    requests = value.get("requests")
    if isinstance(requests, list):
        projection["requests"] = [
            ({field: request.get(field) for field in _HARD_BUDGET_REQUEST_FIELDS}
             if isinstance(request, dict) else request)
            for request in requests
        ]
    return projection


def _hard_budget_pre_dispatch_authority(value: Any) -> Any:
    """Persist only the typed pre-dispatch authority needed to bind a terminal ledger."""
    if not isinstance(value, dict):
        return value
    return {field: value.get(field) for field in _HARD_BUDGET_AUTHORITY_FIELDS}


def _message_for_prompt(messages: list[Any], prompt: str, marker: str) -> dict[str, Any]:
    marker_seen = False
    for message in messages:
        if not isinstance(message, dict):
            continue
        if str(message.get("role") or "").lower() in {"user", "human"}:
            content = str(message.get("content") or "")
            if marker in content and content != prompt:
                raise DriverError("persisted user prompt differs from the frozen packet prompt")
            if content != prompt:
                continue
            marker_seen = True
            continue
        if marker_seen and str(message.get("role") or "").lower() in {"assistant", "agent"}:
            checkpoint = (message.get("assistantTrace") or {}).get("checkpoint")
            if (
                isinstance(checkpoint, dict)
                and checkpoint.get("isSettled") is True
            ):
                return message
    raise DriverError("settled marker checkpoint unavailable")


def _tools(trace: dict[str, Any], packet: dict[str, Any]) -> list[dict[str, Any]]:
    expected_fixtures = packet.get("readFixtures") or []
    rows: list[dict[str, Any]] = []
    for order, tool in enumerate(trace.get("tools") or [], 1):
        if not isinstance(tool, dict):
            continue
        searchable = " ".join(
            str(tool.get(key) or "")
            for key in ("title", "resultDetail", "path", "filePath", "rawInput")
        )
        identity = next(
            (fixture["identity"] for fixture in expected_fixtures if fixture["workspacePath"] in searchable),
            None,
        )
        rows.append({
            "family": _tool_family(tool),
            "qualifiedToolID": _qualified_tool_id(tool),
            "identity": identity,
            "status": _tool_status(tool.get("status")),
            "order": order,
        })
    return rows


def _workers(checkpoint: dict[str, Any], packet: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    expected_roles = set((packet.get("childTopology") or {}).get("roles") or [])
    for worker in checkpoint.get("workerReceipts") or []:
        if not isinstance(worker, dict):
            continue
        title = str(worker.get("title") or "")
        role = next((item for item in expected_roles if item in title), None)
        if role is None:
            role = "unmatched"
        rows.append({
            "role": role,
            "status": worker.get("status"),
            "childBackendSessionID": worker.get("childBackendSessionID"),
            "toolCallCount": worker.get("toolCallCount"),
            "runtimeModelID": worker.get("runtimeModelID"),
        })
    return rows


def _tool_family(tool: dict[str, Any]) -> str:
    qualified = _qualified_tool_id(tool)
    return qualified.rsplit(":", 1)[-1] if qualified else "unrecognized"


def _qualified_tool_id(tool: dict[str, Any]) -> str:
    value = str(tool.get("qualifiedToolName") or tool.get("qualifiedToolID") or "").strip()
    return value if value.startswith("GrokBuild:") else "unrecognized"


def _tool_status(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized in {"succeeded", "success", "completed", "complete"}:
        return "succeeded"
    if normalized in {"failed", "failure", "error"}:
        return "failed"
    if normalized in {"cancelled", "canceled"}:
        return "cancelled"
    return "unknown"


def _frozen_estimate(pricing: Any, usage: dict[str, Any]) -> float | None:
    if not isinstance(pricing, dict):
        return None
    input_tokens = usage.get("inputTokens")
    output_tokens = usage.get("outputTokens")
    if input_tokens is None or output_tokens is None:
        return None
    return round(
        int(input_tokens) * float(pricing["promptUsdPerMillion"]) / 1_000_000
        + int(output_tokens) * float(pricing["completionUsdPerMillion"]) / 1_000_000,
        8,
    )


def _cost_reconciliation(
    provider_ticks: Any,
    partial: Any,
    estimate: float | None,
) -> str:
    if partial is True:
        return "partial"
    if provider_ticks is None:
        return "provider-unavailable" if estimate is not None else "unavailable"
    if estimate is None:
        return "unavailable"
    reported = int(provider_ticks) / 10_000_000_000
    tolerance = 0.00000001
    return "within-upper-bound" if reported <= estimate + tolerance else "variance"


def _failure_code(reason: str) -> str:
    lowered = reason.lower()
    if "budget" in lowered or "allocation" in lowered:
        return "budget-stop"
    for code in ("preflight", "send", "timeout", "route", "usage", "cleanup", "driver"):
        if code in lowered:
            return code
    return "campaign-failure"
