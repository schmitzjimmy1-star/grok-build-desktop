"""Allowlisted Slice 4 ledger and strict campaign evaluation."""

from __future__ import annotations

import json
import os
import re
import stat
from pathlib import Path
from typing import Any

from .errors import ReceiptError
from .schema_v2 import ROUTE_FIELDS

COMMON = {
    "schemaVersion", "rowType", "runId", "packetId", "marker", "promptHash",
    "attempt", "tabId", "backendId", "processGeneration", "appLaunchEpoch", "status",
}
START_ONLY = COMMON | {"reservedTokens", "maxModelCalls"}
TERMINAL_ONLY = COMMON | {
    "configuredRoute", "observedRoute", "usage", "cost", "toolReceipts",
    "workerReceipts", "coordination", "outcome", "checkpointDigest", "failure",
}
CLEANUP_ONLY = COMMON | {"cleanup"}
OBSERVED_ROUTE_FIELDS = {
    "processGeneration", "backendSessionID", "requestID", "acpAgentVersion",
    "catalogCurrentModelID", "catalogContainsSelectedModel", "sessionModelID",
    "resolvedModelID", "modelFingerprint", "apiBackend",
    "turnUsageEffectiveModelID", "modelUsageIDs",
}
USAGE_FIELDS = {
    "inputTokens", "outputTokens", "totalTokens", "cachedReadTokens",
    "cacheCreationTokens", "reasoningTokens", "modelCalls", "modelUsageIDs",
}
COST_FIELDS = {
    "providerCostUsdTicks", "providerCostIsPartial", "frozenEstimateUsd", "reconciliation",
}
TOOL_FIELDS = {"family", "qualifiedToolID", "identity", "status", "order"}
WORKER_FIELDS = {"role", "status", "childBackendSessionID", "toolCallCount", "runtimeModelID"}
CLEANUP_FIELDS = {"localTab", "backendSession"}
COORDINATION_FIELDS = {"maximumUsefulConcurrency"}
SEMVER = re.compile(r"\b(\d+)\.(\d+)\.(\d+)")
FAILURE_CODES = {
    "preflight", "send", "timeout", "route", "usage", "cleanup", "driver",
    "campaign-failure", "budget-stop",
}


