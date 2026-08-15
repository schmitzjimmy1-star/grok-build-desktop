"""Fixture-mode runner: expected accept/reject at zero provider cost."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .cleanup import require_exact_ids
from .errors import HarnessError
from .handoff import HandoffContext, render_handoff, validate_handoff
from .receipts import evaluate, load_ledger
from .redaction import safe_print
from .schema import dry_run_plan, load_manifest


def run_fixture(directory: Path) -> int:
    case_path = directory / "case.json"
    case = json.loads(case_path.read_text(encoding="utf-8"))
    kind = case["kind"]
    expect = case["expect"]
    reason = case.get("reason")
    error: HarnessError | None = None
    detail = ""
    try:
        if kind in {"manifest", "dry-run", "happy"}:
            manifest = load_manifest(_manifest_path(directory, case))
            if kind in {"dry-run", "happy"}:
                plan = dry_run_plan(manifest)
                safe_print(json.dumps({"mode": "dry-run", "runId": plan["runId"], "packets": len(plan["packets"])}))
            if kind == "happy":
                receipts = load_ledger(directory / "ledger.jsonl")
                evaluate(manifest, receipts)
                handoff = render_handoff(_handoff_from_case(case, manifest, receipts))
                safe_print(handoff)
        elif kind == "evaluate":
            manifest = load_manifest(_manifest_path(directory, case))
            receipts = load_ledger(directory / "ledger.jsonl")
            evaluate(manifest, receipts)
        elif kind == "cleanup":
            receipts = load_ledger(directory / "ledger.jsonl")
            request = json.loads((directory / "cleanup-request.json").read_text(encoding="utf-8"))
            require_exact_ids(
                receipts,
                request.get("ids"),
                guessed=bool(request.get("guessed")),
            )
        elif kind == "handoff":
            validate_handoff((directory / "handoff.txt").read_text(encoding="utf-8"))
        else:
            raise HarnessError(f"unknown fixture kind {kind}")
    except HarnessError as exc:
        error = exc
        detail = str(exc)

    actual = "reject" if error else "accept"
    if actual != expect:
        safe_print(f"fixture {directory.name}: expected {expect}, got {actual}: {detail}")
        return 1
    if expect == "reject":
        if reason and reason not in detail:
            safe_print(f"fixture {directory.name}: expected reason {reason!r}, got {detail!r}")
            return 1
        safe_print(f"fixture {directory.name}: rejected as expected ({detail})")
        return 0
    safe_print(f"fixture {directory.name}: accepted")
    return 0


def _manifest_path(directory: Path, case: dict[str, Any]) -> Path:
    name = case.get("manifest", "manifest.json")
    return directory / name


def _handoff_from_case(
    case: dict[str, Any],
    manifest: dict[str, Any],
    receipts: list[dict[str, Any]],
) -> HandoffContext:
    threads = ",".join(row["tabId"] for row in receipts) or "none"
    return HandoffContext(
        repo=case.get("repo", "/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop"),
        branch=case.get("branch", "codex/grokbuild-s5-acceptance-harness"),
        commit=case.get("commit", "fixture"),
        slice="5",
        checkpoint=case.get("checkpoint", "fixture"),
        result=case.get("result", "passed"),
        live_state=case.get("liveState", "fixture-mode process-zero"),
        usage="none",
        thread_ids=threads,
        cleanup="none",
        risk="none",
        next_action=case.get("nextAction", "installed three-route billable manifest after signed ship"),
        hard_stop=case.get(
            "hardStop",
            "Slice 6, Slice 7, releases, tags, origin, force-push, branch deletion, and configuration changes",
        ),
    )
