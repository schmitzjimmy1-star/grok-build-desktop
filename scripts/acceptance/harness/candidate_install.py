"""Slice 4B.6: install a signed digest-addressed pager into an owner-private
GrokBuild runtime. Never replaces ``~/.grok/bin/grok``. Rollback removes only
the acceptance selection after two process-zero samples.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import uuid
from pathlib import Path
from typing import Any

from .candidate_process_driver import (
    OFFICIAL_CLI,
    OFFICIAL_CLI_SHA256,
    STAGED_CLI_BUILD,
    STAGED_PAGER_SHA256,
    official_cli_sha256,
    sha256_file,
)
from .candidate_runtime import validate_runtime_selection
from .errors import HarnessError

DEFAULT_RUNTIME_ROOT = (
    Path.home() / "Library" / "Application Support" / "GrokBuild" / "candidate-runtime"
)
SELECTION_NAME = "runtime-selection.json"
ROLLBACK_NAME = "rollback-receipt-v1.json"


def owner_private_runtime_root() -> Path:
    return DEFAULT_RUNTIME_ROOT


def install_signed_candidate(
    source_selection: Path,
    dest_root: Path,
    *,
    expected_cli_build: str = STAGED_CLI_BUILD,
) -> Path:
    """Copy the validated signed pager into ``dest_root/<sha256>/`` atomically.

    Returns the destination ``runtime-selection.json``. The official CLI path is
    never a source or destination. Ordinary ``GrokProcess.start`` does not scan
    ``dest_root``.
    """
    dest_root = Path(dest_root)
    _refuse_official_cli_overlap(dest_root)
    before = _official_digest_or_missing()
    source = validate_runtime_selection(
        source_selection,
        expected_cli_build=expected_cli_build,
    )
    if source.binary_sha256 != STAGED_PAGER_SHA256:
        raise HarnessError("4B.6 requires the signed digest-staged pager, not an ad-hoc copy")
    if Path(source.candidate_path).resolve() == OFFICIAL_CLI.resolve():
        raise HarnessError("4B.6 must not install from the official CLI")

    _ensure_private_directory(dest_root)
    digest_dir = dest_root / source.binary_sha256
    staging = dest_root / f".staging-{uuid.uuid4().hex}-{source.binary_sha256[:12]}"
    moved = False
    try:
        os.mkdir(staging, 0o700)
        staged_pager = staging / "xai-grok-pager"
        staged_provenance = staging / "candidate-provenance-v1.json"
        _copy_private_file(Path(source.candidate_path), staged_pager, mode=0o700, executable=True)
        _copy_private_file(Path(source.provenance_path), staged_provenance, mode=0o600, executable=False)
        _clear_quarantine(staged_pager)
        _clear_quarantine(staged_provenance)
        if sha256_file(staged_pager) != source.binary_sha256:
            raise HarnessError("staged pager digest drifted during copy")
        if sha256_file(staged_provenance) != source.provenance_sha256:
            raise HarnessError("staged provenance digest drifted during copy")
        if os.stat(Path(source.candidate_path)).st_ino == os.stat(staged_pager).st_ino:
            raise HarnessError("4B.6 must byte-copy the pager, not hard-link it")
        _require_strict_signature(staged_pager)
        if digest_dir.exists():
            existing = digest_dir / "xai-grok-pager"
            if not existing.is_file() or sha256_file(existing) != source.binary_sha256:
                raise HarnessError("digest-addressed runtime already holds a different candidate")
            shutil.rmtree(staging)
            moved = True
        else:
            os.rename(staging, digest_dir)
            moved = True
            os.chmod(digest_dir, 0o700)
    finally:
        if not moved and Path(staging).exists():
            shutil.rmtree(staging, ignore_errors=True)

    selection_path = dest_root / SELECTION_NAME
    payload = {
        "schemaVersion": 1,
        "runtimeRoot": str(dest_root),
        "candidatePath": str(digest_dir / "xai-grok-pager"),
        "provenancePath": str(digest_dir / "candidate-provenance-v1.json"),
        "provenanceSHA256": source.provenance_sha256,
    }
    _write_private_exclusive(selection_path, _canonical_json(payload))
    installed = validate_runtime_selection(selection_path, expected_cli_build=expected_cli_build)
    if installed.binary_sha256 != source.binary_sha256:
        raise HarnessError("installed runtime selection failed validation")
    if Path(installed.candidate_path).resolve() == OFFICIAL_CLI.resolve():
        raise HarnessError("installed selection resolved to the official CLI")
    _require_official_unchanged(before)
    return selection_path


def rollback_signed_install(
    selection_path: Path,
    *,
    process_zero_samples: list[dict[str, Any]],
) -> dict[str, Any]:
    """Remove only the acceptance selection after two empty process-zero samples.

    The two samples must carry distinct timestamps. The digest-addressed pager
    and provenance stay. The official CLI is never overwritten or deleted.
    """
    selection_path = Path(selection_path)
    _refuse_official_cli_overlap(selection_path)
    before = _official_digest_or_missing()
    if not _valid_process_zero_samples(process_zero_samples):
        raise HarnessError("rollback requires two empty process-zero samples with distinct timestamps")
    if not selection_path.is_file():
        raise HarnessError("rollback requires an existing selection sidecar")
    document = json.loads(selection_path.read_text())
    candidate_path = Path(str(document.get("candidatePath") or ""))
    digest = ""
    retained = False
    if candidate_path.is_file():
        digest = sha256_file(candidate_path)
        retained = True
    metadata = selection_path.lstat()
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_uid != os.getuid()
        or stat.S_IMODE(metadata.st_mode) & 0o077
        or metadata.st_nlink != 1
    ):
        raise HarnessError("rollback refused a non-private or hard-linked selection sidecar")
    selection_path.unlink()
    receipt = {
        "schemaVersion": 1,
        "action": "remove-acceptance-selection",
        "officialCLISHA256": before or OFFICIAL_CLI_SHA256,
        "candidateBinarySHA256": digest,
        "candidateRetained": retained and candidate_path.is_file(),
        "runtimeSelectionRemoved": not selection_path.exists(),
        "officialCLIUntouched": True,
        "processZeroSamples": process_zero_samples,
    }
    receipt_path = selection_path.with_name(ROLLBACK_NAME)
    if receipt_path.exists():
        existing = receipt_path.lstat()
        if (
            not stat.S_ISREG(existing.st_mode)
            or existing.st_uid != os.getuid()
            or stat.S_IMODE(existing.st_mode) & 0o077
            or existing.st_nlink != 1
        ):
            raise HarnessError("rollback refused a non-private existing receipt")
        receipt_path.unlink()
    _write_private_exclusive(receipt_path, _canonical_json(receipt))
    _require_official_unchanged(before)
    if OFFICIAL_CLI.exists() and not OFFICIAL_CLI.is_file():
        raise HarnessError("official CLI path is no longer a file")
    return receipt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="4B.6 signed owner-private candidate install")
    sub = parser.add_subparsers(dest="command", required=True)
    install = sub.add_parser("install", help="byte-copy the signed pager into dest_root/<sha256>/")
    install.add_argument("--source", required=True, help="validated runtime-selection.json")
    install.add_argument("--dest", default=str(DEFAULT_RUNTIME_ROOT))
    rollback = sub.add_parser("rollback", help="unlink only the selection sidecar")
    rollback.add_argument("--selection", required=True)
    rollback.add_argument("--process-zero", required=True, help="JSON list of two empty samples")
    args = parser.parse_args(argv)
    if args.command == "install":
        path = install_signed_candidate(Path(args.source), Path(args.dest))
        print(path)
        return 0
    samples = json.loads(Path(args.process_zero).read_text())
    receipt = rollback_signed_install(Path(args.selection), process_zero_samples=samples)
    print(json.dumps(receipt, sort_keys=True))
    return 0


def _refuse_official_cli_overlap(path: Path) -> None:
    resolved = path.expanduser().resolve()
    grok_home = (Path.home() / ".grok").resolve()
    try:
        resolved.relative_to(grok_home)
        raise HarnessError("4B.6 must not write into ~/.grok")
    except ValueError:
        pass
    if resolved == OFFICIAL_CLI.resolve():
        raise HarnessError("4B.6 must not replace the official CLI")


def _ensure_private_directory(path: Path) -> None:
    if path.exists():
        info = path.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
            raise HarnessError("candidate runtime directory must be owner-private")
        return
    os.makedirs(path, mode=0o700, exist_ok=False)
    os.chmod(path, 0o700)


def _copy_private_file(source: Path, destination: Path, *, mode: int, executable: bool) -> None:
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    src_fd = os.open(source, flags)
    try:
        before = os.fstat(src_fd)
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
            raise HarnessError("install source must be one regular file")
        if executable and not before.st_mode & stat.S_IXUSR:
            raise HarnessError("candidate binary must be owner-executable")
        data = bytearray()
        remaining = before.st_size
        while remaining > 0:
            chunk = os.read(src_fd, remaining)
            if not chunk:
                break
            data.extend(chunk)
            remaining -= len(chunk)
        if len(data) != before.st_size:
            raise HarnessError("install source changed while reading")
    finally:
        os.close(src_fd)
    write_flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    dest_fd = os.open(destination, write_flags, mode)
    try:
        written = 0
        payload = bytes(data)
        while written < len(payload):
            written += os.write(dest_fd, payload[written:])
        os.fsync(dest_fd)
    finally:
        os.close(dest_fd)
    os.chmod(destination, mode)


def _clear_quarantine(path: Path) -> None:
    subprocess.run(
        ["/usr/bin/xattr", "-d", "com.apple.quarantine", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    listing = subprocess.run(
        ["/usr/bin/xattr", "-l", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if "com.apple.quarantine" in (listing.stdout or ""):
        raise HarnessError("candidate still has quarantine after install")


def _require_strict_signature(path: Path) -> None:
    verify = subprocess.run(
        ["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if verify.returncode != 0:
        raise HarnessError("installed candidate failed strict code-signing verification")
    details = subprocess.run(
        ["/usr/bin/codesign", "-d", "--verbose=4", str(path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if "TeamIdentifier=DD2GCQJVB4" not in details.stderr:
        raise HarnessError("installed candidate is not Team DD2GCQJVB4")


def _write_private_exclusive(path: Path, payload: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags, 0o600)
    except OSError as exc:
        raise HarnessError("install sidecar must not pre-exist or follow a link") from exc
    with os.fdopen(fd, "wb") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    if stat.S_IMODE(path.stat().st_mode) != 0o600:
        raise HarnessError("install sidecar must be private")


def _canonical_json(value: dict[str, Any]) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def _valid_process_zero_samples(samples: list[dict[str, Any]] | None) -> bool:
    if not isinstance(samples, list) or len(samples) != 2:
        return False
    stamps: list[str] = []
    for sample in samples:
        stamp = sample.get("at") if isinstance(sample, dict) else None
        if not isinstance(stamp, str) or not stamp:
            return False
        stamps.append(stamp)
        pids = sample.get("pids")
        if not isinstance(pids, dict) or not pids:
            return False
        if any(not isinstance(values, list) or values for values in pids.values()):
            return False
    return stamps[0] != stamps[1]


def _official_digest_or_missing() -> str | None:
    if not OFFICIAL_CLI.is_file():
        return None
    return official_cli_sha256()


def _require_official_unchanged(before: str | None) -> None:
    after = _official_digest_or_missing()
    if before is None and after is None:
        return
    if before is None or after is None or after != before:
        raise HarnessError("official grok CLI changed during 4B.6 install")
    if after != OFFICIAL_CLI_SHA256:
        raise HarnessError("official grok CLI digest drifted")


if __name__ == "__main__":
    raise SystemExit(main())
