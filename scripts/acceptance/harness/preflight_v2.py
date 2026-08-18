"""Nonbillable Slice 4 gates required before the first Send actuator."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - exercised only on obsolete system Python.
    tomllib = None  # type: ignore[assignment]

from .errors import PreflightError
from .preflight import APP, DIST, TEAM, cli_version, installed_identity, marker_collisions, require_clean_test_ledger, require_models, two_process_zero_samples

HELPER = APP / "Contents/MacOS/GrokBuildProviderAuthHelper"
CONFIG = Path.home() / ".grok/config.toml"
VERSION = re.compile(r"\b(\d+)\.(\d+)\.(\d+)")


def require_runtime_floor(version_text: str | None = None) -> str:
    version_text = version_text or cli_version()
    match = VERSION.search(version_text)
    if not match or tuple(map(int, match.groups())) < (1, 0, 5):
        raise PreflightError(
            "all billable acceptance is disabled until the installed Grok ACP runtime is 1.0.5+"
        )
    return version_text


def preflight(repo: Path, manifest: dict[str, Any], *, ledger: Path) -> dict[str, Any]:
    unpriced = [
        packet["id"] for packet in manifest["packets"]
        if packet["routeReceipt"]["kind"] != "nativeXAI" and packet["frozenPricing"] is None
    ]
    if unpriced:
        raise PreflightError(f"provider packets lack frozen current pricing: {unpriced}")
    identity = installed_identity(repo)
    version_text = require_runtime_floor()
    require_models([packet["selectorModelID"] for packet in manifest["packets"]])
    _require_configured_routes(manifest)
    inspect_sha = _require_effective_config(repo)
    marker_collisions(repo, [packet["marker"] for packet in manifest["packets"]])
    require_clean_test_ledger(ledger)
    if not HELPER.is_file() or not HELPER.stat().st_mode & 0o111:
        raise PreflightError("installed provider auth helper is missing or non-executable")
    dist_helper = repo / DIST / "Contents/MacOS/GrokBuildProviderAuthHelper"
    if not dist_helper.is_file() or _sha256(dist_helper) != _sha256(HELPER):
        raise PreflightError("dist/installed provider auth helper hash mismatch")
    verify = _run(["codesign", "--verify", "--strict", str(HELPER)])
    details = _run(["codesign", "-dvvv", str(HELPER)])
    if verify.returncode != 0 or f"TeamIdentifier={TEAM}" not in details.stderr:
        raise PreflightError("installed provider auth helper signing identity is invalid")
    app_requirement = _run(["codesign", "-dr", "-", str(APP / "Contents/MacOS/GrokBuild")]).stderr
    helper_requirement = _run(["codesign", "-dr", "-", str(HELPER)]).stderr
    if _requirement(app_requirement) != _requirement(helper_requirement):
        raise PreflightError("GUI/helper designated requirements differ")
    for args in ([], ["bad/id"]):
        negative = _run([str(HELPER), *args])
        if negative.returncode == 0 or negative.stdout:
            raise PreflightError("provider helper negative path emitted credential bytes or succeeded")
    selected_agent = _run(["defaults", "read", "com.grokbuild.app", "grokbuild.selectedAgent"])
    if selected_agent.returncode == 0 and selected_agent.stdout.strip():
        raise PreflightError("paid acceptance requires the inherited session agent to be Default")
    require_absolute_ceiling_support()
    return {
        "identity": identity,
        "cliVersion": version_text,
        "processZero": two_process_zero_samples(),
        "helperSha256": _sha256(HELPER),
        "configSha256": _sha256(CONFIG) if CONFIG.exists() else None,
        "effectiveConfigSha256": inspect_sha,
        "ledgerClean": True,
    }


def _run(args: list[str], *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=False)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _requirement(output: str) -> str:
    return output.split("designated =>", 1)[-1].strip()


def _require_configured_routes(manifest: dict[str, Any]) -> None:
    if tomllib is None:
        raise PreflightError("billable preflight requires Python 3.11+ for strict TOML validation")
    try:
        with CONFIG.open("rb") as handle:
            config = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise PreflightError("official provider config is unavailable or invalid") from exc
    models = config.get("model") if isinstance(config.get("model"), dict) else {}
    providers = config.get("model_providers") if isinstance(config.get("model_providers"), dict) else {}
    for packet in manifest["packets"]:
        route = packet["routeReceipt"]
        if route["kind"] == "nativeXAI":
            continue
        model = models.get(packet["selectorModelID"])
        provider = providers.get(route["officialProviderID"])
        if not isinstance(model, dict) or not isinstance(provider, dict):
            raise PreflightError(f"{packet['id']}: official provider/model projection is absent")
        if model.get("model_provider") != route["officialProviderID"]:
            raise PreflightError(f"{packet['id']}: model_provider binding mismatch")
        if model.get("model") != route["providerModelID"] or model.get("api_backend") != route["apiBackend"]:
            raise PreflightError(f"{packet['id']}: provider-facing model/backend mismatch")
        if set(model) & {"api_key", "env_key", "auth_provider", "base_url", "api_base_url"}:
            raise PreflightError(f"{packet['id']}: legacy inline model credential/endpoint remains")
        if provider.get("base_url") != route["endpointIdentity"]:
            raise PreflightError(f"{packet['id']}: provider endpoint mismatch")
        auth = provider.get("auth")
        if set(provider) != {"base_url", "auth"}:
            raise PreflightError(f"{packet['id']}: provider contains a helper-shadowing or unowned field")
        if route["authBoundary"] == "officialHelper":
            if not isinstance(auth, dict):
                raise PreflightError(f"{packet['id']}: official helper boundary is absent")
            if auth.get("command") != str(HELPER) or auth.get("args") != [route["appProviderID"]]:
                raise PreflightError(f"{packet['id']}: helper command/argument mismatch")
            if set(auth) != {"command", "args", "token_ttl_secs", "timeout_secs"}:
                raise PreflightError(f"{packet['id']}: helper auth table contains an unexpected field")
            if auth.get("token_ttl_secs") != 300 or auth.get("timeout_secs") != 10:
                raise PreflightError(f"{packet['id']}: helper TTL/timeout mismatch")


def _require_effective_config(repo: Path) -> str:
    grok = Path.home() / ".grok/bin/grok"
    binary = str(grok) if grok.exists() else "grok"
    result = _run([binary, "inspect", "--json"], cwd=repo)
    if result.returncode != 0:
        raise PreflightError("official grok inspect --json failed")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise PreflightError("official inspect did not return JSON") from exc
    if not isinstance(payload, dict):
        raise PreflightError("official inspect report is not an object")
    warnings = payload.get("configWarnings") or []
    if not isinstance(warnings, list) or warnings:
        raise PreflightError("official inspect reports effective configuration warnings")
    if payload.get("cwd") != str(repo) or payload.get("projectRoot") != str(repo):
        raise PreflightError("official inspect cwd/project root differs from the pinned acceptance workspace")
    sources = payload.get("configSources")
    layers = sources.get("layers") if isinstance(sources, dict) else None
    if not isinstance(layers, list):
        raise PreflightError("official inspect did not expose effective configuration sources")
    user_layers = []
    for layer in layers:
        if not isinstance(layer, dict):
            raise PreflightError("official inspect emitted an invalid configuration layer")
        role = layer.get("role")
        note = str(layer.get("note") or "").lower()
        path = layer.get("path")
        if role == "user":
            user_layers.append(layer)
            if path != str(CONFIG) or "parse" in note or "invalid" in note:
                raise PreflightError("official user configuration source is not the expected valid file")
            continue
        # Any effective managed, project, requirements, MDM, or environment
        # layer could alter provider/auth/model semantics. Empty layers are
        # inert; everything else blocks instead of being guessed safe.
        if note != "empty":
            raise PreflightError(f"unexpected effective configuration layer: {role}")
    if len(user_layers) != 1:
        raise PreflightError("official inspect must report exactly one user config layer")
    receipt = {
        "cwd": payload.get("cwd"),
        "projectRoot": payload.get("projectRoot"),
        "configSources": sources,
        "configWarnings": warnings,
    }
    encoded = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def effective_config_sha(repo: Path) -> str:
    """Re-evaluate official layered configuration immediately before Send."""
    return _require_effective_config(repo)


def require_absolute_ceiling_support() -> None:
    raise PreflightError(
        "billable Slice 4 remains locked: ACP usage polling is reactive and cannot prove the absolute 4,000,000-token ceiling"
    )
