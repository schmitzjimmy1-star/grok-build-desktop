"""Private, non-executing authority files for the dormant Slice 4 paid lane."""

from __future__ import annotations

import hashlib
import json
import os
import stat
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .errors import HarnessError
from .candidate_runtime import CandidateRuntimeSelection, SignatureProbe, validate_runtime_selection


@dataclass(frozen=True)
class CampaignAuthority:
    directory: Path
    cli_manifest: Path
    ledger: Path
    authorization: Path
    runtime_selection: Path
    candidate: CandidateRuntimeSelection


def retain_campaign_authority(
    authority: CampaignAuthority,
    *,
    process_zero_samples: list[dict[str, Any]] | None,
) -> dict[str, Any]:
    """Retain sampler spend evidence; only retire the app-only sidecar after process-zero."""
    process_zero_confirmed = _valid_process_zero_samples(process_zero_samples)
    retirement_safe = process_zero_confirmed and all(
        _private_single_link(path) for path in (authority.authorization, authority.runtime_selection)
    )
    if retirement_safe:
        authority.authorization.unlink(missing_ok=True)
        authority.runtime_selection.unlink(missing_ok=True)
    return {
        "authorityDirectory": str(authority.directory),
        "cliManifestSHA256": hashlib.sha256(authority.cli_manifest.read_bytes()).hexdigest(),
        "ledgerSHA256": hashlib.sha256(authority.ledger.read_bytes()).hexdigest(),
        "cliManifestRetained": authority.cli_manifest.exists(),
        "ledgerRetained": authority.ledger.exists(),
        "candidateBinarySHA256": authority.candidate.binary_sha256,
        "candidateProvenanceSHA256": authority.candidate.provenance_sha256,
        "authorizationSidecarRemoved": retirement_safe and not authority.authorization.exists(),
        "runtimeSelectionRemoved": retirement_safe and not authority.runtime_selection.exists(),
        "processZeroSamples": process_zero_samples if process_zero_confirmed else None,
        "retirementRefused": process_zero_confirmed and not retirement_safe,
    }


def _valid_process_zero_samples(samples: list[dict[str, Any]] | None) -> bool:
    if not isinstance(samples, list) or len(samples) != 2:
        return False
    for sample in samples:
        if not isinstance(sample, dict) or not isinstance(sample.get("at"), str):
            return False
        pids = sample.get("pids")
        if not isinstance(pids, dict) or not pids:
            return False
        if any(not isinstance(values, list) or values for values in pids.values()):
            return False
    return True


def _private_single_link(path: Path) -> bool:
    try:
        metadata = path.lstat()
    except OSError:
        return False
    return (
        stat.S_ISREG(metadata.st_mode)
        and metadata.st_uid == os.getuid()
        and stat.S_IMODE(metadata.st_mode) & 0o077 == 0
        and metadata.st_nlink == 1
    )


def prepare_campaign_authority(
    manifest: dict[str, Any],
    *,
    candidate_selection: Path,
    root: Path | None = None,
    signature_probe: SignatureProbe | None = None,
) -> CampaignAuthority:
    """Create the Rust sampler authority and Swift sidecar without launching anything."""
    base = root or Path(tempfile.gettempdir())
    directory = Path(tempfile.mkdtemp(prefix="grokbuild-s4-", dir=base))
    os.chmod(directory, 0o700)
    try:
        candidate = validate_runtime_selection(
            candidate_selection,
            expected_cli_build=manifest["expectedCLIBuild"],
            signature_probe=signature_probe,
        )
        runtime_selection = directory / "runtime-selection.json"
        _write_private_exclusive(runtime_selection, _canonical_json(candidate.document))
        cli_payload = canonical_cli_manifest(manifest)
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


def canonical_cli_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    return {
        "version": 1,
        "campaignId": manifest["runId"],
        "ceilingTokens": manifest["plannedTokenMaximum"],
        "allocations": [
            {
                "id": packet["hardBudget"]["allocationID"],
                "packetId": packet["id"],
                "promptSha256": packet["promptHash"],
                "tokenCeiling": packet["tokenAllocation"],
                "maxModelCalls": packet["maxModelCalls"],
                "route": packet["hardBudget"]["route"],
            }
            for packet in manifest["packets"]
        ],
    }


def swift_authorization_sidecar(manifest: dict[str, Any], cli_manifest: Path, ledger: Path) -> dict[str, Any]:
    digest = hashlib.sha256(cli_manifest.read_bytes()).hexdigest()
    return {
        "schemaVersion": 2,
        "runID": manifest["runId"],
        "campaignTokenCeiling": manifest["campaignTokenCeiling"],
        "emergencyReserveTokens": manifest["emergencyReserveTokens"],
        "hardBudgetManifestSHA256": digest,
        "expectedCLIBuild": manifest["expectedCLIBuild"],
        "packets": [
            {
                "packetID": packet["id"],
                "allocationID": packet["hardBudget"]["allocationID"],
                "marker": packet["marker"],
                "promptHash": packet["promptHash"],
                "tokenAllocation": packet["tokenAllocation"],
                "maxModelCalls": packet["maxModelCalls"],
                "route": packet["hardBudget"]["route"],
            }
            for packet in manifest["packets"]
        ],
    }


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
