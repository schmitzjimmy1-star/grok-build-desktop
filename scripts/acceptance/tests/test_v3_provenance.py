from __future__ import annotations

import json
import unittest

from scripts.acceptance.harness.provenance_v3 import (
    GOLDEN_CANONICAL,
    GOLDEN_SHA256,
    ProvenanceV3Error,
    canonical_auth_header_names,
    canonical_json_bytes,
    sha256_hex,
    verify_canonical_provenance,
    verify_golden_parity,
    verify_v3_authority_projection,
)


class Slice4B3ProvenanceV3Contracts(unittest.TestCase):
    def test_golden_bytes_and_digest_match_rust_and_swift(self) -> None:
        verify_golden_parity()
        self.assertEqual(sha256_hex(GOLDEN_CANONICAL.encode("ascii")), GOLDEN_SHA256)
        document = verify_canonical_provenance(GOLDEN_CANONICAL.encode("ascii"))
        self.assertEqual(canonical_json_bytes(document), GOLDEN_CANONICAL.encode("ascii"))

    def test_historical_v2_policy_and_noncanonical_bytes_are_refused(self) -> None:
        old_policy = GOLDEN_CANONICAL.replace("20000000", "4000000")
        extra = GOLDEN_CANONICAL[:-1] + ',"opaqueDigest":"nope"}'
        whitespace = GOLDEN_CANONICAL.replace(":", ": ", 1)
        reordered = '{"schemaVersion":1,' + GOLDEN_CANONICAL[GOLDEN_CANONICAL.find('"serializerVersion"') :]
        for hostile in (old_policy, extra, whitespace, reordered):
            with self.assertRaises(ProvenanceV3Error):
                verify_canonical_provenance(hostile.encode("ascii"))

    def test_auth_headers_are_derived_from_scheme_not_caller_names(self) -> None:
        self.assertEqual(canonical_auth_header_names("bearer"), ("authorization",))
        self.assertEqual(canonical_auth_header_names("x_api_key"), ("x-api-key",))
        self.assertEqual(
            canonical_auth_header_names("bearer_and_x_api_key"),
            ("authorization", "x-api-key"),
        )
        with self.assertRaises(ProvenanceV3Error):
            canonical_auth_header_names("oauth")

    def test_v3_authority_projection_is_exactly_three_typed_fields(self) -> None:
        provenance = json.loads(GOLDEN_CANONICAL)
        authority = {
            "authorityVersion": 3,
            "provenance": provenance,
            "provenanceSha256": GOLDEN_SHA256,
        }
        document = verify_v3_authority_projection(authority)
        self.assertEqual(document["configIdentity"]["managedProviderId"], "openrouter")
        extra = dict(authority)
        extra["authHeaderNames"] = ["authorization"]
        missing = {"authorityVersion": 3, "provenanceSha256": GOLDEN_SHA256}
        wrong_version = dict(authority)
        wrong_version["authorityVersion"] = 2
        digest_mismatch = dict(authority)
        digest_mismatch["provenanceSha256"] = "0" * 64
        string_duplicate = {
            "authorityVersion": 3,
            "provenance": GOLDEN_CANONICAL,
            "provenanceSha256": GOLDEN_SHA256,
        }
        for hostile in (extra, missing, wrong_version, digest_mismatch, string_duplicate):
            with self.assertRaises(ProvenanceV3Error):
                verify_v3_authority_projection(hostile)

    def test_source_kind_provider_binding_bool_integers_and_del_are_refused(self) -> None:
        wrong_kind = GOLDEN_CANONICAL.replace("resolved-managed-provider", "toml")
        provider_mismatch = GOLDEN_CANONICAL.replace(
            '"managedProviderId":"openrouter"',
            '"managedProviderId":"other-provider"',
        )
        extra_route = GOLDEN_CANONICAL.replace(
            '"routeId":"route-1"',
            '"authHeaderName":"authorization","routeId":"route-1"',
        )
        bool_int = GOLDEN_CANONICAL.replace('"maxModelCalls":1', '"maxModelCalls":true')
        del_build = GOLDEN_CANONICAL.replace("1.0.5 (003f955)", "1.0.5\x7f")
        for hostile in (wrong_kind, provider_mismatch, extra_route, bool_int, del_build):
            with self.assertRaises(ProvenanceV3Error):
                verify_canonical_provenance(hostile.encode("ascii"))


if __name__ == "__main__":
    unittest.main()
