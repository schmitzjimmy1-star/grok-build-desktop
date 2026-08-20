"""Private 4C campaign authority. campaignId is a product id, never runId.

Live bind hashes are filled at arm time from the candidate plus frozen
endpointIdentity. They are never copied from the 4M v2 fixture. The
committed 4C matrix still freezes models, routes, allocations, and
unconfirmed prices only. Native packets use sha256(b"nativeXAI") rather
than inventing an xAI host. Native Keychain selectors stay null; Swift
schema-3 isValid still rejects that mixed matrix until the step-5 leftover.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
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

NATIVE_ENDPOINT_FREEZE_SHA256 = hashlib.sha256(b"nativeXAI").hexdigest()
SHA256_HEX = re.compile(r"^[0-9a-f]{64}$")

__all__ = [
    "CampaignAuthority",
    "NATIVE_ENDPOINT_FREEZE_SHA256",
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
            _canonical_json(
                swift_authorization_sidecar(
                    manifest,
                    cli_manifest,
                    ledger,
                    provenance_sha256=candidate.provenance_sha256,
                )
            ),
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
    provenance = None if candidate is None else _require_sha256(
        candidate.provenance_sha256, "candidate provenance"
    )
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
                "route": _cli_route(packet, provenance_sha256=provenance),
            }
            for packet in manifest["packets"]
        ],
    }
    if candidate is not None:
        payload["candidateExpectation"]["binarySha256"] = candidate.binary_sha256
    return payload


def swift_authorization_sidecar(
    manifest: dict[str, Any],
    cli_manifest: Path,
    ledger: Path,
    *,
    provenance_sha256: str,
) -> dict[str, Any]:
    del ledger  # Path is retained next to the sidecar; Swift reads it from argv.
    digest = hashlib.sha256(cli_manifest.read_bytes()).hexdigest()
    campaign_id = manifest["campaignId"]
    run_id = manifest["runId"]
    if campaign_id == run_id:
        raise HarnessError("4C Swift sidecar campaignId must not equal runId")
    provenance = _require_sha256(provenance_sha256, "sidecar provenance")
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
                "route": _swift_route(packet, provenance_sha256=provenance),
            }
            for packet in manifest["packets"]
        ],
    }


def _cli_route(packet: dict[str, Any], *, provenance_sha256: str | None) -> dict[str, Any]:
    hard = packet["hardBudget"]["route"]
    route: dict[str, Any] = {
        "model": hard["model"],
        "apiBackend": hard["apiBackend"],
        "requestBoundTokens": hard["requestBoundTokens"],
        "maxPayloadBytes": hard["maxPayloadBytes"],
        "maxOutputTokens": hard["maxOutputTokens"],
    }
    if provenance_sha256 is not None:
        route["endpointSha256"] = _endpoint_sha256(packet)
        route["boundProvenanceSha256"] = provenance_sha256
    return route


def _swift_route(packet: dict[str, Any], *, provenance_sha256: str) -> dict[str, Any]:
    hard = packet["hardBudget"]["route"]
    return {
        "model": hard["model"],
        "endpointSHA256": _endpoint_sha256(packet),
        "apiBackend": hard["apiBackend"],
        "requestBoundTokens": hard["requestBoundTokens"],
        "maxPayloadBytes": hard["maxPayloadBytes"],
        "maxOutputTokens": hard["maxOutputTokens"],
        "boundProvenanceSHA256": provenance_sha256,
        "managedProviderID": packet["routeReceipt"]["officialProviderID"],
        "authScheme": _auth_scheme(packet),
    }


def _endpoint_sha256(packet: dict[str, Any]) -> str:
    packet_id = packet["id"]
    kind = packet["routeReceipt"]["kind"]
    if kind == "nativeXAI":
        if packet["routeReceipt"].get("endpointIdentity") is not None:
            raise HarnessError(f"{packet_id}: native 4C must not invent an xAI host")
        return NATIVE_ENDPOINT_FREEZE_SHA256
    identity = packet["routeReceipt"].get("endpointIdentity")
    if not isinstance(identity, str) or not identity.strip():
        raise HarnessError(f"{packet_id}: provider packet needs endpointIdentity to bind")
    return hashlib.sha256(identity.encode("utf-8")).hexdigest()


def _require_sha256(value: str, where: str) -> str:
    if not isinstance(value, str) or SHA256_HEX.fullmatch(value) is None:
        raise HarnessError(f"{where} must be a 64-hex digest")
    return value


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