def append_row(path: Path, row: dict[str, Any]) -> None:
    _validate_row(row)
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags, 0o600)
    except OSError as exc:
        raise ReceiptError("v2 ledger could not be opened without following links") from exc
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        os.close(fd)
        raise ReceiptError("v2 ledger must be an owner-only regular file")
    with os.fdopen(fd, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def load_ledger(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    flags = os.O_RDONLY | (os.O_NOFOLLOW if hasattr(os, "O_NOFOLLOW") else 0)
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        raise ReceiptError("v2 ledger could not be read without following links") from exc
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        os.close(fd)
        raise ReceiptError("v2 ledger must be an owner-only regular file")
    with os.fdopen(fd, "r", encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    for line_no, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ReceiptError(f"v2 ledger line {line_no} is not JSON") from exc
        _validate_row(row)
        rows.append(row)
    return rows


def _validate_row(row: Any) -> None:
    if not isinstance(row, dict) or row.get("schemaVersion") != 2:
        raise ReceiptError("v2 ledger row must be a schemaVersion 2 object")
    expected_by_type = {
        "attemptStarted": START_ONLY,
        "terminal": TERMINAL_ONLY,
        "cleanup": CLEANUP_ONLY,
    }
    expected = expected_by_type.get(row.get("rowType"), set())
    if row.get("rowType") not in expected_by_type:
        raise ReceiptError("v2 ledger rowType is invalid")
    if set(row) != expected:
        raise ReceiptError(
            f"v2 {row.get('rowType')} keys differ: missing={sorted(expected-set(row))} extra={sorted(set(row)-expected)}"
        )
    if row["attempt"] != 1:
        raise ReceiptError("v2 rows require exactly one attempt")
    for key in ("runId", "packetId", "marker", "promptHash", "status"):
        if not isinstance(row[key], str) or not row[key]:
            raise ReceiptError(f"v2 row {key} must be a non-empty string")
    for key in ("tabId", "backendId"):
        if not isinstance(row[key], str):
            raise ReceiptError(f"v2 row {key} must be a string")
    generation = row["processGeneration"]
    if generation is not None and (not isinstance(generation, int) or isinstance(generation, bool) or generation < 0):
        raise ReceiptError("v2 processGeneration must be a nonnegative integer or null")
    _require_positive_int(row["appLaunchEpoch"], "appLaunchEpoch")
    if row["rowType"] == "attemptStarted":
        _require_positive_int(row["reservedTokens"], "reservedTokens")
        _require_positive_int(row["maxModelCalls"], "maxModelCalls")
        if row["status"] != "reserved":
            raise ReceiptError("attemptStarted status must be reserved")
        return
    if row["rowType"] == "cleanup":
        _exact_object(row["cleanup"], CLEANUP_FIELDS, "cleanup")
        if row["status"] != "cleanup":
            raise ReceiptError("cleanup row status must be cleanup")
        if row["cleanup"]["localTab"] not in {"closedExact", "retained", "unknown"}:
            raise ReceiptError("cleanup.localTab is invalid")
        if row["cleanup"]["backendSession"] != "retained":
            raise ReceiptError("Slice 4 cleanup must retain the backend session")
        return
    _validate_terminal_row(row)


def _validate_terminal_row(row: dict[str, Any]) -> None:
    _exact_object(row["cost"], COST_FIELDS, "cost")
    if not isinstance(row["toolReceipts"], list) or not isinstance(row["workerReceipts"], list):
        raise ReceiptError("toolReceipts and workerReceipts must be arrays")
    for index, tool in enumerate(row["toolReceipts"]):
        _exact_object(tool, TOOL_FIELDS, f"toolReceipts[{index}]")
        if not isinstance(tool["family"], str) or not tool["family"]:
            raise ReceiptError("tool family must be non-empty")
        if not isinstance(tool["qualifiedToolID"], str) or not tool["qualifiedToolID"].startswith("GrokBuild:"):
            raise ReceiptError("tool qualifiedToolID must be an exact native GrokBuild ID")
        if tool["family"] != tool["qualifiedToolID"].split(":", 1)[1]:
            raise ReceiptError("tool family must match its exact native GrokBuild ID")
        if tool["identity"] is not None and not isinstance(tool["identity"], str):
            raise ReceiptError("tool identity must be a string or null")
        if tool["status"] not in {"succeeded", "failed", "cancelled", "unknown"}:
            raise ReceiptError("tool status is invalid")
        _require_nonnegative_int(tool["order"], "tool order")
    for index, worker in enumerate(row["workerReceipts"]):
        _exact_object(worker, WORKER_FIELDS, f"workerReceipts[{index}]")
        for key in ("role", "status", "childBackendSessionID"):
            if not isinstance(worker[key], str) or not worker[key]:
                raise ReceiptError(f"worker {key} must be non-empty")
        if worker["toolCallCount"] is not None:
            _require_nonnegative_int(worker["toolCallCount"], "worker toolCallCount")
        if worker["runtimeModelID"] is not None and not isinstance(worker["runtimeModelID"], str):
            raise ReceiptError("worker runtimeModelID must be a string or null")

    _validate_cost(row["cost"])
    if row["status"] == "failed":
        if row["configuredRoute"] is not None or row["observedRoute"] is not None or row["usage"] is not None:
            raise ReceiptError("failed terminal row cannot invent route or usage")
        if row["coordination"] is not None:
            raise ReceiptError("failed terminal row cannot invent coordination evidence")
        if row["failure"] not in FAILURE_CODES:
            raise ReceiptError("failed terminal row requires an allowlisted failure code")
        if row["checkpointDigest"] is not None:
            raise ReceiptError("failed terminal row cannot have a checkpoint digest")
        if row["toolReceipts"] or row["workerReceipts"] or row["outcome"] != "failed":
            raise ReceiptError("failed terminal row cannot invent workload evidence")
        return
    if row["status"] not in {"settled", "rejected"}:
        raise ReceiptError("terminal row must be settled, rejected, or preserve a pre-receipt failure")
    _exact_object(row["configuredRoute"], ROUTE_FIELDS, "configuredRoute")
    _validate_configured_route(row["configuredRoute"])
    _exact_object(row["observedRoute"], OBSERVED_ROUTE_FIELDS, "observedRoute")
    _exact_object(row["usage"], USAGE_FIELDS, "usage")
    if row["coordination"] is not None:
        _exact_object(row["coordination"], COORDINATION_FIELDS, "coordination")
        _require_nonnegative_int(
            row["coordination"]["maximumUsefulConcurrency"],
            "coordination.maximumUsefulConcurrency",
        )
    for key in USAGE_FIELDS - {"modelUsageIDs"}:
        if row["usage"][key] is not None:
            _require_nonnegative_int(row["usage"][key], f"usage.{key}")
    if not isinstance(row["usage"]["modelUsageIDs"], list) or any(
        not isinstance(item, str) or not item for item in row["usage"]["modelUsageIDs"]
    ):
        raise ReceiptError("usage.modelUsageIDs must contain non-empty strings")
    observed = row["observedRoute"]
    for key in OBSERVED_ROUTE_FIELDS - {"processGeneration", "catalogContainsSelectedModel", "modelUsageIDs"}:
        if observed[key] is not None and not isinstance(observed[key], str):
            raise ReceiptError(f"observedRoute.{key} must be a string or null")
    if observed["processGeneration"] is not None:
        _require_nonnegative_int(observed["processGeneration"], "observedRoute.processGeneration")
    if observed["catalogContainsSelectedModel"] is not None and not isinstance(observed["catalogContainsSelectedModel"], bool):
        raise ReceiptError("observedRoute.catalogContainsSelectedModel must be boolean or null")
    if not isinstance(observed["modelUsageIDs"], list) or any(
        not isinstance(item, str) or not item for item in observed["modelUsageIDs"]
    ):
        raise ReceiptError("observedRoute.modelUsageIDs must contain non-empty strings")
    digest = row["checkpointDigest"]
    if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
        raise ReceiptError("settled terminal row requires a SHA-256 checkpoint digest")
    if not row["tabId"] or not row["backendId"] or row["processGeneration"] is None:
        raise ReceiptError("settled terminal row requires exact tab/backend/generation identity")
    if row["status"] == "settled":
        if row["failure"] is not None or row["outcome"] != "completed":
            raise ReceiptError("settled terminal row requires the completed outcome")
    elif row["failure"] not in FAILURE_CODES or not isinstance(row["outcome"], str) or not row["outcome"]:
        raise ReceiptError("rejected terminal row must retain its outcome and failure code")


def _validate_cost(cost: dict[str, Any]) -> None:
    ticks = cost["providerCostUsdTicks"]
    if ticks is not None:
        _require_nonnegative_int(ticks, "cost.providerCostUsdTicks")
    partial = cost["providerCostIsPartial"]
    if partial is not None and not isinstance(partial, bool):
        raise ReceiptError("cost.providerCostIsPartial must be boolean or null")
    estimate = cost["frozenEstimateUsd"]
    if estimate is not None and (not isinstance(estimate, (int, float)) or isinstance(estimate, bool) or estimate < 0):
        raise ReceiptError("cost.frozenEstimateUsd must be nonnegative or null")
    if cost["reconciliation"] not in {
        "exact-match", "within-upper-bound", "variance", "provider-unavailable", "partial", "unavailable",
    }:
        raise ReceiptError("cost.reconciliation is invalid")


def _exact_object(value: Any, fields: set[str], where: str) -> None:
    if not isinstance(value, dict) or set(value) != fields:
        actual = set(value) if isinstance(value, dict) else set()
        raise ReceiptError(
            f"{where} keys differ: missing={sorted(fields-actual)} extra={sorted(actual-fields)}"
        )


def _validate_configured_route(route: dict[str, Any]) -> None:
    string_or_null = ROUTE_FIELDS - {
        "modelIsPinned", "servingProviderIsProven", "appFallbackEnabled",
    }
    for key in string_or_null:
        if route[key] is not None and not isinstance(route[key], str):
            raise ReceiptError(f"configuredRoute.{key} must be a string or null")
    for key in ("modelIsPinned", "servingProviderIsProven", "appFallbackEnabled"):
        if not isinstance(route[key], bool):
            raise ReceiptError(f"configuredRoute.{key} must be boolean")
    if route["appFallbackEnabled"] is not False:
        raise ReceiptError("configuredRoute.appFallbackEnabled must be false")


def _require_nonnegative_int(value: Any, where: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0:
        raise ReceiptError(f"{where} must be a nonnegative integer")


def _require_positive_int(value: Any, where: str) -> None:
    _require_nonnegative_int(value, where)
    if value == 0:
        raise ReceiptError(f"{where} must be positive")


def evaluate_prefix(
    manifest: dict[str, Any],
    rows: list[dict[str, Any]],
    *,
    require_cleanup: bool = True,
) -> dict[str, Any]:
    if not rows or len(rows) % 3 != 0:
        raise ReceiptError("v2 prefix requires complete start+terminal+cleanup row triples")
    packet_count = len(rows) // 3
    if packet_count > len(manifest["packets"]):
        raise ReceiptError("v2 prefix contains more packets than the manifest")
    packets = manifest["packets"][:packet_count]
    actual_tokens = 0
    provider_ticks = 0
    continuation_state: dict[str, tuple[str, str, int, int, int]] = {}
    closed_tabs: set[str] = set()
    observed_tabs: set[str] = set()
    for index, packet in enumerate(packets):
        start, terminal, cleanup = rows[index * 3 : index * 3 + 3]
        _check_identity(packet, start, "attemptStarted", manifest["runId"])
        _check_identity(packet, terminal, "terminal", manifest["runId"])
        _check_identity(packet, cleanup, "cleanup", manifest["runId"])
        if (
            cleanup["tabId"], cleanup["backendId"], cleanup["processGeneration"]
        ) != (
            terminal["tabId"], terminal["backendId"], terminal["processGeneration"]
        ):
            raise ReceiptError(f"{packet['id']}: cleanup identity differs from terminal evidence")
        if cleanup["appLaunchEpoch"] != terminal["appLaunchEpoch"]:
            raise ReceiptError(f"{packet['id']}: cleanup app-launch epoch differs from terminal evidence")
        if start["reservedTokens"] != packet["tokenAllocation"]:
            raise ReceiptError(f"{packet['id']}: reserved token allocation mismatch")
        if start["maxModelCalls"] != packet["maxModelCalls"]:
            raise ReceiptError(f"{packet['id']}: model-call reservation mismatch")
        if terminal["status"] != "settled" or terminal["failure"] is not None:
            raise ReceiptError(f"{packet['id']}: terminal failure is preserved and stops acceptance")
        _check_route(packet, terminal)
        usage = terminal["usage"]
        if not isinstance(usage, dict):
            raise ReceiptError(f"{packet['id']}: usage unavailable")
        total = usage.get("totalTokens")
        calls = usage.get("modelCalls")
        if total is None or calls is None:
            raise ReceiptError(f"{packet['id']}: token/call receipt unavailable")
        if int(total) > int(packet["tokenAllocation"]):
            raise ReceiptError(f"{packet['id']}: packet token allocation exceeded")
        if int(calls) > int(packet["maxModelCalls"]):
            raise ReceiptError(f"{packet['id']}: model-call allocation exceeded")
        usage_ids = sorted(str(item) for item in usage.get("modelUsageIDs") or [])
        if usage_ids != sorted(packet["expectedModelUsageIDs"]):
            raise ReceiptError(f"{packet['id']}: modelUsage IDs mismatch")
        actual_tokens += int(total)
        cost = terminal["cost"]
        if cost.get("providerCostIsPartial") is True:
            raise ReceiptError(f"{packet['id']}: provider cost is partial")
        if packet["routeReceipt"]["kind"] != "nativeXAI" and cost.get("frozenEstimateUsd") is None:
            raise ReceiptError(f"{packet['id']}: frozen provider estimate unavailable")
        reconciliation = cost.get("reconciliation")
        if reconciliation in {"variance", "partial"} or (
            reconciliation == "unavailable" and packet["routeReceipt"]["kind"] != "nativeXAI"
        ):
            raise ReceiptError(f"{packet['id']}: provider cost reconciliation failed")
        ticks = cost.get("providerCostUsdTicks")
        if ticks is not None:
            provider_ticks += int(ticks)
        if cleanup["cleanup"].get("localTab") not in {"retained", "closedExact"}:
            raise ReceiptError(f"{packet['id']}: cleanup receipt is invalid")
        continuation = packet["continuation"]
        should_close = continuation is None or continuation["turn"] == continuation["of"]
        expected_cleanup = "closedExact" if should_close else "retained"
        if require_cleanup and cleanup["cleanup"].get("localTab") != expected_cleanup:
            raise ReceiptError(f"{packet['id']}: exact local-tab cleanup state mismatch")
        observed_tabs.add(terminal["tabId"])
        if cleanup["cleanup"].get("localTab") == "closedExact":
            closed_tabs.add(terminal["tabId"])
        _check_workload(packet, terminal)
        _check_continuation(packet, terminal, continuation_state)
    if actual_tokens > int(manifest["plannedTokenMaximum"]):
        raise ReceiptError("campaign actual tokens exceed planned maximum")
    if actual_tokens + int(manifest["emergencyReserveTokens"]) > int(manifest["campaignTokenCeiling"]):
        raise ReceiptError("campaign reserve was consumed")
    return {
        "schemaVersion": 2,
        "packets": packet_count,
        "actualTokens": actual_tokens,
        "emergencyReserveTokens": manifest["emergencyReserveTokens"],
        "providerCostUsdTicks": provider_ticks,
        "outcome": "accepted",
    }


def evaluate(manifest: dict[str, Any], rows: list[dict[str, Any]]) -> dict[str, Any]:
    expected_rows = len(manifest["packets"]) * 3
    if len(rows) != expected_rows:
        raise ReceiptError(f"v2 ledger requires start+terminal+cleanup per packet: expected {expected_rows}, found {len(rows)}")
    summary = evaluate_prefix(manifest, rows)
    closed_tabs = {
        row["tabId"] for row in rows
        if row.get("rowType") == "cleanup" and row.get("cleanup", {}).get("localTab") == "closedExact"
    }
    observed_tabs = {
        row["tabId"] for row in rows
        if row.get("rowType") == "terminal" and row.get("tabId")
    }
    if observed_tabs != closed_tabs:
        raise ReceiptError("every exact run-created local tab must be closed")
    return summary


def _check_identity(packet: dict[str, Any], row: dict[str, Any], row_type: str, run_id: str) -> None:
    if row["rowType"] != row_type or row["runId"] != run_id:
        raise ReceiptError(f"{packet['id']}: ledger row ordering/identity mismatch")
    for key, expected in (("packetId", packet["id"]), ("marker", packet["marker"]), ("promptHash", packet["promptHash"])):
        if row[key] != expected:
            raise ReceiptError(f"{packet['id']}: {key} mismatch")


def _check_route(packet: dict[str, Any], terminal: dict[str, Any]) -> None:
    configured = terminal["configuredRoute"]
    observed = terminal["observedRoute"]
    if configured != packet["routeReceipt"]:
        raise ReceiptError(f"{packet['id']}: configured route mismatch")
    if not isinstance(observed, dict):
        raise ReceiptError(f"{packet['id']}: observed route unavailable")
    if observed.get("catalogContainsSelectedModel") is not True:
        raise ReceiptError(f"{packet['id']}: selected model absent from official catalog")
    if observed.get("catalogCurrentModelID") != packet["selectorModelID"]:
        raise ReceiptError(f"{packet['id']}: current official catalog model mismatch")
    if observed.get("sessionModelID") not in {packet["selectorModelID"], packet["effectiveModelID"]}:
        raise ReceiptError(f"{packet['id']}: session model mismatch")
    if observed.get("resolvedModelID") != packet["effectiveModelID"]:
        raise ReceiptError(f"{packet['id']}: resolved model mismatch")
    if observed.get("turnUsageEffectiveModelID") != packet["effectiveModelID"]:
        raise ReceiptError(f"{packet['id']}: turn usage model mismatch")
    if observed.get("apiBackend") != packet["routeReceipt"].get("apiBackend"):
        raise ReceiptError(f"{packet['id']}: observed API backend mismatch")
    if observed.get("processGeneration") != terminal["processGeneration"]:
        raise ReceiptError(f"{packet['id']}: observed process generation mismatch")
    if observed.get("backendSessionID") != terminal["backendId"]:
        raise ReceiptError(f"{packet['id']}: observed backend mismatch")
    if sorted(observed.get("modelUsageIDs") or []) != sorted(packet["expectedModelUsageIDs"]):
        raise ReceiptError(f"{packet['id']}: observed modelUsage IDs mismatch")
    for key in ("requestID", "modelFingerprint"):
        if not str(observed.get(key) or "").strip():
            raise ReceiptError(f"{packet['id']}: observed {key} unavailable")
    match = SEMVER.search(str(observed.get("acpAgentVersion") or ""))
    if not match or tuple(map(int, match.groups())) < (1, 0, 5):
        raise ReceiptError(f"{packet['id']}: ACP 1.0.5+ observed route receipt required")


def _check_workload(packet: dict[str, Any], terminal: dict[str, Any]) -> None:
    tools = terminal["toolReceipts"]
    if [tool["order"] for tool in tools] != list(range(1, len(tools) + 1)):
        raise ReceiptError(f"{packet['id']}: tool order receipts are not contiguous")
    qualified = [tool["qualifiedToolID"] for tool in tools]
    if set(qualified) - set(packet["allowedTools"]):
        raise ReceiptError(f"{packet['id']}: unallowed tool observed")
    if set(packet["requiredTools"]) - set(qualified):
        raise ReceiptError(f"{packet['id']}: required tool missing")
    if set(qualified) & set(packet["forbiddenTools"]):
        raise ReceiptError(f"{packet['id']}: forbidden tool observed")
    if packet["workload"] == "noTool" and tools:
        raise ReceiptError(f"{packet['id']}: no-tool packet used a tool")
    if any(tool["status"] != "succeeded" for tool in tools) and packet["workload"] != "recovery":
        raise ReceiptError(f"{packet['id']}: tool did not settle successfully")
    expected_fixtures = packet.get("readFixtures") or []
    if expected_fixtures:
        expected_statuses = [fixture["expectedStatus"] for fixture in expected_fixtures]
        if [tool["status"] for tool in tools] != expected_statuses:
            raise ReceiptError(f"{packet['id']}: native read status evidence mismatch")
    for group in packet["orderedGroups"]:
        actual = [tool["identity"] for tool in tools]
        if actual != group:
            raise ReceiptError(f"{packet['id']}: ordered tool evidence mismatch")
        if len(tools) != len(group):
            raise ReceiptError(f"{packet['id']}: unexpected extra tool receipt")
    topology = packet["childTopology"]
    if topology is not None:
        workers = terminal["workerReceipts"]
        if len(workers) != topology["count"]:
            raise ReceiptError(f"{packet['id']}: child count mismatch")
        if sorted(worker["role"] for worker in workers) != sorted(topology["roles"]):
            raise ReceiptError(f"{packet['id']}: child roles mismatch")
        if any(worker["status"] != "completed" for worker in workers):
            raise ReceiptError(f"{packet['id']}: child did not complete successfully")
        if any(worker["runtimeModelID"] != packet["effectiveModelID"] for worker in workers):
            raise ReceiptError(f"{packet['id']}: child runtime model did not inherit the selected route")
        child_ids = [worker["childBackendSessionID"] for worker in workers]
        if len(set(child_ids)) != len(child_ids):
            raise ReceiptError(f"{packet['id']}: child backend identities are not unique")
        if qualified.count("GrokBuild:task") != topology["count"] or qualified.count(topology["collection"]) != 1:
            raise ReceiptError(f"{packet['id']}: child coordination tools mismatch")
        if qualified != ["GrokBuild:task", "GrokBuild:task", topology["collection"]]:
            raise ReceiptError(f"{packet['id']}: child coordination tool order mismatch")
        coordination = terminal["coordination"]
        if not isinstance(coordination, dict) or coordination.get("maximumUsefulConcurrency") != topology["maxSimultaneous"]:
            raise ReceiptError(f"{packet['id']}: maximum simultaneous child evidence mismatch")
    elif terminal["coordination"] is not None:
        raise ReceiptError(f"{packet['id']}: unexpected child coordination evidence")


def _check_continuation(
    packet: dict[str, Any],
    terminal: dict[str, Any],
    state: dict[str, tuple[str, str, int, int, int]],
) -> None:
    continuation = packet["continuation"]
    if continuation is None:
        return
    group = continuation["group"]
    turn = int(continuation["turn"])
    generation = int(terminal["processGeneration"])
    epoch = int(terminal["appLaunchEpoch"])
    if turn == 1:
        if group in state:
            raise ReceiptError(f"{packet['id']}: duplicate continuation group")
        state[group] = (terminal["tabId"], terminal["backendId"], epoch, generation, turn)
        return
    prior = state.get(group)
    if prior is None or turn != prior[4] + 1:
        raise ReceiptError(f"{packet['id']}: continuation order mismatch")
    if (terminal["tabId"], terminal["backendId"]) != prior[:2]:
        raise ReceiptError(f"{packet['id']}: continuation tab/backend identity drift")
    if continuation["resumeAfterQuit"] and epoch == prior[2]:
        raise ReceiptError(f"{packet['id']}: relaunch continuation reused an app-launch epoch")
    if not continuation["resumeAfterQuit"]:
        if epoch != prior[2]:
            raise ReceiptError(f"{packet['id']}: in-process continuation changed app-launch epoch")
        if generation != prior[3]:
            raise ReceiptError(f"{packet['id']}: in-process continuation changed process generation")
    state[group] = (prior[0], prior[1], epoch, generation, turn)
