from __future__ import annotations

import copy
import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
import stat

from scripts.acceptance.harness.errors import ReceiptError, SchemaError
from scripts.acceptance.harness.errors import PreflightError
from scripts.acceptance.harness.preflight_v2 import require_runtime_floor
from scripts.acceptance.harness.receipts_v2 import _validate_row, append_row, evaluate
from scripts.acceptance.harness.schema_v2 import load_manifest
from scripts.acceptance.harness.evidence_v2 import (
    _cost_reconciliation,
    _hard_budget_pre_dispatch_authority,
    _hard_budget_terminal_projection,
    extract_terminal,
    terminal_failure,
)
from scripts.acceptance.harness.authority_v2 import (
    canonical_cli_manifest,
    prepare_campaign_authority,
    retain_campaign_authority,
    swift_authorization_sidecar,
)


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

    def test_private_cli_authority_is_canonical_and_sidecar_matches_it(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            authority = prepare_campaign_authority(self.manifest, root=Path(directory))
            self.assertEqual(stat.S_IMODE(authority.directory.stat().st_mode), 0o700)
            for path in (authority.cli_manifest, authority.ledger, authority.authorization):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            cli = json.loads(authority.cli_manifest.read_text(encoding="utf-8"))
            self.assertEqual(cli, canonical_cli_manifest(self.manifest))
            self.assertEqual(cli["version"], 1)
            self.assertEqual(cli["ceilingTokens"], 3_000_000)
            self.assertEqual([row["id"] for row in cli["allocations"]], [
                packet["hardBudget"]["allocationID"] for packet in self.manifest["packets"]
            ])
            sidecar = json.loads(authority.authorization.read_text(encoding="utf-8"))
            self.assertEqual(sidecar, swift_authorization_sidecar(self.manifest, authority.cli_manifest, authority.ledger))
            self.assertEqual(sidecar["schemaVersion"], 2)
            self.assertEqual(sidecar["expectedCLIBuild"], self.manifest["expectedCLIBuild"])
            self.assertEqual(sidecar["packets"][0]["route"], cli["allocations"][0]["route"])
            retained = retain_campaign_authority(authority, remove_authorization=True)
            self.assertTrue(retained["cliManifestRetained"])
            self.assertTrue(retained["ledgerRetained"])
            self.assertTrue(retained["authorizationSidecarRemoved"])
            self.assertFalse(authority.authorization.exists())

    def test_hard_budget_route_and_allocation_invariants_are_schema_enforced(self) -> None:
        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["packets"][0]["hardBudget"]["allocationID"] = raw["packets"][1]["hardBudget"]["allocationID"]
        with self.assertRaises(SchemaError):
            _load_temp(raw)
        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["packets"][0]["hardBudget"]["route"]["requestBoundTokens"] = raw["packets"][0]["tokenAllocation"] + 1
        with self.assertRaises(SchemaError):
            _load_temp(raw)
        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["expectedCLIBuild"] = "grokbuild-fork"
        with self.assertRaises(SchemaError):
            _load_temp(raw)

    def test_completed_packet_requires_a_full_settled_hard_budget_projection(self) -> None:
        for mutation in (
            lambda projection: None,
            lambda projection: {**projection, "requests": []},
            lambda projection: {**projection, "status": "ambiguous"},
            lambda projection: {
                **projection,
                "requests": [{
                    **projection["requests"][0],
                    "lifecycle": "reserved",
                    "actualTokens": None,
                }],
            },
        ):
            rows = copy.deepcopy(self.rows)
            terminal = _terminal(rows, "NAT-CTRL")
            terminal["hardBudgetTerminalProjection"] = mutation(
                terminal["hardBudgetTerminalProjection"]
            )
            with self.assertRaises(ReceiptError):
                evaluate(self.manifest, rows)

    def test_hard_budget_records_reject_duplicates_route_drift_and_usage_mismatch(self) -> None:
        rows = copy.deepcopy(self.rows)
        terminal = _terminal(rows, "OAI-H-ORD3")
        projection = terminal["hardBudgetTerminalProjection"]
        duplicate = copy.deepcopy(projection["requests"][0])
        duplicate["sequence"] = 2
        projection["requests"].append(duplicate)
        projection["reservationCount"] = 2
        projection["nextSequence"] = 2
        terminal["usage"]["modelCalls"] = 2
        terminal["usage"]["totalTokens"] = 4
        with self.assertRaisesRegex(ReceiptError, "duplicate hard-budget reservation"):
            evaluate(self.manifest, rows)

        rows = copy.deepcopy(self.rows)
        terminal = _terminal(rows, "OAI-H-ORD3")
        projection = terminal["hardBudgetTerminalProjection"]
        repeated_correlation = copy.deepcopy(projection["requests"][0])
        repeated_correlation["reservationID"] = "reservation-OAI-H-ORD3-2"
        repeated_correlation["sequence"] = 1
        # One provider request can legitimately drive a multi-call tool loop.
        repeated_correlation["providerRequestID"] = projection["requests"][0]["providerRequestID"]
        projection["requests"].append(repeated_correlation)
        projection["reservationCount"] = 2
        projection["nextSequence"] = 2
        terminal["usage"]["modelCalls"] = 2
        terminal["usage"]["totalTokens"] = 4
        self.assertEqual(evaluate(self.manifest, rows)["outcome"], "accepted")

        rows = copy.deepcopy(self.rows)
        _terminal(rows, "NAT-CTRL")["hardBudgetTerminalProjection"]["requests"][0]["model"] = "wrong-model"
        with self.assertRaisesRegex(ReceiptError, "route record mismatch"):
            evaluate(self.manifest, rows)

        rows = copy.deepcopy(self.rows)
        _terminal(rows, "NAT-CTRL")["hardBudgetTerminalProjection"]["requests"][0]["actualTokens"] = 1
        _terminal(rows, "NAT-CTRL")["hardBudgetTerminalProjection"]["requests"][0]["chargedTokens"] = 1
        with self.assertRaisesRegex(ReceiptError, "do not reconcile"):
            evaluate(self.manifest, rows)

        rows = copy.deepcopy(self.rows)
        request = _terminal(rows, "NAT-CTRL")["hardBudgetTerminalProjection"]["requests"][0]
        request["reservedTokens"] = 1
        request["actualTokens"] = 2
        request["chargedTokens"] = 2
        with self.assertRaisesRegex(ReceiptError, "settled charge is invalid"):
            evaluate(self.manifest, rows)

    def test_stop_failure_retains_ambiguous_full_reservation_evidence(self) -> None:
        packet = self.manifest["packets"][0]
        row = terminal_failure(packet, self.manifest["runId"], "user stopped", 1)
        route = packet["hardBudget"]["route"]
        row["hardBudgetTerminalProjection"] = {
            "status": "ambiguous",
            "ledgerRevision": 7,
            "nextSequence": 2,
            "reservationCount": 1,
            "reason": "stop after reservation; full reservation retained",
            "requests": [{
                "reservationID": "reservation-stop",
                "sequence": 1,
                "providerRequestID": "provider-stop",
                "model": route["model"],
                "endpointSHA256": route["endpointSha256"],
                "apiBackend": route["apiBackend"],
                "payloadBytes": 1,
                "maxOutputTokens": 1,
                "reservedTokens": 2,
                "actualTokens": None,
                "chargedTokens": 2,
                "lifecycle": "ambiguous_full_reservation_charged",
            }],
        }
        _validate_row(row)
        self.assertEqual(row["hardBudgetTerminalProjection"]["requests"][0]["chargedTokens"], 2)

    def test_stop_checkpoint_preserves_ambiguous_projection_without_route_or_usage(self) -> None:
        packet = self.manifest["packets"][0]
        checkpoint = {
            "isSettled": True,
            "outcomeCode": "userStopped",
            "processGeneration": 9,
            "hardBudgetReceipt": _hard_budget_authority(packet),
            "hardBudgetTerminalProjection": {
                **_hard_budget_projection(packet),
                "status": "ambiguous",
                "reason": "Stop retained full reservation",
                "requests": [{
                    **_hard_budget_projection(packet)["requests"][0],
                    "actualTokens": None,
                    "chargedTokens": 2,
                    "lifecycle": "ambiguous_full_reservation_charged",
                }],
            },
        }
        envelope = {"messages": [
            {"role": "user", "content": packet["prompt"]},
            {"role": "assistant", "content": "", "assistantTrace": {"checkpoint": checkpoint}},
        ]}
        with tempfile.TemporaryDirectory() as directory:
            transcripts = Path(directory)
            (transcripts / "stop-tab.json").write_text(json.dumps(envelope), encoding="utf-8")
            row = extract_terminal(
                packet, self.manifest["runId"], {"tabId": "stop-tab", "backendId": "stop-backend"},
                transcripts, 1,
            )
        self.assertEqual(row["status"], "rejected")
        self.assertIsNone(row["configuredRoute"])
        self.assertIsNone(row["observedRoute"])
        self.assertIsNone(row["usage"])
        self.assertEqual(row["hardBudgetTerminalProjection"]["status"], "ambiguous")
        self.assertEqual(row["hardBudgetTerminalProjection"]["requests"][0]["chargedTokens"], 2)
        _validate_row(row)

    def test_terminal_projection_is_allowlisted_before_receipt_persistence(self) -> None:
        projection = _hard_budget_projection(self.manifest["packets"][0])
        projection["rawLedgerPath"] = "/private/secret-ledger"
        projection["requests"][0]["authorization"] = "must-not-persist"
        persisted = _hard_budget_terminal_projection(projection)
        self.assertNotIn("rawLedgerPath", persisted)
        self.assertNotIn("authorization", persisted["requests"][0])
        _validate_row({**copy.deepcopy(self.rows[1]), "hardBudgetTerminalProjection": persisted})

        authority = _hard_budget_authority(self.manifest["packets"][0], self.manifest)
        authority["ledgerPath"] = "/private/authority-ledger"
        persisted_authority = _hard_budget_pre_dispatch_authority(authority)
        self.assertNotIn("ledgerPath", persisted_authority)
        _validate_row({**copy.deepcopy(self.rows[1]), "hardBudgetPreDispatchAuthority": persisted_authority})

    def test_pre_dispatch_authority_binds_terminal_cursor_and_serial_records(self) -> None:
        rows = copy.deepcopy(self.rows)
        terminal = _terminal(rows, "NAT-CTRL")
        terminal["hardBudgetPreDispatchAuthority"]["preDispatchNextSequence"] = 1
        with self.assertRaisesRegex(ReceiptError, "next sequence"):
            evaluate(self.manifest, rows)

        rows = copy.deepcopy(self.rows)
        terminal = _terminal(rows, "NAT-CTRL")
        terminal["hardBudgetTerminalProjection"]["ledgerRevision"] = 0
        with self.assertRaisesRegex(ReceiptError, "revision did not advance"):
            evaluate(self.manifest, rows)

        rows = copy.deepcopy(self.rows)
        terminal = _terminal(rows, "NAT-CTRL")
        terminal["hardBudgetPreDispatchAuthority"]["preDispatchNextSequence"] = 1
        terminal["hardBudgetTerminalProjection"]["nextSequence"] = 2
        with self.assertRaisesRegex(ReceiptError, "predates pre-dispatch cursor"):
            evaluate(self.manifest, rows)

        rows = copy.deepcopy(self.rows)
        terminal = _terminal(rows, "OAI-H-ORD3")
        requests = terminal["hardBudgetTerminalProjection"]["requests"]
        requests.append({
            **requests[0],
            "reservationID": "reservation-gap",
            "sequence": 99,
        })
        terminal["hardBudgetTerminalProjection"]["reservationCount"] = 2
        terminal["hardBudgetTerminalProjection"]["nextSequence"] = (
            terminal["hardBudgetPreDispatchAuthority"]["preDispatchNextSequence"] + 2
        )
        terminal["usage"]["modelCalls"] = 2
        terminal["usage"]["totalTokens"] = 4
        with self.assertRaisesRegex(ReceiptError, "sequence range is not contiguous"):
            evaluate(self.manifest, rows)

    def test_future_billable_source_requires_fresh_authority_per_packet(self) -> None:
        source = (ROOT / "run.py").read_text(encoding="utf-8")
        billable_v2 = source[source.index("def _billable_v2"):source.index("if __name__")]
        self.assertIn("convert them to fresh,", billable_v2)
        self.assertIn("cli_manifest_file=authority.cli_manifest", billable_v2)
        self.assertIn("budget_ledger_file=authority.ledger", billable_v2)
        self.assertNotIn("resume_saved_task()", billable_v2)
        self.assertIn("retain_campaign_authority", billable_v2)
        stop_recovery = billable_v2[billable_v2.index("except Exception as exc:"):]
        self.assertIn("wait_for_terminal_checkpoint(current_packet[\"marker\"]", stop_recovery)
        self.assertNotIn("wait_for_marker(current_packet[\"marker\"]", stop_recovery)

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
            "hardBudgetPreDispatchAuthority": _hard_budget_authority(packet, manifest),
            "hardBudgetTerminalProjection": _hard_budget_projection(packet),
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


def _hard_budget_authority(packet: dict, manifest: dict | None = None) -> dict:
    manifest = manifest or load_manifest(MANIFEST, run_id=RUN_ID)
    route = packet["hardBudget"]["route"]
    canonical = json.dumps(canonical_cli_manifest(manifest), sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {
        "campaignID": manifest["runId"],
        "manifestSHA256": hashlib.sha256(canonical).hexdigest(),
        "allocationID": packet["hardBudget"]["allocationID"],
        "packetID": packet["id"],
        "cliBuild": manifest["expectedCLIBuild"],
        "routeModel": route["model"],
        "endpointSHA256": route["endpointSha256"],
        "apiBackend": route["apiBackend"],
        "requestBoundTokens": route["requestBoundTokens"],
        "maxPayloadBytes": route["maxPayloadBytes"],
        "maxOutputTokens": route["maxOutputTokens"],
        "boundProvenanceSHA256": route["boundProvenanceSha256"],
        "preDispatchNextSequence": 0,
        "preDispatchLedgerRevision": 0,
    }


def _hard_budget_projection(packet: dict) -> dict:
    route = packet["hardBudget"]["route"]
    return {
        "status": "settled",
        "ledgerRevision": 1,
        "nextSequence": 1,
        "reservationCount": 1,
        "reason": None,
        "requests": [{
            "reservationID": f"reservation-{packet['id']}",
            "sequence": 0,
            "providerRequestID": f"provider-{packet['id']}",
            "model": route["model"],
            "endpointSHA256": route["endpointSha256"],
            "apiBackend": route["apiBackend"],
            "payloadBytes": 1,
            "maxOutputTokens": 1,
            "reservedTokens": 2,
            "actualTokens": 2,
            "chargedTokens": 2,
            "lifecycle": "settled_usage_reported",
        }],
    }


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
