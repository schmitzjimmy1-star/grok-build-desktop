from __future__ import annotations

import copy
import hashlib
import inspect
import json
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.acceptance.harness.authority_4c import (
    canonical_cli_manifest,
    prepare_campaign_authority,
    swift_authorization_sidecar,
)
from scripts.acceptance.harness.candidate_runtime import EXPECTED_TEAM
from scripts.acceptance.harness.errors import HarnessError, PreflightError, SchemaError
from scripts.acceptance.harness.preflight_v2 import require_absolute_ceiling_support
from scripts.acceptance.harness.schema_4c import (
    EXPECTED_CLI_BUILD,
    FROZEN_CAMPAIGN_ID,
    FROZEN_MANIFEST_SHA256,
    committed_identity_digest,
    dry_run_plan,
    load_manifest,
    require_4c_paid_identity,
    require_4c_send_ready,
    validate_4c_document,
)


REPO = Path(__file__).resolve().parents[3]
ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "manifests" / "official-provider-slice4c-paid.json"
V2_MANIFEST = ROOT / "manifests" / "official-provider-slice4-v2.json"
V3_MANIFEST = ROOT / "manifests" / "fresh-process-continuation-v3.json"
RUN_PY = ROOT / "run.py"
RUN_ID = "20260819T210000Z"
V2_LIVE_BIND_HASHES = {
    "ebb5dec7d8c69fa5c35a5bfa5ae24d96b7d763c30f68df44bceb7195465ce82b",
    "9f7ee2a1f4fae3348dec514ebf94adfe788c7c6ecabccd6eb1b59a1dea057ec5",
    "ee0291cefbb5b6136483fb38ba9efe9264f9b685d5006c273e293a54b43a1883",
    "8d01aff0b5e92c6e5c0b3c3584a3bf00ac11f1477cd1ae12c8ffcf2034b770ba",
    "5c1332d5f9242f304584f5dca3e53a8afe9d1e0c9ea153e0ab73f27e4f341bce",
    "e1e898291e8fe317aa3ff1b147d4503edd4af18808fa935da852af28a61209f1",
}


