"""Exact, credential-free runtime-selection validation for Slice 4B.1."""

from __future__ import annotations

import hashlib
import json
import os
import re
import platform
import stat
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .errors import HarnessError

EXPECTED_TEAM = "DD2GCQJVB4"
MAX_MANIFEST_BYTES = 1_048_576
MAX_BINARY_BYTES = 536_870_912


@dataclass(frozen=True)
class CandidateRuntimeSelection:
    document: dict
    provenance_sha256: str
    binary_sha256: str
    candidate_path: Path
    provenance_path: Path
    cli_build: str


SignatureProbe = Callable[[Path], tuple[str, str, str]]


def validate_runtime_selection(
    path: Path,
    *,
    expected_cli_build: str,
    signature_probe: SignatureProbe | None = None,
) -> CandidateRuntimeSelection:
    selection = _json_object(_read_private(path, MAX_MANIFEST_BYTES), "runtime selection")
    _exact(selection, {"schemaVersion", "runtimeRoot", "candidatePath", "provenancePath", "provenanceSHA256"})
    if selection["schemaVersion"] != 1:
        raise HarnessError("runtime selection schemaVersion must be 1")
    raw_root = Path(_absolute_string(selection["runtimeRoot"], "runtimeRoot"))
    # Check the caller-named leaf before canonicalizing ordinary system
    # ancestors such as /var -> /private/var. Resolving first would erase a
    # hostile runtimeRoot symlink and diverge from Swift's lstat contract.
    _private_directory(raw_root)
    root = Path(os.path.abspath(raw_root))
    candidate = Path(_absolute_string(selection["candidatePath"], "candidatePath"))
    provenance = Path(_absolute_string(selection["provenancePath"], "provenancePath"))
    provenance_sha = _sha_string(selection["provenanceSHA256"], "provenanceSHA256")

    provenance_bytes = _read_private(provenance, MAX_MANIFEST_BYTES)
    if _sha256(provenance_bytes) != provenance_sha:
        raise HarnessError("candidate provenance digest mismatch")
    document = _json_object(provenance_bytes, "candidate provenance")
    _exact(document, {"schemaVersion", "source", "toolchain", "build", "binary", "signing"})
    if document["schemaVersion"] != 1:
        raise HarnessError("candidate provenance schemaVersion must be 1")
    source = _object(document["source"], "source")
    _exact(source, {"officialBaseSHA", "upstreamReplayBaseSHA", "forkSourceSHA", "sourceRev", "cargoLockSHA256"})
    for key in ("officialBaseSHA", "upstreamReplayBaseSHA", "forkSourceSHA", "sourceRev"):
        _git_sha_string(source[key], f"source.{key}")
    _sha_string(source["cargoLockSHA256"], "source.cargoLockSHA256")

    toolchain = _object(document["toolchain"], "toolchain")
    _exact(toolchain, {
        "rustVersion", "cargoVersion", "dotslashVersion", "rustcSHA256", "cargoSHA256",
        "dotslashSHA256", "targetTriple", "architecture",
    })
    architecture = _nonempty(toolchain["architecture"], "toolchain.architecture")
    host_architecture = "arm64" if platform.machine() in {"arm64", "arm64e"} else platform.machine()
    expected_triple = "aarch64-apple-darwin" if architecture == "arm64" else "x86_64-apple-darwin"
    if architecture != host_architecture or toolchain["targetTriple"] != expected_triple:
        raise HarnessError("candidate toolchain architecture is unsupported")
    if not _nonempty(toolchain["rustVersion"], "toolchain.rustVersion").startswith("rustc 1.94.0 "):
        raise HarnessError("candidate Rust version is not pinned")
    if not _nonempty(toolchain["cargoVersion"], "toolchain.cargoVersion").startswith("cargo 1.94.0 "):
        raise HarnessError("candidate Cargo version is not pinned")
    if toolchain["dotslashVersion"] != "DotSlash 0.5.7":
        raise HarnessError("candidate DotSlash version is not pinned")
    for key in ("rustcSHA256", "cargoSHA256", "dotslashSHA256"):
        _sha_string(toolchain[key], f"toolchain.{key}")

    build = _object(document["build"], "build")
    _validate_build(build)
    binary = _object(document["binary"], "binary")
    signing = _object(document["signing"], "signing")
    expected_binary_keys = {
        "artifactName", "sha256", "sizeBytes", "architecture", "expectedVersionWithCommit",
        "expectedACPCLIBuild", "observedVersionWithCommit",
    }
    _exact(binary, expected_binary_keys)
    if binary["artifactName"] != "xai-grok-pager":
        raise HarnessError("candidate artifactName mismatch")
    cli_build = _nonempty(binary["expectedACPCLIBuild"], "expectedACPCLIBuild")
    source_bound_build = f"1.0.5 ({source['forkSourceSHA'][:7]})"
    if (cli_build != expected_cli_build or cli_build != source_bound_build
            or binary["expectedVersionWithCommit"] != cli_build
            or binary["observedVersionWithCommit"] != cli_build):
        raise HarnessError("candidate CLI build mismatch")
    binary_sha = _sha_string(binary["sha256"], "binary.sha256")
    binary_size = binary["sizeBytes"]
    if type(binary_size) is not int or not 0 < binary_size <= MAX_BINARY_BYTES:
        raise HarnessError("candidate size is invalid")
    binary_architecture = _nonempty(binary["architecture"], "binary.architecture")
    if binary_architecture != architecture:
        raise HarnessError("candidate architecture is unsupported")

    _exact(signing, {"state", "strictVerification", "teamIdentifier", "designatedRequirement"})
    requirement = _nonempty(signing["designatedRequirement"], "designatedRequirement")
    if signing["state"] != "signed" or signing["strictVerification"] is not True or signing["teamIdentifier"] != EXPECTED_TEAM:
        raise HarnessError("candidate signing contract is not strict GrokBuild Team authority")

    candidate_bytes = _read_private(candidate, MAX_BINARY_BYTES, executable=True)
    if len(candidate_bytes) != binary_size or _sha256(candidate_bytes) != binary_sha:
        raise HarnessError("candidate binary digest or size mismatch")
    digest_directory = root / binary_sha
    candidate_parent = Path(os.path.abspath(candidate)).parent
    provenance_parent = Path(os.path.abspath(provenance)).parent
    if candidate_parent != digest_directory or provenance_parent != digest_directory:
        raise HarnessError("candidate runtime is not in its digest-addressed directory")
    _private_directory(digest_directory)

    observed_team, observed_requirement, observed_architecture = (signature_probe or _codesign_probe)(candidate)
    if (observed_team, observed_requirement, observed_architecture) != (EXPECTED_TEAM, requirement, binary_architecture):
        raise HarnessError("candidate signature, requirement, or architecture drift")
    return CandidateRuntimeSelection(
        document=selection,
        provenance_sha256=provenance_sha,
        binary_sha256=binary_sha,
        candidate_path=candidate,
        provenance_path=provenance,
        cli_build=cli_build,
    )


