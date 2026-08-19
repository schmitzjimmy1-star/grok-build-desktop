from __future__ import annotations

import copy
import inspect
import unittest

from scripts.acceptance.harness.driver import governed_fresh_process_load, resume_saved_task
from scripts.acceptance.harness.errors import DriverError, ReceiptError, SchemaError
from scripts.acceptance.harness.receipts_v3 import evaluate_fresh_process_continuation
from scripts.acceptance.harness.schema_v3 import validate_fresh_process_continuation


def _packet(turn: int, **overrides: object) -> dict:
    predecessor = None if turn == 1 else f"CONT-T{turn - 1}"
    digest = None if turn == 1 else "a" * 64
    packet = {
        "id": f"CONT-T{turn}",
        "allocationID": f"alloc-{turn}",
        "continuation": {
            "group": "S4B4-CONT",
            "turn": turn,
            "of": 3,
            "predecessorPacketID": predecessor,
            "predecessorBackendDigest": digest,
            "expectedLocalTab": "tab-retained",
            "freshAppLaunchEpoch": True,
            "freshProcessGeneration": True,
            "freshAllocation": True,
            "sharedCampaignManifest": True,
            "sharedCampaignLedger": True,
            "loadMethod": "session/load",
        },
    }
    packet.update(overrides)
    return packet


def _terminal(turn: int, **overrides: object) -> dict:
    row = {
        "rowType": "terminal",
        "packetId": f"CONT-T{turn}",
        "tabId": "tab-retained",
        "backendId": "backend-1",
        "appLaunchEpoch": turn,
        "processGeneration": 100 + turn,
        "allocationID": f"alloc-{turn}",
        "campaignLedger": "ledger-1",
        "loadMethod": "session/load",
        "sessionLoadStartedFreshFallback": False,
        "loadTimePrompt": False,
        "outcome": "new" if turn == 1 else "loaded",
    }
    row.update(overrides)
    return row


class Slice4B4FreshProcessContinuationContracts(unittest.TestCase):
    def test_valid_three_turn_group_is_accepted(self) -> None:
        packets = [_packet(1), _packet(2), _packet(3)]
        validate_fresh_process_continuation(packets)
        result = evaluate_fresh_process_continuation(packets, [_terminal(1), _terminal(2), _terminal(3)])
        self.assertEqual(result["outcome"], "accepted")
        self.assertEqual(result["allocationCount"], 3)
        self.assertEqual(result["ledgerCount"], 1)

    def test_resume_after_quit_is_rejected_at_schema(self) -> None:
        packets = [_packet(1), _packet(2), _packet(3)]
        packets[1]["continuation"]["resumeAfterQuit"] = True
        with self.assertRaisesRegex(SchemaError, "resumeAfterQuit is rejected"):
            validate_fresh_process_continuation(packets)

    def test_session_resume_and_resume_saved_task_are_rejected(self) -> None:
        for method in ("session/resume", "resume_saved_task"):
            packets = [_packet(1), _packet(2), _packet(3)]
            packets[1]["continuation"]["loadMethod"] = method
            with self.assertRaisesRegex(SchemaError, "rejected"):
                validate_fresh_process_continuation(packets)

    def test_shared_allocation_or_tab_drift_is_rejected(self) -> None:
        packets = [_packet(1), _packet(2), _packet(3)]
        packets[2]["allocationID"] = "alloc-1"
        with self.assertRaisesRegex(SchemaError, "each turn needs its own allocation"):
            validate_fresh_process_continuation(packets)
        packets = [_packet(1), _packet(2), _packet(3)]
        packets[2]["continuation"]["expectedLocalTab"] = "tab-other"
        with self.assertRaisesRegex(SchemaError, "retained tab"):
            validate_fresh_process_continuation(packets)

    def test_stale_fallback_load_prompt_and_early_cleanup_are_rejected(self) -> None:
        packets = [_packet(1), _packet(2), _packet(3)]
        rows = [_terminal(1), _terminal(2, sessionLoadStartedFreshFallback=True), _terminal(3)]
        with self.assertRaisesRegex(ReceiptError, "stale session/new fallback"):
            evaluate_fresh_process_continuation(packets, rows)
        rows = [_terminal(1), _terminal(2, loadTimePrompt=True), _terminal(3)]
        with self.assertRaisesRegex(ReceiptError, "must not send a prompt"):
            evaluate_fresh_process_continuation(packets, rows)
        rows = [_terminal(1), _terminal(2), _terminal(3)]
        rows.append({"rowType": "cleanup", "packetId": "CONT-T2", "cleanup": {"localTab": "closedExact"}})
        with self.assertRaisesRegex(ReceiptError, "until the continuation group ends"):
            evaluate_fresh_process_continuation(packets, rows)

    def test_reused_generation_or_backend_drift_is_rejected(self) -> None:
        packets = [_packet(1), _packet(2), _packet(3)]
        with self.assertRaisesRegex(ReceiptError, "reused launch epoch"):
            evaluate_fresh_process_continuation(
                packets,
                [_terminal(1), _terminal(2, processGeneration=101), _terminal(3)],
            )
        with self.assertRaisesRegex(ReceiptError, "tab/backend identity drift"):
            evaluate_fresh_process_continuation(
                packets,
                [_terminal(1), _terminal(2, backendId="backend-2"), _terminal(3)],
            )

    def test_governed_load_driver_never_calls_resume_saved_task(self) -> None:
        source = inspect.getsource(governed_fresh_process_load)
        self.assertNotIn("resume_saved_task", source)
        self.assertNotIn("Resume current task", source)
        self.assertNotIn("not live-wired yet", source)
        self.assertIn("session/load", source)
        with self.assertRaises(DriverError):
            governed_fresh_process_load(expected_tab="", expected_backend="backend-1")
        with self.assertRaises(DriverError):
            governed_fresh_process_load(expected_tab="tab-retained", expected_backend="backend-1")
        self.assertIn("def resume_saved_task", inspect.getsource(resume_saved_task))
