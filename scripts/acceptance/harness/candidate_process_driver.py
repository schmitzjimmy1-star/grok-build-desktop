"""Staged-candidate process-driver helpers for Slice 4B.5.

This module never replaces ``~/.grok/bin/grok``. It validates the owner-private
selection file, hashes loopback endpoints the same way the CLI does, and writes
isolated HOME config plus a schema-3 CLI manifest. Live spawn stays in Swift
``GrokProcess.start``.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

from .candidate_runtime import validate_runtime_selection
from .errors import HarnessError

OFFICIAL_CLI = Path.home() / ".grok" / "bin" / "grok"
OFFICIAL_CLI_SHA256 = "39366f7756a090b735cc1df8c93a8c0c3c7871555cf6cbb28f9351ca82936485"
STAGED_PAGER_SHA256 = "354b3b71306c04fdc43efc90193232d5409035871330387ebb86c4dc99693c98"
STAGED_CLI_BUILD = "1.0.5 (d11dfed)"
STAGED_SOURCE_SHA = "d11dfed12c4e161951f9198ce2404ca2d15379a3"
LIVE_SERIALIZER_PAYLOAD_CEILING = 65_536
ISOLATED_TOOL_IDS = [
    "GrokBuild:get_task_output",
    "GrokBuild:kill_task",
    "GrokBuild:read_file",
    "GrokBuild:task",
    "GrokBuild:wait_tasks",
]
BACKEND_PATHS = {
    "chat_completions": "chat/completions",
    "responses": "responses",
    "messages": "messages",
}
MODEL_ID = "s4b5-direct"
PROVIDER_ID = "openrouter"
PROVIDER_FACING_MODEL = "loopback-model"
MAX_OUTPUT_TOKENS = 256
CAMPAIGN_ID = "s4b5-lifecycle"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def official_cli_sha256() -> str:
    if not OFFICIAL_CLI.is_file():
        raise HarnessError("official grok CLI is missing")
    return sha256_file(OFFICIAL_CLI)


def require_official_cli_untouched(before: str | None = None) -> str:
    digest = official_cli_sha256()
    if digest != OFFICIAL_CLI_SHA256:
        raise HarnessError("official grok CLI digest drifted")
    if before is not None and digest != before:
        raise HarnessError("official grok CLI changed during 4B.5")
    return digest


def require_staged_selection(path: Path) -> dict[str, Any]:
    selection = validate_runtime_selection(path, expected_cli_build=STAGED_CLI_BUILD)
    if selection.binary_sha256 != STAGED_PAGER_SHA256:
        raise HarnessError("4B.5 requires the signed digest-staged pager, not an ad-hoc copy")
    if Path(selection.candidate_path).resolve() == OFFICIAL_CLI.resolve():
        raise HarnessError("4B.5 must not select the installed official CLI")
    return {
        "binarySHA256": selection.binary_sha256,
        "cliBuild": selection.cli_build,
        "candidatePath": str(selection.candidate_path),
        "sourceSHA": STAGED_SOURCE_SHA,
    }


def exact_loopback_endpoint_sha256(base_url: str, api_backend: str) -> str:
    if "://" not in base_url or "?" in base_url:
        raise HarnessError("loopback base URL is invalid")
    parsed = base_url.split("://", 1)[1]
    host = parsed.split("/", 1)[0]
    if host not in {"127.0.0.1", "localhost"} and not host.startswith("127."):
        raise HarnessError("4B.5 loopback provider refuses non-loopback hosts")
    path = BACKEND_PATHS.get(api_backend)
    if path is None:
        raise HarnessError("unsupported api backend")
    url = f"{base_url.rstrip('/')}/{path}"
    return sha256_bytes(url.encode())


def deterministic_route_id(
    provider_id: str,
    provider_facing_model: str,
    endpoint_sha256: str,
    api_backend: str,
    auth_scheme: str,
) -> str:
    joined = "\0".join(
        [provider_id, provider_facing_model, endpoint_sha256, api_backend, auth_scheme]
    )
    return "v3." + sha256_bytes(joined.encode())


def config_projection_bytes(base_url: str, catalog_key: str = MODEL_ID) -> bytes:
    rows = [
        {
            "catalogKey": catalog_key,
            "model": PROVIDER_FACING_MODEL,
            "modelProvider": PROVIDER_ID,
            "apiBackend": "chat_completions",
            "authScheme": "bearer",
            "baseUrl": base_url.rstrip("/"),
        }
    ]
    return json.dumps(rows, separators=(",", ":")).encode()


def write_isolated_home(home: Path, base_url: str) -> Path:
    grok = home / ".grok"
    grok.mkdir(mode=0o700)
    config = grok / "config.toml"
    body = f"""[endpoints]