def _codesign_probe(path: Path) -> tuple[str, str, str]:
    verify = subprocess.run(
        ["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", str(path)],
        capture_output=True, text=True, check=False,
    )
    if verify.returncode != 0:
        raise HarnessError("candidate failed strict code-signing verification")
    details = subprocess.run(
        ["/usr/bin/codesign", "-d", "--verbose=4", str(path)],
        capture_output=True, text=True, check=False,
    )
    requirement = subprocess.run(
        ["/usr/bin/codesign", "-d", "-r-", str(path)],
        capture_output=True, text=True, check=False,
    )
    architecture = subprocess.run(
        ["/usr/bin/lipo", "-archs", str(path)], capture_output=True, text=True, check=False,
    )
    if details.returncode != 0 or requirement.returncode != 0 or architecture.returncode != 0:
        raise HarnessError("candidate signing or architecture receipt is unavailable")
    team_match = re.search(r"^TeamIdentifier=(.+)$", details.stderr, re.MULTILINE)
    requirement_match = re.search(r"designated => (.+)$", requirement.stderr, re.MULTILINE)
    archs = architecture.stdout.split()
    if not team_match or not requirement_match or len(archs) != 1:
        raise HarnessError("candidate signing or architecture receipt is ambiguous")
    return team_match.group(1).strip(), requirement_match.group(1).strip(), archs[0]


