from __future__ import annotations

import copy
import json
import os
import tempfile
import unittest
from pathlib import Path

from scripts.acceptance.harness.errors import ReceiptError, SchemaError
from scripts.acceptance.harness.errors import PreflightError
from scripts.acceptance.harness.preflight_v2 import require_runtime_floor
from scripts.acceptance.harness.receipts_v2 import _validate_row, append_row, evaluate
from scripts.acceptance.harness.schema_v2 import load_manifest
from scripts.acceptance.harness.evidence_v2 import _cost_reconciliation


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "official-provider-slice4-v2.json"
RUN_ID = "20260817T170000Z"


class Slice4V2Contracts(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = load_manifest(MANIFEST, run_id=RUN_ID)
        self.rows = _accepted_rows(self.manifest)

    def test_reference_ledger_is_accepted(self) -> None:
        self.assertEqual(evaluate(self.manifest, self.rows)["outcome"], "accepted")
        self.assertEqual(_cost_reconciliation(126_890_500, False, 0.01268905), "within-upper-bound")
        self.assertEqual(_cost_reconciliation(99_000_000, False, 0.0001), "variance")

    def test_runtime_floor_is_deterministic(self) -> None:
        with self.assertRaises(PreflightError):
            require_runtime_floor("grok 1.0.4")
        self.assertEqual(require_runtime_floor("grok 1.0.6"), "grok 1.0.6")

    def test_negative_usage_and_cost_are_rejected_before_evaluation(self) -> None:
        row = copy.deepcopy(self.rows[1])
        row["usage"]["totalTokens"] = -1
        with self.assertRaises(ReceiptError):
            _validate_row(row)
        row = copy.deepcopy(self.rows[1])
        row["cost"]["providerCostUsdTicks"] = -1
        with self.assertRaises(ReceiptError):
            _validate_row(row)

    def test_nested_unallowlisted_payload_is_rejected(self) -> None:
        row = copy.deepcopy(self.rows[1])
        row["observedRoute"]["responseBody"] = "secret"
        with self.assertRaises(ReceiptError):
            _validate_row(row)

    def test_route_identity_drift_is_rejected(self) -> None:
        rows = copy.deepcopy(self.rows)
        rows[1]["observedRoute"]["backendSessionID"] = "some-other-backend"
        with self.assertRaises(ReceiptError):
            evaluate(self.manifest, rows)

    def test_failed_outcome_worker_and_tool_order_cannot_pass(self) -> None:
        row = copy.deepcopy(self.rows[1])
        row["outcome"] = "failed"
        with self.assertRaises(ReceiptError):
            _validate_row(row)

        rows = copy.deepcopy(self.rows)
        _terminal(rows, "OR-OW-CH2")["workerReceipts"][0]["status"] = "failed"
        with self.assertRaises(ReceiptError):
            evaluate(self.manifest, rows)

        rows = copy.deepcopy(self.rows)
        _terminal(rows, "OAI-H-ORD3")["toolReceipts"][1]["order"] = 1
        with self.assertRaises(ReceiptError):
            evaluate(self.manifest, rows)

    def test_continuation_launch_epoch_lie_is_rejected(self) -> None:
        rows = copy.deepcopy(self.rows)
        t3 = _terminal(rows, "OR-OW-CONT-T3")
        t2 = _terminal(rows, "OR-OW-CONT-T2")
        t3["appLaunchEpoch"] = t2["appLaunchEpoch"]
        _cleanup(rows, "OR-OW-CONT-T3")["appLaunchEpoch"] = t2["appLaunchEpoch"]
        with self.assertRaises(ReceiptError):
            evaluate(self.manifest, rows)

    def test_retained_run_tab_cannot_pass_cleanup(self) -> None:
        rows = copy.deepcopy(self.rows)
        _cleanup(rows, "NAT-CTRL")["cleanup"]["localTab"] = "retained"
        with self.assertRaises(ReceiptError):
            evaluate(self.manifest, rows)

    def test_boolean_budget_and_incomplete_continuation_are_rejected(self) -> None:
        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["packets"][0]["tokenAllocation"] = True
        with self.assertRaises(SchemaError):
            _load_temp(raw)

    def test_tracked_native_read_fixtures_are_hashed_and_missing_fixture_stays_absent(self) -> None:
        ordered = next(packet for packet in self.manifest["packets"] if packet["id"] == "OAI-H-ORD3")
        self.assertEqual(
            [item["identity"] for item in ordered["readFixtures"]],
            ["ONE", "TWO", "THREE"],
        )
        recovery = next(packet for packet in self.manifest["packets"] if packet["id"] == "OR-OW-CONT-T2")
        self.assertEqual(
            [(item["identity"], item["expectedStatus"]) for item in recovery["readFixtures"]],
            [("MISSING", "failed"), ("RECOVERED", "succeeded")],
        )
        self.assertFalse((ROOT / "fixtures/.slice4-native-tools/MISSING.txt").exists())

        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["packets"][2]["readFixtures"][0]["sha256"] = "0" * 64
        with self.assertRaises(SchemaError):
            _load_temp(raw)

        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["packets"][7]["readFixtures"][0]["sha256"] = "0" * 64
        with self.assertRaises(SchemaError):
            _load_temp(raw)

    def test_native_tool_receipts_require_exact_qualified_ids_and_read_identity_order(self) -> None:
        rows = copy.deepcopy(self.rows)
        ordered = _terminal(rows, "OAI-H-ORD3")
        ordered["toolReceipts"][0]["qualifiedToolID"] = "terminal"
        with self.assertRaises(ReceiptError):
            evaluate(self.manifest, rows)

        row = copy.deepcopy(self.rows[1])
        row["toolReceipts"] = [{
            "family": "terminal", "qualifiedToolID": "GrokBuild:read_file",
            "identity": "ONE", "status": "succeeded", "order": 1,
        }]
        with self.assertRaises(ReceiptError):
            _validate_row(row)

        manifest = copy.deepcopy(self.manifest)
        packet = next(item for item in manifest["packets"] if item["id"] == "OAI-H-ORD3")
        packet["allowedTools"].append("GrokBuild:update_plan")
        rows = copy.deepcopy(self.rows)
        ordered = _terminal(rows, "OAI-H-ORD3")
        ordered["toolReceipts"][0].update({"family": "update_plan", "qualifiedToolID": "GrokBuild:update_plan"})
        with self.assertRaisesRegex(ReceiptError, "forbidden tool"):
            evaluate(manifest, rows)

        rows = copy.deepcopy(self.rows)
        recovery = _terminal(rows, "OR-OW-CONT-T2")
        recovery["toolReceipts"][0]["identity"] = "RECOVERED"
        with self.assertRaises(ReceiptError):
            evaluate(self.manifest, rows)

    def test_unqualified_tool_policy_is_rejected_by_schema(self) -> None:
        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["packets"][2]["forbiddenTools"] = ["update_plan"]
        with self.assertRaises(SchemaError):
            _load_temp(raw)

    def test_ledger_refuses_a_preexisting_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "target"
            target.write_text("DO-NOT-CLOBBER", encoding="utf-8")
            ledger = root / "ledger.jsonl"
            os.symlink(target, ledger)
            with self.assertRaises(ReceiptError):
                append_row(ledger, self.rows[0])
            self.assertEqual(target.read_text(encoding="utf-8"), "DO-NOT-CLOBBER")
        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["packets"] = [packet for packet in raw["packets"] if packet["id"] != "OR-OW-CONT-T2"]
        with self.assertRaises(SchemaError):
            _load_temp(raw)


def _load_temp(raw: dict) -> dict:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "manifest.json"
        path.write_text(json.dumps(raw), encoding="utf-8")
        return load_manifest(path, run_id=RUN_ID)


def _terminal(rows: list[dict], packet_id: str) -> dict:
    return next(row for row in rows if row["rowType"] == "terminal" and row["packetId"] == packet_id)


def _cleanup(rows: list[dict], packet_id: str) -> dict:
    return next(row for row in rows if row["rowType"] == "cleanup" and row["packetId"] == packet_id)


def _accepted_rows(manifest: dict) -> list[dict]:
    rows: list[dict] = []
    independent = 0
    continuation_generation = 100
    for packet in manifest["packets"]:
        continuation = packet["continuation"]
        if continuation is None:
            independent += 1
            tab = f"tab-{independent}"
            backend = f"backend-{independent}"
            generation = 200 + independent
            cleanup = "closedExact"
        else:
            tab = "tab-continuation"
            backend = "backend-continuation"
            generation = continuation_generation + (1 if continuation["resumeAfterQuit"] else 0)
            cleanup = "closedExact" if continuation["turn"] == continuation["of"] else "retained"
        epoch = 2 if continuation is not None and continuation["resumeAfterQuit"] else 1
        start = {
            "schemaVersion": 2, "rowType": "attemptStarted", "runId": manifest["runId"],
            "packetId": packet["id"], "marker": packet["marker"], "promptHash": packet["promptHash"],
            "attempt": 1, "tabId": "", "backendId": "", "processGeneration": None,
            "appLaunchEpoch": epoch,
            "status": "reserved", "reservedTokens": packet["tokenAllocation"],
            "maxModelCalls": packet["maxModelCalls"],
        }
        tools, workers = _workload(packet)
        observed = {
            "processGeneration": generation,
            "backendSessionID": backend,
            "requestID": f"request-{packet['id']}",
            "acpAgentVersion": "grok 1.0.5",
            "catalogCurrentModelID": packet["selectorModelID"],
            "catalogContainsSelectedModel": True,
            "sessionModelID": packet["selectorModelID"],
            "resolvedModelID": packet["effectiveModelID"],
            "modelFingerprint": f"fingerprint-{packet['id']}",
            "apiBackend": packet["routeReceipt"]["apiBackend"],
            "turnUsageEffectiveModelID": packet["effectiveModelID"],
            "modelUsageIDs": packet["expectedModelUsageIDs"],
        }
        native = packet["routeReceipt"]["kind"] == "nativeXAI"
        terminal = {
            "schemaVersion": 2, "rowType": "terminal", "runId": manifest["runId"],
            "packetId": packet["id"], "marker": packet["marker"], "promptHash": packet["promptHash"],
            "attempt": 1, "tabId": tab, "backendId": backend, "processGeneration": generation,
            "appLaunchEpoch": epoch,
            "status": "settled", "configuredRoute": packet["routeReceipt"], "observedRoute": observed,
            "usage": {"inputTokens": 1, "outputTokens": 1, "totalTokens": 2,
                      "cachedReadTokens": 0, "cacheCreationTokens": 0, "reasoningTokens": 0,
                      "modelCalls": 1, "modelUsageIDs": packet["expectedModelUsageIDs"]},
            "cost": {"providerCostUsdTicks": None, "providerCostIsPartial": None,
                     "frozenEstimateUsd": None if native else 0.000001,
                     "reconciliation": "unavailable" if native else "provider-unavailable"},
            "toolReceipts": tools, "workerReceipts": workers, "outcome": "completed",
            "coordination": ({"maximumUsefulConcurrency": 2} if packet["childTopology"] else None),
            "checkpointDigest": "0" * 64, "failure": None,
        }
        cleanup_row = {
            "schemaVersion": 2, "rowType": "cleanup", "runId": manifest["runId"],
            "packetId": packet["id"], "marker": packet["marker"], "promptHash": packet["promptHash"],
            "attempt": 1, "tabId": tab, "backendId": backend, "processGeneration": generation,
            "appLaunchEpoch": epoch,
            "status": "cleanup", "cleanup": {"localTab": cleanup, "backendSession": "retained"},
        }
        _validate_row(start)
        _validate_row(terminal)
        _validate_row(cleanup_row)
        rows.extend([start, terminal, cleanup_row])
    return rows


def _workload(packet: dict) -> tuple[list[dict], list[dict]]:
    if packet["readFixtures"]:
        return ([
            {
                "family": "read_file", "qualifiedToolID": "GrokBuild:read_file",
                "identity": fixture["identity"], "status": fixture["expectedStatus"], "order": index,
            }
            for index, fixture in enumerate(packet["readFixtures"], 1)
        ], [])
    if packet["childTopology"] is not None:
        tools = [
            {"family": "task", "qualifiedToolID": "GrokBuild:task", "identity": None, "status": "succeeded", "order": 1},
            {"family": "task", "qualifiedToolID": "GrokBuild:task", "identity": None, "status": "succeeded", "order": 2},
            {"family": "wait_tasks", "qualifiedToolID": "GrokBuild:wait_tasks", "identity": None, "status": "succeeded", "order": 3},
        ]
        workers = [
            {"role": role, "status": "completed", "childBackendSessionID": f"child-{role.lower()}",
             "toolCallCount": 0, "runtimeModelID": packet["effectiveModelID"]}
            for role in packet["childTopology"]["roles"]
        ]
        return tools, workers
    return [], []


if __name__ == "__main__":
    unittest.main()
