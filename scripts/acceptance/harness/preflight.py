"""Live preflight before any --billable Send. Fixture mode never calls this."""

from __future__ import annotations

import hashlib
import os
import subprocess
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote

from .errors import PreflightError

APP = Path("/Applications/GrokBuild.app")
DIST = Path("dist/GrokBuild.app")
TEAM = "DD2GCQJVB4"
OWNED = ("GrokBuild", "grok", "GrokBuildComputerUseMCP", "agent-desktop")


def _run(args: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
    )


def _pgrep(name: str) -> list[str]:
    result = _run(["pgrep", "-x", name])
    if result.returncode not in (0, 1):
        raise PreflightError(f"pgrep {name} failed")
    return [line for line in result.stdout.splitlines() if line.strip()]


def process_zero_sample() -> dict[str, Any]:
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    pids = {name: _pgrep(name) for name in OWNED}
    leftover = {name: values for name, values in pids.items() if values}
    if leftover:
        raise PreflightError(f"process-zero failed at {stamp}: {leftover}")
    return {"at": stamp, "pids": pids}


def two_process_zero_samples(*, delay_seconds: float = 5.0) -> list[dict[str, Any]]:
    first = process_zero_sample()
    time.sleep(delay_seconds)
    second = process_zero_sample()
    return [first, second]


def _plist(key: str) -> str:
    result = _run(["plutil", "-extract", key, "raw", str(APP / "Contents/Info.plist")])
    if result.returncode != 0:
        raise PreflightError(f"missing Info.plist key {key}")
    return result.stdout.strip()


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def installed_identity(repo: Path) -> dict[str, Any]:
    if not APP.exists():
        raise PreflightError("installed app is missing")
    head = _run(["git", "rev-parse", "HEAD"], cwd=repo)
    if head.returncode != 0:
        raise PreflightError("cannot read HEAD")
    head_sha = head.stdout.strip()
    stamp = _plist("GrokBuildSourceCommit")
    dirty = _plist("GrokBuildSourceDirty")
    branch = _plist("GrokBuildSourceBranch")
    repository = _plist("GrokBuildSourceRepository")
    dist_exec = repo / DIST / "Contents/MacOS/GrokBuild"
    inst_exec = APP / "Contents/MacOS/GrokBuild"
    if not dist_exec.exists() or not inst_exec.exists():
        raise PreflightError("dist or installed executable is missing")
    dist_sha = _sha256(dist_exec)
    inst_sha = _sha256(inst_exec)
    if stamp != head_sha:
        raise PreflightError(f"installed stamp {stamp} != HEAD {head_sha}")
    if dist_sha != inst_sha:
        raise PreflightError("dist/installed executable hash mismatch")
    verify = _run(["codesign", "--verify", "--deep", "--strict", str(APP)])
    if verify.returncode != 0:
        raise PreflightError("codesign --verify --deep --strict failed")
    details = _run(["codesign", "-dvvv", str(APP)])
    if f"TeamIdentifier={TEAM}" not in details.stderr:
        raise PreflightError("signing team is not DD2GCQJVB4")
    xattr = _run(["xattr", str(APP)])
    if "quarantine" in xattr.stdout.lower():
        raise PreflightError("installed app is quarantined")
    return {
        "head": head_sha,
        "stamp": stamp,
        "dirty": dirty,
        "branch": branch,
        "repository": repository,
        "sha256": inst_sha,
        "team": TEAM,
    }


def cli_version() -> str:
    grok = Path.home() / ".grok/bin/grok"
    binary = str(grok) if grok.exists() else "grok"
    result = _run([binary, "--version"])
    if result.returncode != 0:
        raise PreflightError("grok --version failed")
    return result.stdout.strip() or result.stderr.strip()


def available_models() -> list[str]:
    grok = Path.home() / ".grok/bin/grok"
    binary = str(grok) if grok.exists() else "grok"
    result = _run([binary, "models"])
    if result.returncode != 0:
        raise PreflightError("grok models failed")
    models = []
    for line in result.stdout.splitlines():
        trimmed = line.strip()
        if trimmed.startswith("- ") or trimmed.startswith("* "):
            models.append(trimmed[2:].replace(" (default)", "").strip())
    return models


def require_models(needed: list[str]) -> None:
    available = available_models()
    missing = [model for model in needed if model not in available]
    if missing:
        raise PreflightError(f"configured models unavailable: {missing}")


def marker_collisions(repo: Path, markers: list[str]) -> None:
    encoded = quote(str(repo), safe="")
    session_root = Path.home() / ".grok/sessions" / encoded
    transcript_root = (
        Path.home() / "Library/Application Support/GrokBuild/Transcripts"
    )
    hits: list[str] = []
    for marker in markers:
        if session_root.exists():
            search = _run(
                ["rg", "-l", "--glob", "!prompt_history.jsonl", marker, str(session_root)]
            )
            if search.stdout.strip():
                hits.append(marker)
        if transcript_root.exists():
            search = _run(["rg", "-l", marker, str(transcript_root)])
            if search.stdout.strip():
                hits.append(marker)
    if hits:
        raise PreflightError(f"marker uniqueness failed: {sorted(set(hits))}")


def require_clean_test_ledger(ledger: Path) -> None:
    if ledger.exists() and ledger.stat().st_size > 0:
        raise PreflightError(f"test ledger is not clean: {ledger}")


def preflight(
    repo: Path,
    manifest: dict[str, Any],
    *,
    ledger: Path,
) -> dict[str, Any]:
    identity = installed_identity(repo)
    version = cli_version()
    models = [packet["model"] for packet in manifest["packets"]]
    require_models(models)
    samples = two_process_zero_samples()
    marker_collisions(repo, [packet["marker"] for packet in manifest["packets"]])
    require_clean_test_ledger(ledger)
    return {
        "identity": identity,
        "cliVersion": version,
        "processZero": samples,
        "ledger": str(ledger),
        "pid": os.getpid(),
    }
