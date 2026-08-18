"""Independent Slice 4B.3 canonical provenance verifier.

This module consumes a CLI-produced HardTokenBoundProvenanceV1 document. It does
not resolve routes, read credentials, or upgrade historical v2 receipts. V2
schemas remain historical in authority_v2.py / schema_v2.py.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any

GOLDEN_CANONICAL = (
    '{"allocationId":"allocation-1","campaignId":"campaign-v3",'
    '"campaignPolicy":{"absoluteTokenCeiling":20000000,"allocatableTokenCeiling":19000000,'
    '"schemaVersion":3,"unreachableReserveTokens":1000000},'
    '"candidate":{"binarySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
    '"cliBuild":"1.0.5 (003f955)","sourceCommitSha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},'
    '"configIdentity":{"configProjectionSha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",'
    '"generation":7,"managedProviderId":"openrouter","sourceKind":"resolved-managed-provider"},'
    '"route":{"allocationTokenCeiling":20000,"apiBackend":"responses","authScheme":"bearer",'
    '"conservativeRequestBoundTokens":12288,"credentialTransport":"fd_v1",'
    '"endpointSha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",'
    '"maxFinalSerializedPayloadBytes":8192,"maxModelCalls":1,"maxOutputTokens":4096,'
    '"multimodalForbidden":true,"providerFacingModel":"openai/gpt-4.1-mini",'
    '"providerId":"openrouter","redirectDisabled":true,"remoteContextForbidden":true,'
    '"retryDisabled":true,"routeId":"route-1","textOnly":true,'
    '"toolIsolation":{"allowedToolIds":["GrokBuild:read_file","GrokBuild:task"],'
    '"authProviderHelpersDisabled":true,"externalMcpDisabled":true,"hooksDisabled":true,'
    '"lspDisabled":true,"pluginsDisabled":true,"protectedAuthorityFs":true,'
    '"samplerTransportRetriesDisabled":true,"schedulerDisabled":true,"terminalDisabled":true,'
    '"workflowsDisabled":true,"workspaceFsConfined":true}},'
    '"schemaVersion":1,"serializerVersion":1}'
)
GOLDEN_SHA256 = "5052a5285a35ea96151340259475a69351ed162c8308a8f2166b453a5720f950"

ABSOLUTE_TOKEN_CEILING = 20_000_000
ALLOCATABLE_TOKEN_CEILING = 19_000_000
UNREACHABLE_RESERVE_TOKENS = 1_000_000
AUTH_HEADERS = {
    "bearer": ("authorization",),
    "x_api_key": ("x-api-key",),
    "bearer_and_x_api_key": ("authorization", "x-api-key"),
}


class ProvenanceV3Error(ValueError):
    """Fail-closed independent v3 provenance verification."""


def canonical_json_bytes(value: Any) -> bytes:
    if isinstance(value, float):
        raise ProvenanceV3Error("hard-token provenance forbids floats")
    if value is None:
        return b"null"
    if isinstance(value, bool):
        return b"true" if value else b"false"
    if isinstance(value, int):
        return str(value).encode("ascii")
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True).encode("ascii")
    if isinstance(value, list):
        return b"[" + b",".join(canonical_json_bytes(item) for item in value) + b"]"
    if isinstance(value, dict):
        items = []
        for key in sorted(value):
            if not isinstance(key, str) or not key.isascii():
                raise ProvenanceV3Error("hard-token provenance keys must be ASCII")
            items.append(json.dumps(key, ensure_ascii=True).encode("ascii") + b":" + canonical_json_bytes(value[key]))
        return b"{" + b",".join(items) + b"}"
    raise ProvenanceV3Error("hard-token provenance JSON is malformed")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_auth_header_names(auth_scheme: str) -> tuple[str, ...]:
    try:
        return AUTH_HEADERS[auth_scheme]
    except KeyError as error:
        raise ProvenanceV3Error("armed v3 auth scheme is invalid") from error


def _require_identifier(value: Any) -> str:
    if not isinstance(value, str) or not value or len(value) > 128:
        raise ProvenanceV3Error("hard-token provenance identifier is invalid")
    if any(ord(char) > 127 or not (char.isalnum() or char in "-_.") for char in value):
        raise ProvenanceV3Error("hard-token provenance identifier is invalid")
    return value


def _require_ascii(value: Any, maximum: int) -> str:
    if (
        not isinstance(value, str)
        or not value
        or len(value) > maximum
        or not value.isascii()
        or any(ord(char) < 32 or ord(char) == 127 for char in value)
    ):
        raise ProvenanceV3Error("hard-token provenance ASCII field is invalid")
    return value


def _require_positive_int(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ProvenanceV3Error("hard-token provenance integer is invalid")
    return value


def _require_sha256(value: Any) -> str:
    if not isinstance(value, str) or len(value) != 64 or any(char not in "0123456789abcdef" for char in value):
        raise ProvenanceV3Error("hard-token provenance digest is invalid")
    return value


def _require_commit(value: Any) -> str:
    if not isinstance(value, str) or len(value) != 40 or any(char not in "0123456789abcdef" for char in value):
        raise ProvenanceV3Error("hard-token provenance source commit is invalid")
    return value


def verify_campaign_policy(policy: dict[str, Any]) -> None:
    if set(policy) != {
        "schemaVersion",
        "absoluteTokenCeiling",
        "allocatableTokenCeiling",
        "unreachableReserveTokens",
    }:
        raise ProvenanceV3Error("campaign policy v3 document is unsupported")
    if (
        policy["schemaVersion"] != 3
        or policy["absoluteTokenCeiling"] != ABSOLUTE_TOKEN_CEILING
        or policy["allocatableTokenCeiling"] != ALLOCATABLE_TOKEN_CEILING
        or policy["unreachableReserveTokens"] != UNREACHABLE_RESERVE_TOKENS
        or policy["allocatableTokenCeiling"] + policy["unreachableReserveTokens"]
        != policy["absoluteTokenCeiling"]
    ):
        raise ProvenanceV3Error("campaign policy v3 document is unsupported")


def verify_canonical_provenance(data: bytes) -> dict[str, Any]:
    try:
        document = json.loads(data.decode("ascii"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProvenanceV3Error("hard-token provenance JSON is malformed") from error
    if not isinstance(document, dict):
        raise ProvenanceV3Error("hard-token provenance JSON is malformed")
    if canonical_json_bytes(document) != data:
        raise ProvenanceV3Error("hard-token provenance JSON is not canonical")
    required = {
        "schemaVersion",
        "serializerVersion",
        "campaignPolicy",
        "campaignId",
        "allocationId",
        "candidate",
        "configIdentity",
        "route",
    }
    if set(document) != required:
        raise ProvenanceV3Error("hard-token provenance fields are incomplete or extra")
    if document["schemaVersion"] != 1 or document["serializerVersion"] != 1:
        raise ProvenanceV3Error("hard-token provenance version is unsupported")
    verify_campaign_policy(document["campaignPolicy"])
    _require_identifier(document["campaignId"])
    _require_identifier(document["allocationId"])
    candidate = document["candidate"]
    config = document["configIdentity"]
    route = document["route"]
    if set(candidate) != {"cliBuild", "binarySha256", "sourceCommitSha"}:
        raise ProvenanceV3Error("hard-token provenance candidate is invalid")
    _require_ascii(candidate["cliBuild"], 256)
    _require_sha256(candidate["binarySha256"])
    _require_commit(candidate["sourceCommitSha"])
    if set(config) != {"sourceKind", "generation", "managedProviderId", "configProjectionSha256"}:
        raise ProvenanceV3Error("hard-token provenance config identity is invalid")
    _require_ascii(config["sourceKind"], 128)
    if config["sourceKind"] != "resolved-managed-provider":
        raise ProvenanceV3Error("hard-token provenance config identity is invalid")
    _require_positive_int(config["generation"])
    _require_identifier(config["managedProviderId"])
    _require_sha256(config["configProjectionSha256"])
    isolation = route.get("toolIsolation") if isinstance(route, dict) else None
    if not isinstance(route, dict) or not isinstance(isolation, dict):
        raise ProvenanceV3Error("hard-token provenance route is invalid")
    if set(route) != {
        "routeId",
        "providerId",
        "providerFacingModel",
        "endpointSha256",
        "apiBackend",
        "credentialTransport",
        "authScheme",
        "maxFinalSerializedPayloadBytes",
        "maxOutputTokens",
        "conservativeRequestBoundTokens",
        "allocationTokenCeiling",
        "maxModelCalls",
        "textOnly",
        "remoteContextForbidden",
        "multimodalForbidden",
        "redirectDisabled",
        "retryDisabled",
        "toolIsolation",
    }:
        raise ProvenanceV3Error("hard-token provenance route is invalid")
    if set(isolation) != {
        "authProviderHelpersDisabled",
        "terminalDisabled",
        "externalMcpDisabled",
        "hooksDisabled",
        "pluginsDisabled",
        "lspDisabled",
        "workflowsDisabled",
        "schedulerDisabled",
        "protectedAuthorityFs",
        "workspaceFsConfined",
        "samplerTransportRetriesDisabled",
        "allowedToolIds",
    }:
        raise ProvenanceV3Error("hard-token provenance tool isolation is invalid")
    _require_identifier(route["routeId"])
    _require_identifier(route["providerId"])
    if config["managedProviderId"] != route["providerId"]:
        raise ProvenanceV3Error("hard-token provenance provider binding is invalid")
    _require_ascii(route["providerFacingModel"], 256)
    _require_sha256(route["endpointSha256"])
    payload_bytes = _require_positive_int(route["maxFinalSerializedPayloadBytes"])
    output_tokens = _require_positive_int(route["maxOutputTokens"])
    conservative_bound = _require_positive_int(route["conservativeRequestBoundTokens"])
    allocation_ceiling = _require_positive_int(route["allocationTokenCeiling"])
    _require_positive_int(route["maxModelCalls"])
    if (
        route["apiBackend"] not in {"chat_completions", "responses", "messages"}
        or route["credentialTransport"] != "fd_v1"
        or route["textOnly"] is not True
        or route["remoteContextForbidden"] is not True
        or route["multimodalForbidden"] is not True
        or route["redirectDisabled"] is not True
        or route["retryDisabled"] is not True
    ):
        raise ProvenanceV3Error("hard-token provenance route is invalid")
    if (
        payload_bytes + output_tokens > conservative_bound
        or conservative_bound > allocation_ceiling
        or allocation_ceiling > ALLOCATABLE_TOKEN_CEILING
    ):
        raise ProvenanceV3Error("hard-token provenance bound is invalid")
    canonical_auth_header_names(route["authScheme"])
    allowed = isolation["allowedToolIds"]
    if (
        isolation["authProviderHelpersDisabled"] is not True
        or isolation["terminalDisabled"] is not True
        or isolation["externalMcpDisabled"] is not True
        or isolation["hooksDisabled"] is not True
        or isolation["pluginsDisabled"] is not True
        or isolation["lspDisabled"] is not True
        or isolation["workflowsDisabled"] is not True
        or isolation["schedulerDisabled"] is not True
        or isolation["protectedAuthorityFs"] is not True
        or isolation["workspaceFsConfined"] is not True
        or isolation["samplerTransportRetriesDisabled"] is not True
        or not isinstance(allowed, list)
        or not allowed
        or any(
            not isinstance(item, str)
            or not item.startswith("GrokBuild:")
            or len(item) <= len("GrokBuild:")
            or len(item) > 256
            or not item.isascii()
            or any(ord(char) < 32 or ord(char) == 127 for char in item)
            for item in allowed
        )
        or any(left >= right for left, right in zip(allowed, allowed[1:]))
    ):
        raise ProvenanceV3Error("hard-token provenance tool isolation is invalid")
    return document


def verify_v3_authority_projection(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProvenanceV3Error("v3 authority projection is invalid")
    if set(value) != {"authorityVersion", "provenance", "provenanceSha256"}:
        raise ProvenanceV3Error("v3 authority projection fields are incomplete or extra")
    if value["authorityVersion"] != 3:
        raise ProvenanceV3Error("v3 authority version is unsupported")
    if isinstance(value.get("provenance"), str):
        raise ProvenanceV3Error("v3 authority provenance must be a typed object")
    if not isinstance(value.get("provenance"), dict):
        raise ProvenanceV3Error("v3 authority provenance is invalid")
    canonical = canonical_json_bytes(value["provenance"])
    document = verify_canonical_provenance(canonical)
    digest = _require_sha256(value["provenanceSha256"])
    if sha256_hex(canonical) != digest:
        raise ProvenanceV3Error("v3 authority digest does not match canonical provenance")
    return document


def verify_golden_parity() -> None:
    document = verify_canonical_provenance(GOLDEN_CANONICAL.encode("ascii"))
    if sha256_hex(GOLDEN_CANONICAL.encode("ascii")) != GOLDEN_SHA256:
        raise ProvenanceV3Error("hard-token provenance digest does not match canonical bytes")
    if canonical_auth_header_names(document["route"]["authScheme"]) != ("authorization",):
        raise ProvenanceV3Error("hard-token provenance auth headers are not derived from the scheme")
