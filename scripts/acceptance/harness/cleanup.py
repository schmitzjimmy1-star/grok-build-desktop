"""Exact-ID cleanup. Refuse guessed, missing, or non-ledger identities."""

from __future__ import annotations

from typing import Any, Iterable

from .errors import CleanupError


def ledger_identities(receipts: list[dict[str, Any]]) -> set[str]:
    identities: set[str] = set()
    for row in receipts:
        for key in ("tabId", "backendId"):
            value = str(row.get(key) or "").strip()
            if value:
                identities.add(value)
        for child in row.get("childIds") or []:
            child_id = str(child).strip()
            if child_id:
                identities.add(child_id)
        for worker in row.get("workerReceipts") or []:
            child_id = str(worker.get("childId") or "").strip()
            if child_id:
                identities.add(child_id)
    return identities


def require_exact_ids(
    receipts: list[dict[str, Any]],
    requested: Iterable[str] | None,
    *,
    guessed: bool = False,
) -> list[str]:
    if guessed:
        raise CleanupError("incorrect cleanup: refuse guessed cleanup IDs")
    if requested is None:
        raise CleanupError("incorrect cleanup: cleanup requires --ids-from-ledger")
    wanted = [item.strip() for item in requested if str(item).strip()]
    if not wanted:
        raise CleanupError("incorrect cleanup: no exact IDs in the ledger")
    known = ledger_identities(receipts)
    if not known:
        raise CleanupError("incorrect cleanup: ledger has no cleanup identities")
    unknown = [item for item in wanted if item not in known]
    if unknown:
        raise CleanupError(
            f"incorrect cleanup: IDs are not in the ledger: {unknown}"
        )
    return wanted