def _read_private(path: Path, maximum: int, *, executable: bool = False) -> bytes:
    if not path.is_absolute():
        raise HarnessError("candidate authority paths must be absolute")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        raise HarnessError("candidate authority path is unreadable or follows a link") from exc
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink != 1:
            raise HarnessError("candidate authority must be one owner-held regular file")
        if stat.S_IMODE(before.st_mode) & 0o077:
            raise HarnessError("candidate authority must be private")
        if executable and not before.st_mode & stat.S_IXUSR:
            raise HarnessError("candidate binary must be owner-executable")
        if before.st_size < 0 or before.st_size > maximum:
            raise HarnessError("candidate authority size is invalid")
        data = bytearray()
        while len(data) < before.st_size:
            chunk = os.read(fd, min(1_048_576, before.st_size - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        after = os.fstat(fd)
        if len(data) != before.st_size or (after.st_dev, after.st_ino, after.st_size) != (before.st_dev, before.st_ino, before.st_size):
            raise HarnessError("candidate authority changed while reading")
        return bytes(data)
    finally:
        os.close(fd)


def _private_directory(path: Path) -> None:
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise HarnessError("candidate runtime directory must be owner-private")


def _json_object(data: bytes, label: str) -> dict:
    try:
        value = json.loads(data)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise HarnessError(f"{label} is invalid JSON") from exc
    return _object(value, label)


def _object(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        raise HarnessError(f"{label} must be an object")
    return value


def _exact(value: dict, keys: set[str]) -> None:
    if set(value) != keys:
        raise HarnessError("candidate authority contains missing or unknown fields")


def _absolute_string(value: object, label: str) -> str:
    value = _nonempty(value, label)
    if not Path(value).is_absolute():
        raise HarnessError(f"{label} must be absolute")
    return value


def _nonempty(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise HarnessError(f"{label} must be a nonempty string")
    return value


def _sha_string(value: object, label: str) -> str:
    value = _nonempty(value, label)
    if re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise HarnessError(f"{label} must be lowercase SHA-256")
    return value


def _git_sha_string(value: object, label: str) -> str:
    value = _nonempty(value, label)
    if re.fullmatch(r"[0-9a-f]{40}", value) is None:
        raise HarnessError(f"{label} must be lowercase Git SHA")
    return value


def _validate_build(build: dict) -> None:
    _exact(build, {"preBuildCommand", "command", "environment", "profile", "package", "features"})
    expected_prebuild = [
        "cargo", "clean", "--target-dir", "<candidate-target>", "--profile", "release-dist",
        "-p", "xai-grok-pager-bin",
    ]
    expected_build = [
        "cargo", "build", "--locked", "--profile", "release-dist", "-p",
        "xai-grok-pager-bin", "--features", "release-dist",
    ]
    if build["preBuildCommand"] != expected_prebuild or build["command"] != expected_build:
        raise HarnessError("candidate build command drift")
    if build["profile"] != "release-dist" or build["package"] != "xai-grok-pager-bin":
        raise HarnessError("candidate package or profile drift")
    if build["features"] != ["release-dist"]:
        raise HarnessError("candidate feature drift")
    environment = _object(build["environment"], "build.environment")
    _exact(environment, {
        "clearEnvironment", "home", "path", "cargoHome", "rustupHome", "rustc",
        "cargoTargetDir", "cargoIncremental", "locale", "temporaryDirectory",
    })
    expected_environment = {
        "clearEnvironment": True,
        "home": "<account-home>",
        "path": ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "<dotslash-directory>"],
        "cargoHome": "<account-home>/.cargo",
        "rustupHome": "<account-home>/.rustup",
        "rustc": "<pinned-rustc>",
        "cargoTargetDir": "<candidate-target>",
        "cargoIncremental": False,
        "locale": "C",
        "temporaryDirectory": "/private/tmp",
    }
    if environment != expected_environment:
        raise HarnessError("candidate build environment drift")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()