models_list_url = "{base_url.rstrip('/')}/models"

[model_providers.{PROVIDER_ID}]
name = "OpenRouter"
base_url = "{base_url.rstrip('/')}"

[model.{MODEL_ID}]
model = "{PROVIDER_FACING_MODEL}"
model_provider = "{PROVIDER_ID}"
api_backend = "chat_completions"
max_completion_tokens = {MAX_OUTPUT_TOKENS}

[models]
default = "{MODEL_ID}"
"""
    config.write_text(body)
    os.chmod(config, 0o600)
    return config


def conservative_request_bound_tokens(max_output_tokens: int = MAX_OUTPUT_TOKENS) -> int:
    return LIVE_SERIALIZER_PAYLOAD_CEILING + max_output_tokens


def route_expectation(base_url: str, *, token_ceiling: int, max_model_calls: int) -> dict[str, Any]:
    endpoint = exact_loopback_endpoint_sha256(base_url, "chat_completions")
    bound = conservative_request_bound_tokens()
    if bound > token_ceiling:
        raise HarnessError("allocation cannot cover the live serializer ceiling")
    return {
        "routeId": deterministic_route_id(
            PROVIDER_ID, PROVIDER_FACING_MODEL, endpoint, "chat_completions", "bearer"
        ),
        "providerId": PROVIDER_ID,
        "providerFacingModel": PROVIDER_FACING_MODEL,
        "endpointSha256": endpoint,
        "apiBackend": "chat_completions",
        "credentialTransport": "fd_v1",
        "authScheme": "bearer",
        "maxFinalSerializedPayloadBytes": LIVE_SERIALIZER_PAYLOAD_CEILING,
        "maxOutputTokens": MAX_OUTPUT_TOKENS,
        "conservativeRequestBoundTokens": bound,
        "allocationTokenCeiling": token_ceiling,
        "maxModelCalls": max_model_calls,
        "textOnly": True,
        "remoteContextForbidden": True,
        "multimodalForbidden": True,
        "redirectDisabled": True,
        "retryDisabled": True,
        "toolIsolation": {
            "authProviderHelpersDisabled": True,
            "terminalDisabled": True,
            "externalMcpDisabled": True,
            "hooksDisabled": True,
            "pluginsDisabled": True,
            "lspDisabled": True,
            "workflowsDisabled": True,
            "schedulerDisabled": True,
            "protectedAuthorityFs": True,
            "workspaceFsConfined": True,
            "samplerTransportRetriesDisabled": True,
            "allowedToolIds": list(ISOLATED_TOOL_IDS),
        },
    }


def write_v3_manifest(
    directory: Path,
    base_url: str,
    allocations: list[dict[str, Any]],
) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    projection = config_projection_bytes(base_url)
    manifest = {
        "schemaVersion": 3,
        "campaignId": CAMPAIGN_ID,
        "campaignPolicy": {
            "schemaVersion": 3,
            "absoluteTokenCeiling": 20_000_000,
            "allocatableTokenCeiling": 19_000_000,
            "unreachableReserveTokens": 1_000_000,
        },
        "candidateExpectation": {
            "cliBuild": STAGED_CLI_BUILD,
            "binarySha256": STAGED_PAGER_SHA256,
            "sourceCommitSha": STAGED_SOURCE_SHA,
        },
        "configExpectation": {
            "sourceKind": "resolved-managed-provider",
            "generation": 1,
            "managedProviderId": PROVIDER_ID,
            "configProjectionSha256": sha256_bytes(projection),
        },
        "allocations": allocations,
    }
    path = directory / "manifest-v3.json"
    path.write_bytes(json.dumps(manifest, separators=(",", ":")).encode())
    os.chmod(path, 0o600)
    ledger = directory / "ledger.json"
    ledger.write_bytes(b"")
    os.chmod(ledger, 0o600)
    return path


def one_allocation(
    base_url: str,
    *,
    allocation_id: str,
    packet_id: str,
    prompt: str,
    token_ceiling: int,
    max_model_calls: int,
) -> dict[str, Any]:
    return {
        "id": allocation_id,
        "packetId": packet_id,
        "promptSha256": sha256_bytes(prompt.encode()),
        "tokenCeiling": token_ceiling,
        "maxModelCalls": max_model_calls,
        "routeExpectation": route_expectation(
            base_url, token_ceiling=token_ceiling, max_model_calls=max_model_calls
        ),
    }
