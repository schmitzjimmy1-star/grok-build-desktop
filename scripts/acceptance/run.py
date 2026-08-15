#!/usr/bin/env python3
"""GrokBuild agentic acceptance harness.

Dry-run is the default. Pass --billable for fresh provider Sends after preflight.
Never prints credentials or response bodies. Never fakes ACP or guesses cleanup IDs.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from harness.cleanup import require_exact_ids
from harness.driver import (
    capture_identities,
    launch_installed,
    new_chat,
    quit_installed,
    restore_continuation,
    resume_saved_task,
    select_model,
    send_prompt,
    stop_turn,
    wait_for_marker,
    wait_for_stop_control,
)
from harness.errors import HarnessError
from harness.evidence import extract_receipt
from harness.fixture import run_fixture
from harness.handoff import HandoffContext, render_handoff, validate_handoff
from harness.preflight import preflight, two_process_zero_samples
from harness.receipts import evaluate, load_ledger
from harness.redaction import redact_value, safe_print
from harness.schema import dry_run_plan, load_manifest, require_live_run_id

DEFAULT_MANIFEST = ROOT / "manifests" / "installed-three-route-v1.json"
DEFAULT_LEDGER = Path("/tmp/grokbuild-s5-ledger.jsonl")
REPO = Path("/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop")
TRANSCRIPTS = Path.home() / "Library/Application Support/GrokBuild/Transcripts"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="GrokBuild agentic acceptance harness")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--billable", action="store_true", help="Allow fresh provider Sends after preflight")
    parser.add_argument("--run-id", dest="run_id")
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
    parser.add_argument("--cleanup", action="store_true")
    parser.add_argument("--ids-from-ledger", type=Path)
    parser.add_argument("--guessed-id", help=argparse.SUPPRESS)
    parser.add_argument("--check-handoff", type=Path)
    parser.add_argument("--evaluate-ledger", action="store_true")
    args = parser.parse_args(argv)

    try:
        if args.fixture:
            return run_fixture(args.fixture)
        if args.check_handoff:
            validate_handoff(args.check_handoff.read_text(encoding="utf-8"))
            safe_print("handoff accepted")
            return 0
        if args.cleanup:
            return _cleanup(args)
        if args.evaluate_ledger:
            manifest = load_manifest(args.manifest, run_id=args.run_id)
            receipts = load_ledger(args.ledger)
            summary = evaluate(manifest, receipts)
            safe_print(json.dumps(redact_value("summary", summary)))
            return 0
        if args.billable:
            return _billable(args)
        manifest = load_manifest(args.manifest, run_id=args.run_id)
        plan = dry_run_plan(manifest)
        safe_print(json.dumps(redact_value("plan", plan), indent=2))
        return 0
    except HarnessError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


def _cleanup(args: argparse.Namespace) -> int:
    if args.ids_from_ledger is None:
        require_exact_ids([], None, guessed=False)
    receipts = load_ledger(args.ids_from_ledger)
    ids = require_exact_ids(receipts, _ids_from_receipts(receipts), guessed=bool(args.guessed_id))
    safe_print(json.dumps({"cleanupIdentities": ids, "executed": False}))
    safe_print("cleanup IDs verified from ledger; installed Close Session still required for tabs")
    return 0


def _ids_from_receipts(receipts: list[dict]) -> list[str]:
    ids: list[str] = []
    for row in receipts:
        for key in ("tabId", "backendId"):
            value = str(row.get(key) or "").strip()
            if value:
                ids.append(value)
        ids.extend(str(item) for item in row.get("childIds") or [] if item)
    return ids


def _billable(args: argparse.Namespace) -> int:
    if not args.run_id:
        raise HarnessError("billable mode requires --run-id")
    require_live_run_id(args.run_id)
    manifest = load_manifest(args.manifest, run_id=args.run_id)
    report = preflight(REPO, manifest, ledger=args.ledger)
    safe_print(json.dumps({"preflight": redact_value("preflight", report)}))
    launch_installed()
    receipts: list[dict] = []
    cumulative = 0
    try:
        packets = manifest["packets"]
        for index, packet in enumerate(packets):
            ceiling = int(manifest["anomalyCeilingActualTokens"])
            if cumulative >= ceiling:
                raise HarnessError(
                    f"ceiling breach: cumulative actual tokens {cumulative} exceed {ceiling}"
                )
            continuation = packet["continuation"]
            start_new = continuation is None or int(continuation["turn"]) == 1
            if start_new:
                new_chat()
                select_model(packet["model"])
            elif continuation and continuation.get("resumeAfterQuit"):
                restore_continuation(marker=receipts[-1]["marker"])
                resume_saved_task()
            send_prompt(packet["prompt"])
            if packet.get("deliberateStop"):
                wait_for_stop_control(timeout_seconds=60)
                time.sleep(2)
                stop_turn()
            else:
                timeout = 480 if packet["childTopology"] else 300
                wait_for_marker(packet["marker"], timeout_seconds=timeout)
            identities = capture_identities(REPO, packet["marker"])
            receipt = extract_receipt(packet, identities, TRANSCRIPTS)
            if packet.get("deliberateStop"):
                receipt["outcome"] = "stopped"
            receipts.append(receipt)
            cumulative += int(receipt["tokenSplit"]["total"])
            _append_ledger(args.ledger, receipt)
            nxt = packets[index + 1] if index + 1 < len(packets) else None
            nxt_continuation = (nxt or {}).get("continuation") or {}
            if nxt_continuation.get("resumeAfterQuit"):
                quit_installed()
                two_process_zero_samples()
                launch_installed()
        summary = evaluate(manifest, receipts)
        slice_id = "6" if int(manifest["anomalyCeilingActualTokens"]) == 250000 else "5"
        if slice_id == "6":
            live_state = "installed GrokBuild after Slice 6 extraction packet"
            next_action = "exact Slice 6 cleanup then merged-main closeout"
            hard_stop = "Slice 7, releases, tags, origin, force-push, branch deletion, and configuration changes"
            checkpoint = "signed-installed Slice 6 acceptance"
        else:
            live_state = "installed GrokBuild after three-route manifest"
            next_action = "exact Slice 5 cleanup then personal PR merge"
            hard_stop = "Slice 6 until merged-main closeout, Slice 7, releases, tags, origin, force-push, branch deletion, and configuration changes"
            checkpoint = "signed-installed acceptance"
        handoff = render_handoff(
            HandoffContext(
                repo=str(REPO),
                branch="main",
                commit=report["identity"]["head"],
                slice=slice_id,
                checkpoint=checkpoint,
                result="completed",
                live_state=live_state,
                usage=str(summary["actualTokens"]),
                thread_ids=",".join(row["tabId"] for row in receipts),
                cleanup="none",
                risk="none",
                next_action=next_action,
                hard_stop=hard_stop,
            )
        )
        safe_print(handoff)
        return 0
    except HarnessError:
        if receipts:
            _write_ledger(args.ledger, receipts)
        raise


def _append_ledger(path: Path, row: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(redact_value("row", row), separators=(",", ":")) + "\n")


def _write_ledger(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(redact_value("row", row), separators=(",", ":")) + "\n")


if __name__ == "__main__":
    sys.exit(main())
