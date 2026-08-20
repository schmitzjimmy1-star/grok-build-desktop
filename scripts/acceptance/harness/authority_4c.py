"""Private 4C campaign authority. campaignId is a product id, never runId.

Live bind hashes are not copied from the 4M v2 fixture. The committed 4C
matrix freezes models, routes, allocations, and unconfirmed prices only.
"""

from __future__ import annotations

import hashlib
import json
import os
import stat
import tempfile
from pathlib import Path
from typing import Any

from .authority_v2 import CampaignAuthority, retain_campaign_authority
from .candidate_runtime import SignatureProbe, validate_runtime_selection
from .errors import HarnessError
from .schema_4c import (
    CAMPAIGN_CEILING,
    EMERGENCY_RESERVE,
    EXPECTED_CLI_BUILD,
    FROZEN_CAMPAIGN_ID,
    PLANNED_MAXIMUM,
    STAGED_SOURCE_SHA,
)

__all__ = [
    "CampaignAuthority",
    "canonical_cli_manifest",
    "prepare_campaign_authority",
    "retain_campaign_authority",
    "swift_authorization_sidecar",
]


def prepare_campaign_authority(
    manifest: dict[str, Any],
    *,
    candidate_selection: Path,
    root: Path | None = None,
    signature_probe: SignatureProbe | None = None,
) -> CampaignAuthority:
    """Create the Rust sampler authority and Swift sidecar without launching anything."""
    if manifest.get("campaignId") != FROZEN_CAMPAIGN_ID:
        raise HarnessError("4C authority refuses a non-frozen campaignId")
    if manifest.get("expectedCLIBuild") != EXPECTED_CLI_BUILD:
        raise HarnessError("4C authority requires expectedCLIBuild 1.0.5 (8226242)")
    base = root or Path(tempfile.gettempdir())
    directory = Path(tempfile.mkdtemp(prefix="grokbuild-s4c-", dir=base))
    os.chmod(directory, 0o700)
    try:
        candidate = validate_runtime_selection(
            candidate_selection,
            expected_cli_build=EXPECTED_CLI_BUILD,
            signature_probe=signature_probe,
        )
        runtime_selection = directory / "runtime-selection.json"
        _write_private_exclusive(runtime_selection, _canonical_json(candidate.document))
        cli_payload = canonical_cli_manifest(manifest, candidate=candidate)
        cli_manifest = directory / "hard-token-campaign.json"
        _write_private_exclusive(cli_manifest, _canonical_json(cli_payload))
        ledger = directory / "hard-token-ledger.json"
        _write_private_exclusive(ledger, b"")
        authorization = directory / "acceptance-budget.json"
        _write_private_exclusive(
            authorization,
            _canonical_json(swift_authorization_sidecar(manifest, cli_manifest, ledger)),
        )
        return CampaignAuthority(directory, cli_manifest, ledger, authorization, runtime_selection, candidate)
    except Exception:
        for path in directory.iterdir():
            path.unlink(missing_ok=True)
        directory.rmdir()
        raise


def canonical_cli_manifest(manifest: dict[str, Any], *, candidate: Any | None = None) -> dict[str, Any]:
    campaign_id = manifest["campaignId"]
    if campaign_id != FROZEN_CAMPAIGN_ID:
        raise HarnessError("4C CLI hard-budget campaignId must be slice4c-bounded-paid")
    if campaign_id == manifest.get("runId"):
        raise HarnessError("4C CLI hard-budget campaignId must not equal runId")
    payload: dict[str, Any] = {
        "schemaVersion": 3,
        "campaignId": campaign_id,
        "campaignPolicy": {
            "schemaVersion": 3,
            "absoluteTokenCeiling": CAMPAIGN_CEILING,
            "allocatableTokenCeiling": PLANNED_MAXIMUM,
            "unreachableReserveTokens": EMERGENCY_RESERVE,
        },
        "candidateExpectation": {
            "cliBuild": EXPECTED_CLI_BUILD,
            "sourceCommitSha": STAGED_SOURCE_SHA,
        },
        "allocations": [
            {
                "id": packet["hardBudget"]["allocationID"],
                "packetId": packet["id"],
                "promptSha256": packet["promptHash"],
                "tokenCeiling": packet["tokenAllocation"],
                "maxModelCalls": packet["maxModelCalls"],
                "route": {
                    "model": packet["hardBudget"]["route"]["model"],
                    "apiBackend": packet["hardBudget"]["route"]["apiBackend"],
                    "requestBoundTokens": packet["hardBudget"]["route"]["requestBoundTokens"],
                    "maxPayloadBytes": packet["hardBudget"]["route"]["maxPayloadBytes"],
                    "maxOutputTokens": packet["hardBudget"]["route"]["maxOutputTokens"],
                },
            }
            for packet in manifest["packets"]
        ],
    }
    if candidate is not None:
        payload["candidateExpectation"]["binarySha256"] = candidate.binary_sha256
    return payload


def swift_authorization_sidecar(manifest: dict[str, Any], cli_manifest: Path, ledger: Path) -> dict[str, Any]:
    del ledger  # Path is retained next to the sidecar; Swift reads it from argv.
    digest = hashlib.sha256(cli_manifest.read_bytes()).hexdigest()
    campaign_id = manifest["campaignId"]
    run_id = manifest["runId"]
    if campaign_id == run_id:
        raise HarnessError("4C Swift sidecar campaignId must not equal runId")
    return {
        "schemaVersion": 3,
        "runID": run_id,
        "campaignId": campaign_id,
        "campaignTokenCeiling": CAMPAIGN_CEILING,
        "emergencyReserveTokens": EMERGENCY_RESERVE,
        "hardBudgetManifestSHA256": digest,
        "expectedCLIBuild": EXPECTED_CLI_BUILD,
        "packets": [
            {
                "packetID": packet["id"],
                "allocationID": packet["hardBudget"]["allocationID"],
                "marker": packet["marker"],
                "promptHash": packet["promptHash"],
                "tokenAllocation": packet["tokenAllocation"],
                "maxModelCalls": packet["maxModelCalls"],
                "route": {
                    "model": packet["hardBudget"]["route"]["model"],
                    "apiBackend": packet["hardBudget"]["route"]["apiBackend"],
                    "requestBoundTokens": packet["hardBudget"]["route"]["requestBoundTokens"],
                    "maxPayloadBytes": packet["hardBudget"]["route"]["maxPayloadBytes"],
                    "maxOutputTokens": packet["hardBudget"]["route"]["maxOutputTokens"],
                    "managedProviderID": packet["routeReceipt"]["officialProviderID"],
                    "authScheme": _auth_scheme(packet),
                },
            }
            for packet in manifest["packets"]
        ],
    }


def _auth_scheme(packet: dict[str, Any]) -> str | None:
    if packet["routeReceipt"]["kind"] == "nativeXAI":
        return None
    return "bearer"


def _canonical_json(value: dict[str, Any]) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _write_private_exclusive(path: Path, payload: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags, 0o600)
    except OSError as exc:
        raise HarnessError("campaign authority path must not pre-exist or follow a link") from exc
    with os.fdopen(fd, "wb") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    if stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise HarnessError("campaign authority file must be private")
