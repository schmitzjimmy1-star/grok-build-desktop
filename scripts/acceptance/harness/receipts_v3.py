"""Evaluate Slice 4B.4 fresh-process continuation receipts.

Three allocations, one backend, one ledger. T2/T3 must be `session/load` of the
T1 backend after a fresh process. Stale `session/new` fallback, load-time
prompts, and cleanup before T3 all fail closed.
"""

from __future__ import annotations

import json
import os
import stat
from pathlib import Path
from typing import Any

from .errors import ReceiptError

LOAD_METHOD = "session/load"


def evaluate_fresh_process_continuation(
    packets: list[dict[str, Any]],
    rows: list[dict[str, Any]],
) -> dict[str, Any]:
    terminals = [row for row in rows if row.get("rowType") == "terminal"]
    cleanups = [row for row in rows if row.get("rowType") == "cleanup"]
    if len(terminals) != 3:
        raise ReceiptError("fresh-process continuation requires exactly three terminal receipts")
    ledgers = {row.get("campaignLedger") for row in terminals}
    if len(ledgers) != 1 or None in ledgers:
        raise ReceiptError("fresh-process continuation must charge one campaign ledger")
    tab = terminals[0]["tabId"]
    backend = terminals[0]["backendId"]
    epochs: set[int] = set()
    generations: set[int] = set()
    allocations: set[str] = set()
    for index, (packet, terminal) in enumerate(zip(packets, terminals), start=1):
        continuation = packet["continuation"]
        if terminal.get("packetId") != packet["id"]:
            raise ReceiptError(f"{packet['id']}: terminal packet identity drift")
        if terminal["tabId"] != tab or terminal["backendId"] != backend:
            raise ReceiptError(f"{packet['id']}: continuation tab/backend identity drift")
        if continuation["expectedLocalTab"] != tab:
            raise ReceiptError(f"{packet['id']}: loaded tab is not the retained tab")
        if terminal.get("loadMethod") != LOAD_METHOD:
            raise ReceiptError(f"{packet['id']}: loadMethod must be session/load")
        if terminal.get("sessionLoadStartedFreshFallback") is not False:
            raise ReceiptError(f"{packet['id']}: stale session/new fallback is refused")
        if terminal.get("loadTimePrompt") is not False:
            raise ReceiptError(f"{packet['id']}: session/load must not send a prompt")
        epoch = int(terminal["appLaunchEpoch"])
        generation = int(terminal["processGeneration"])
        allocation = str(terminal["allocationID"])
        if epoch in epochs or generation in generations or allocation in allocations:
            raise ReceiptError(f"{packet['id']}: reused launch epoch, process generation, or allocation")
        epochs.add(epoch)
        generations.add(generation)
        allocations.add(allocation)
        if index > 1 and terminal.get("outcome") != "loaded":
            raise ReceiptError(f"{packet['id']}: T2/T3 must load the retained backend")
        if index == 1 and terminal.get("outcome") not in {"new", "loaded"}:
            raise ReceiptError(f"{packet['id']}: T1 must create or first-bind the backend")
    if cleanups:
        if any(row.get("packetId") != packets[-1]["id"] for row in cleanups):
            raise ReceiptError("cleanup is refused until the continuation group ends")
        if any(row.get("cleanup", {}).get("localTab") == "retained" for row in cleanups):
            raise ReceiptError("group-end cleanup cannot retain the local tab")
    return {
        "outcome": "accepted",
        "tabId": tab,
        "backendId": backend,
        "allocationCount": 3,
        "ledgerCount": 1,
    }


def append_row(path: Path, row: dict[str, Any]) -> None:
    if not isinstance(row, dict) or row.get("rowType") not in {"terminal", "cleanup"}:
        raise ReceiptError("v3 ledger row must be a terminal or cleanup object")
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags, 0o600)
    except OSError as exc:
        raise ReceiptError("v3 ledger could not be opened without following links") from exc
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        os.close(fd)
        raise ReceiptError("v3 ledger must be an owner-only regular file")
    with os.fdopen(fd, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")


def load_ledger(path: Path) -> list[dict[str, Any]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ReceiptError("v3 ledger is unreadable") from exc
    rows: list[dict[str, Any]] = []
    for line in lines:
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ReceiptError("v3 ledger row is unreadable") from exc
        if not isinstance(row, dict):
            raise ReceiptError("v3 ledger row must be an object")
        rows.append(row)
    return rows