class Slice4CPaidLockContracts(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = load_manifest(MANIFEST, run_id=RUN_ID)

    def test_committed_identity_hash_matches_the_pinned_constant(self) -> None:
        self.assertEqual(committed_identity_digest(path=MANIFEST), FROZEN_MANIFEST_SHA256)
        self.assertEqual(self.manifest["campaignId"], FROZEN_CAMPAIGN_ID)
        self.assertNotEqual(self.manifest["campaignId"], self.manifest["runId"])
        self.assertEqual(self.manifest["expectedCLIBuild"], EXPECTED_CLI_BUILD)
        self.assertEqual(self.manifest["campaignTokenCeiling"], 20_000_000)
        self.assertEqual(self.manifest["plannedTokenMaximum"], 19_000_000)
        self.assertEqual(self.manifest["emergencyReserveTokens"], 1_000_000)
        self.assertIs(self.manifest["pricingConfirmed"], False)
        self.assertEqual(
            [packet["routeReceipt"]["kind"] for packet in self.manifest["packets"]],
            ["nativeXAI", "directProvider", "brokeredOpenRouter"],
        )
        self.assertTrue(all(packet["continuation"] is None for packet in self.manifest["packets"]))
        text = MANIFEST.read_text(encoding="utf-8")
        for digest in V2_LIVE_BIND_HASHES:
            self.assertNotIn(digest, text)

    def test_v2_and_v3_fixtures_stay_historical(self) -> None:
        v2 = json.loads(V2_MANIFEST.read_text(encoding="utf-8"))
        v3 = json.loads(V3_MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(v2["schemaVersion"], 2)
        self.assertEqual(v2["campaignTokenCeiling"], 4_000_000)
        self.assertEqual(v2["expectedCLIBuild"], "1.0.5 (03a28d4)")
        self.assertEqual(v3["schemaVersion"], 3)
        self.assertNotIn("campaignId", v3)
        self.assertNotEqual(v2["schemaVersion"], 4)
        self.assertNotEqual(v3["schemaVersion"], 4)

    def test_wrong_campaign_id_is_refused(self) -> None:
        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["campaignId"] = RUN_ID
        with self.assertRaisesRegex(SchemaError, "frozen product id"):
            validate_4c_document(raw)
        mutated = copy.deepcopy(self.manifest)
        mutated["campaignId"] = RUN_ID
        with self.assertRaisesRegex(SchemaError, "frozen product id"):
            require_4c_paid_identity(mutated)

    def test_wrong_identity_hash_is_refused(self) -> None:
        raw = json.loads(MANIFEST.read_text(encoding="utf-8"))
        raw["packets"][0]["id"] = "S4C-MUTATED"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "mutated.json"
            path.write_text(json.dumps(raw), encoding="utf-8")
            with self.assertRaisesRegex(SchemaError, "identity hash"):
                load_manifest(path, run_id=RUN_ID)
            with self.assertRaisesRegex(SchemaError, "identity hash"):
                require_4c_paid_identity(self.manifest, source_path=path)

    def test_wrong_packet_order_is_refused(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["packets"][0], mutated["packets"][1] = mutated["packets"][1], mutated["packets"][0]
        with self.assertRaisesRegex(SchemaError, "nativeXAI then directProvider then brokeredOpenRouter"):
            require_4c_paid_identity(mutated)

    def test_send_ready_stays_locked_on_unconfirmed_prices(self) -> None:
        with self.assertRaisesRegex(HarnessError, "catalog prices are not campaign-confirmed"):
            require_4c_send_ready(self.manifest)
        mutated = copy.deepcopy(self.manifest)
        mutated["pricingConfirmed"] = True
        mutated["packets"][0]["continuation"] = {"group": "nope"}
        with self.assertRaisesRegex(HarnessError, "must not continue"):
            require_4c_send_ready(mutated)

    def test_dry_run_plan_is_not_billable(self) -> None:
        plan = dry_run_plan(self.manifest)
        self.assertEqual(plan["mode"], "dry-run")
        self.assertEqual(plan["schemaVersion"], 4)
        self.assertIs(plan["billable"], False)
        self.assertIs(plan["pricingConfirmed"], False)
        self.assertIsNone(plan["continuation"])
        self.assertEqual(plan["launch"], "four-arg armed launch_installed")
        self.assertEqual(plan["campaignId"], FROZEN_CAMPAIGN_ID)
        self.assertEqual(
            [packet["routeKind"] for packet in plan["packets"]],
            ["nativeXAI", "directProvider", "brokeredOpenRouter"],
        )
        self.assertEqual(plan["packets"][1]["campaignConfirmed"], False)
        self.assertIsNone(plan["packets"][0]["campaignConfirmed"])

    def test_cli_authority_uses_frozen_campaign_id_not_run_id(self) -> None:
        cli = canonical_cli_manifest(self.manifest)
        self.assertEqual(cli["campaignId"], FROZEN_CAMPAIGN_ID)
        self.assertNotEqual(cli["campaignId"], self.manifest["runId"])
        self.assertEqual(cli["campaignPolicy"]["absoluteTokenCeiling"], 20_000_000)
        self.assertEqual(cli["campaignPolicy"]["allocatableTokenCeiling"], 19_000_000)
        self.assertEqual(cli["campaignPolicy"]["unreachableReserveTokens"], 1_000_000)
        self.assertEqual(cli["candidateExpectation"]["cliBuild"], EXPECTED_CLI_BUILD)
        encoded = json.dumps(cli)
        for digest in V2_LIVE_BIND_HASHES:
            self.assertNotIn(digest, encoded)
        self.assertNotIn("endpointSha256", encoded)
        self.assertNotIn("boundProvenanceSha256", encoded)
        with tempfile.TemporaryDirectory() as directory:
            cli_path = Path(directory) / "hard-token-campaign.json"
            cli_path.write_bytes(json.dumps(cli, sort_keys=True, separators=(",", ":")).encode())
            sidecar = swift_authorization_sidecar(self.manifest, cli_path, Path(directory) / "ledger.json")
        self.assertEqual(sidecar["schemaVersion"], 3)
        self.assertEqual(sidecar["runID"], RUN_ID)
        self.assertEqual(sidecar["campaignId"], FROZEN_CAMPAIGN_ID)
        self.assertNotEqual(sidecar["campaignId"], sidecar["runID"])
        self.assertEqual(sidecar["campaignTokenCeiling"], 20_000_000)
        self.assertEqual(sidecar["expectedCLIBuild"], EXPECTED_CLI_BUILD)
        self.assertIsNone(sidecar["packets"][0]["route"]["managedProviderID"])
        self.assertEqual(sidecar["packets"][1]["route"]["managedProviderID"], "grokbuild.saved.openai")
        self.assertEqual(sidecar["packets"][2]["route"]["managedProviderID"], "grokbuild.saved.openrouter")

    def test_prepare_writes_private_four_arg_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            selection, signature_probe = self._candidate_selection(Path(directory))
            authority = prepare_campaign_authority(
                self.manifest,
                candidate_selection=selection,
                root=Path(directory),
                signature_probe=signature_probe,
            )
            self.assertEqual(stat.S_IMODE(authority.directory.stat().st_mode), 0o700)
            for path in (authority.cli_manifest, authority.ledger, authority.authorization, authority.runtime_selection):
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            cli = json.loads(authority.cli_manifest.read_text(encoding="utf-8"))
            self.assertEqual(cli["campaignId"], FROZEN_CAMPAIGN_ID)
            self.assertNotEqual(cli["campaignId"], RUN_ID)
            sidecar = json.loads(authority.authorization.read_text(encoding="utf-8"))
            self.assertEqual(sidecar["runID"], RUN_ID)
            self.assertEqual(sidecar["campaignId"], FROZEN_CAMPAIGN_ID)

    def test_prepare_refuses_a_run_id_used_as_campaign_id(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["campaignId"] = mutated["runId"]
        with tempfile.TemporaryDirectory() as directory:
            selection, signature_probe = self._candidate_selection(Path(directory))
            with self.assertRaisesRegex(HarnessError, "non-frozen campaignId"):
                prepare_campaign_authority(
                    mutated,
                    candidate_selection=selection,
                    root=Path(directory),
                    signature_probe=signature_probe,
                )

    def test_schema3_billable_still_cannot_send(self) -> None:
        result = subprocess.run(
            [
                "python3",
                str(RUN_PY),
                "--manifest",
                str(V3_MANIFEST),
                "--run-id",
                "20260819T101401Z",
                "--billable",
            ],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("cannot prove the absolute 4,000,000-token ceiling", result.stderr)
        self.assertNotIn("legacy v1 billable execution is retired", result.stderr)

    def test_schema4_dry_run_and_billable_lock(self) -> None:
        dry = subprocess.run(
            ["python3", str(RUN_PY), "--manifest", str(MANIFEST), "--run-id", RUN_ID],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(dry.returncode, 0, dry.stdout + dry.stderr)
        plan = json.loads(dry.stdout)
        self.assertEqual(plan["schemaVersion"], 4)
        self.assertIs(plan["billable"], False)
        self.assertEqual(plan["campaignId"], FROZEN_CAMPAIGN_ID)
        self.assertEqual(plan["campaignTokenCeiling"], 20_000_000)
        billed = subprocess.run(
            [
                "python3",
                str(RUN_PY),
                "--manifest",
                str(MANIFEST),
                "--run-id",
                RUN_ID,
                "--billable",
            ],
            cwd=REPO,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(billed.returncode, 2, billed.stdout + billed.stderr)
        self.assertIn("cannot prove the absolute 4,000,000-token ceiling", billed.stderr)
        self.assertNotIn("catalog prices are not campaign-confirmed", billed.stderr)

    def test_billable_v3_stays_unarmed_and_4c_uses_four_arg_launch(self) -> None:
        source = RUN_PY.read_text(encoding="utf-8")
        billable_v3 = source[source.index("def _billable_v3") : source.index("if __name__")]
        self.assertNotIn("resume_saved_task()", billable_v3)
        self.assertNotIn("later unlock path", billable_v3)
        self.assertIn("4B.4 continuation", billable_v3)
        self.assertIn("launch_installed()", billable_v3)
        self.assertNotIn("runtime_selection_file=", billable_v3)
        billable_4c = source[source.index("def _billable_4c") : source.index("def _billable_v2")]
        self.assertIn("runtime_selection_file=", billable_4c)
        self.assertIn("require_4c_send_ready(manifest)", billable_4c)
        self.assertIn("prepare_campaign_authority_4c", billable_4c)
        self.assertNotIn("resume_saved_task()", billable_4c)
        self.assertNotIn("launch_installed()", billable_4c)
        self.assertIn("launch_installed(", billable_4c)
        ceiling = inspect.getsource(require_absolute_ceiling_support)
        self.assertIn("cannot prove the absolute 4,000,000-token ceiling", ceiling)
        self.assertNotIn(FROZEN_CAMPAIGN_ID, ceiling)
        self.assertNotIn("require_4c_paid_identity", ceiling)
        with self.assertRaises(PreflightError):
            require_absolute_ceiling_support()
        main = source[source.index("def main") : source.index("def _cleanup")]
        billable_main = main[main.index("if args.billable:") :]
        four_c = billable_main[
            billable_main.index("if version == 4:") : billable_main.index("return _billable_4c(args)")
        ]
        self.assertIn("require_absolute_ceiling_support()", four_c)

    def _candidate_selection(self, root: Path):
        runtime_root = root / "runtime"
        runtime_root.mkdir(mode=0o700)
        candidate_bytes = b"signed-candidate-fixture-4c"
        binary_sha = hashlib.sha256(candidate_bytes).hexdigest()
        digest = runtime_root / binary_sha
        digest.mkdir(mode=0o700)
        candidate = digest / "grok"
        candidate.write_bytes(candidate_bytes)
        candidate.chmod(0o700)
        requirement = 'identifier "com.grokbuild.fixture" and anchor apple generic'
        provenance = digest / "candidate-provenance.json"
        source_sha = EXPECTED_CLI_BUILD.split("(", 1)[1].split(")", 1)[0]
        source_sha = source_sha + "0" * (40 - len(source_sha))
        provenance.write_text(json.dumps({
            "schemaVersion": 1,
            "source": {
                "officialBaseSHA": "1" * 40,
                "upstreamReplayBaseSHA": "2" * 40,
                "forkSourceSHA": source_sha,
                "sourceRev": "3" * 40,
                "cargoLockSHA256": "4" * 64,
            },
            "toolchain": {
                "rustVersion": "rustc 1.94.0 (fixture)",
                "cargoVersion": "cargo 1.94.0 (fixture)",
                "dotslashVersion": "DotSlash 0.5.7",
                "rustcSHA256": "5" * 64,
                "cargoSHA256": "6" * 64,
                "dotslashSHA256": "7" * 64,
                "targetTriple": "aarch64-apple-darwin",
                "architecture": "arm64",
            },
            "build": {
                "preBuildCommand": [
                    "cargo", "clean", "--target-dir", "<candidate-target>", "--profile",
                    "release-dist", "-p", "xai-grok-pager-bin",
                ],
                "command": [
                    "cargo", "build", "--locked", "--profile", "release-dist", "-p",
                    "xai-grok-pager-bin", "--features", "release-dist",
                ],
                "environment": {
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
                },
                "profile": "release-dist",
                "package": "xai-grok-pager-bin",
                "features": ["release-dist"],
            },
            "binary": {
                "artifactName": "xai-grok-pager",
                "sha256": binary_sha,
                "sizeBytes": len(candidate_bytes),
                "architecture": "arm64",
                "expectedVersionWithCommit": EXPECTED_CLI_BUILD,
                "expectedACPCLIBuild": EXPECTED_CLI_BUILD,
                "observedVersionWithCommit": EXPECTED_CLI_BUILD,
            },
            "signing": {
                "state": "signed",
                "strictVerification": True,
                "teamIdentifier": EXPECTED_TEAM,
                "designatedRequirement": requirement,
            },
        }, sort_keys=True, separators=(",", ":")), encoding="utf-8")
        provenance.chmod(0o600)
        selection = root / "candidate-selection.json"
        selection.write_text(json.dumps({
            "schemaVersion": 1,
            "runtimeRoot": str(runtime_root),
            "candidatePath": str(candidate),
            "provenancePath": str(provenance),
            "provenanceSHA256": hashlib.sha256(provenance.read_bytes()).hexdigest(),
        }, sort_keys=True, separators=(",", ":")), encoding="utf-8")
        selection.chmod(0o600)
        return selection, lambda _: (EXPECTED_TEAM, requirement, "arm64")


if __name__ == "__main__":
    unittest.main()
