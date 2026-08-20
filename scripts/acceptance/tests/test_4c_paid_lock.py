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
    NATIVE_ENDPOINT_FREEZE_SHA256,
    canonical_cli_manifest,
    prepare_campaign_authority,
    swift_authorization_sidecar,
)
from scripts.acceptance.harness.candidate_runtime import EXPECTED_TEAM
from scripts.acceptance.harness.errors import HarnessError, PreflightError, SchemaError
from scripts.acceptance.harness.driver import new_chat, send_prompt
from scripts.acceptance.harness.preflight_v2 import (
    _blocking_official_inspect_warnings,
    _codesign_designated_requirement,
    _same_inspect_path,
    preflight as preflight_v2,
    require_4c_leased_runtime,
    require_4c_unlock_predicate,
    require_absolute_ceiling_support,
    require_runtime_floor,
)
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
OPENAI_ENDPOINT_SHA256 = hashlib.sha256(b"https://api.openai.com/v1").hexdigest()
OPENROUTER_ENDPOINT_SHA256 = hashlib.sha256(b"https://openrouter.ai/api/v1").hexdigest()
FIXTURE_PROVENANCE_SHA256 = "a" * 64


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
        self.assertIs(self.manifest["pricingConfirmed"], True)
        self.assertEqual(
            [packet["routeReceipt"]["kind"] for packet in self.manifest["packets"]],
            ["nativeXAI", "directProvider", "brokeredOpenRouter"],
        )
        self.assertTrue(all(packet["continuation"] is None for packet in self.manifest["packets"]))
        brokered = self.manifest["packets"][2]
        self.assertEqual(brokered["selectorModelID"], "deepseek-deepseek-v4-flash-0731")
        self.assertEqual(brokered["effectiveModelID"], "deepseek/deepseek-v4-flash-0731")
        self.assertEqual(brokered["routeReceipt"]["providerModelID"], "deepseek/deepseek-v4-flash-0731")
        self.assertEqual(brokered["hardBudget"]["route"]["model"], "deepseek/deepseek-v4-flash-0731")
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

    def test_unlock_predicate_passes_4c_and_fails_historical_fixtures(self) -> None:
        require_4c_unlock_predicate(self.manifest, source_path=MANIFEST)
        v2 = json.loads(V2_MANIFEST.read_text(encoding="utf-8"))
        v3 = json.loads(V3_MANIFEST.read_text(encoding="utf-8"))
        with self.assertRaisesRegex(PreflightError, "unlock predicate refused"):
            require_4c_unlock_predicate(v2, source_path=V2_MANIFEST)
        with self.assertRaisesRegex(PreflightError, "schemaVersion must be 4"):
            require_4c_unlock_predicate(v3, source_path=V3_MANIFEST)
        mutated = copy.deepcopy(self.manifest)
        mutated["campaignId"] = RUN_ID
        with self.assertRaisesRegex(PreflightError, "unlock predicate refused"):
            require_4c_unlock_predicate(mutated, source_path=MANIFEST)
        ceiling = inspect.getsource(require_absolute_ceiling_support)
        self.assertIn("require_4c_unlock_predicate", ceiling)
        self.assertNotIn("require_4c_paid_identity", ceiling)
        self.assertNotIn(FROZEN_CAMPAIGN_ID, ceiling)
        self.assertIn("cannot prove the absolute 4,000,000-token ceiling", ceiling)
        main = RUN_PY.read_text(encoding="utf-8")
        billable_main = main[main.index("if args.billable:") : main.index("def _cleanup")]
        version_four = billable_main[
            billable_main.index("if version == 4:") : billable_main.index("return _billable_4c(args)")
        ]
        self.assertIn("require_absolute_ceiling_support(manifest, source_path=args.manifest)", version_four)
        self.assertNotIn("require_absolute_ceiling_support()", version_four)
        version_three = billable_main[
            billable_main.index("if version == 3:") : billable_main.index("return _billable_v3(args)")
        ]
        self.assertIn("require_absolute_ceiling_support()", version_three)

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

    def test_send_ready_requires_confirmed_prices_and_no_continuation(self) -> None:
        require_4c_send_ready(self.manifest)
        mutated = copy.deepcopy(self.manifest)
        mutated["pricingConfirmed"] = False
        with self.assertRaisesRegex(HarnessError, "catalog prices are not campaign-confirmed"):
            require_4c_send_ready(mutated)
        continued = copy.deepcopy(self.manifest)
        continued["packets"][0]["continuation"] = {"group": "nope"}
        with self.assertRaisesRegex(HarnessError, "must not continue"):
            require_4c_send_ready(continued)

    def test_dry_run_plan_is_not_billable(self) -> None:
        plan = dry_run_plan(self.manifest)
        self.assertEqual(plan["mode"], "dry-run")
        self.assertEqual(plan["schemaVersion"], 4)
        self.assertIs(plan["billable"], False)
        self.assertIs(plan["pricingConfirmed"], True)
        self.assertIsNone(plan["continuation"])
        self.assertEqual(plan["launch"], "four-arg armed launch_installed")
        self.assertEqual(plan["campaignId"], FROZEN_CAMPAIGN_ID)
        self.assertEqual(
            [packet["routeKind"] for packet in plan["packets"]],
            ["nativeXAI", "directProvider", "brokeredOpenRouter"],
        )
        self.assertEqual(plan["packets"][1]["campaignConfirmed"], True)
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
        self.assertNotIn("endpointSHA256", encoded)
        self.assertNotIn("boundProvenanceSHA256", encoded)
        with tempfile.TemporaryDirectory() as directory:
            cli_path = Path(directory) / "hard-token-campaign.json"
            cli_path.write_bytes(json.dumps(cli, sort_keys=True, separators=(",", ":")).encode())
            sidecar = swift_authorization_sidecar(
                self.manifest,
                cli_path,
                Path(directory) / "ledger.json",
                provenance_sha256=FIXTURE_PROVENANCE_SHA256,
            )
        self.assertEqual(sidecar["schemaVersion"], 3)
        self.assertEqual(sidecar["runID"], RUN_ID)
        self.assertEqual(sidecar["campaignId"], FROZEN_CAMPAIGN_ID)
        self.assertNotEqual(sidecar["campaignId"], sidecar["runID"])
        self.assertEqual(sidecar["campaignTokenCeiling"], 20_000_000)
        self.assertEqual(sidecar["expectedCLIBuild"], EXPECTED_CLI_BUILD)
        native_route = sidecar["packets"][0]["route"]
        direct_route = sidecar["packets"][1]["route"]
        brokered_route = sidecar["packets"][2]["route"]
        self.assertEqual(NATIVE_ENDPOINT_FREEZE_SHA256, hashlib.sha256(b"nativeXAI").hexdigest())
        self.assertEqual(native_route["endpointSHA256"], NATIVE_ENDPOINT_FREEZE_SHA256)
        self.assertEqual(direct_route["endpointSHA256"], OPENAI_ENDPOINT_SHA256)
        self.assertEqual(brokered_route["endpointSHA256"], OPENROUTER_ENDPOINT_SHA256)
        for route in (native_route, direct_route, brokered_route):
            self.assertEqual(route["boundProvenanceSHA256"], FIXTURE_PROVENANCE_SHA256)
            self.assertNotIn(route["endpointSHA256"], V2_LIVE_BIND_HASHES)
            self.assertNotIn(route["boundProvenanceSHA256"], V2_LIVE_BIND_HASHES)
        self.assertIsNone(native_route["managedProviderID"])
        self.assertIsNone(native_route["authScheme"])
        self.assertEqual(direct_route["managedProviderID"], "grokbuild.saved.openai")
        self.assertEqual(direct_route["authScheme"], "bearer")
        self.assertEqual(brokered_route["managedProviderID"], "grokbuild.saved.openrouter")
        self.assertEqual(brokered_route["authScheme"], "bearer")
        sidecar_text = json.dumps(sidecar)
        for digest in V2_LIVE_BIND_HASHES:
            self.assertNotIn(digest, sidecar_text)

        mutated = copy.deepcopy(self.manifest)
        mutated["packets"][0]["routeReceipt"]["endpointIdentity"] = "https://api.x.ai/v1"
        with tempfile.TemporaryDirectory() as directory:
            cli_path = Path(directory) / "hard-token-campaign.json"
            cli_path.write_bytes(b"{}")
            with self.assertRaisesRegex(HarnessError, "must not invent an xAI host"):
                swift_authorization_sidecar(
                    mutated,
                    cli_path,
                    Path(directory) / "ledger.json",
                    provenance_sha256=FIXTURE_PROVENANCE_SHA256,
                )

    def test_receipt_authority_uses_product_campaign_id_and_native_freeze(self) -> None:
        from scripts.acceptance.harness.receipts_v2 import _expected_hard_budget_route

        native = self.manifest["packets"][0]
        route = _expected_hard_budget_route(
            self.manifest,
            native,
            {"boundProvenanceSHA256": FIXTURE_PROVENANCE_SHA256},
        )
        self.assertEqual(route["endpointSha256"], NATIVE_ENDPOINT_FREEZE_SHA256)
        self.assertEqual(route["boundProvenanceSha256"], FIXTURE_PROVENANCE_SHA256)
        self.assertNotIn("endpointSha256", native["hardBudget"]["route"])

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
            provenance = authority.candidate.provenance_sha256
            native_cli = cli["allocations"][0]["route"]
            self.assertEqual(native_cli["endpointSha256"], NATIVE_ENDPOINT_FREEZE_SHA256)
            self.assertEqual(cli["allocations"][1]["route"]["endpointSha256"], OPENAI_ENDPOINT_SHA256)
            self.assertEqual(cli["allocations"][2]["route"]["endpointSha256"], OPENROUTER_ENDPOINT_SHA256)
            self.assertEqual(native_cli["boundProvenanceSha256"], provenance)
            sidecar = json.loads(authority.authorization.read_text(encoding="utf-8"))
            self.assertEqual(sidecar["runID"], RUN_ID)
            self.assertEqual(sidecar["campaignId"], FROZEN_CAMPAIGN_ID)
            native_route = sidecar["packets"][0]["route"]
            self.assertEqual(native_route["endpointSHA256"], NATIVE_ENDPOINT_FREEZE_SHA256)
            self.assertEqual(sidecar["packets"][1]["route"]["endpointSHA256"], OPENAI_ENDPOINT_SHA256)
            self.assertEqual(sidecar["packets"][2]["route"]["endpointSHA256"], OPENROUTER_ENDPOINT_SHA256)
            self.assertEqual(native_route["boundProvenanceSHA256"], provenance)
            self.assertIsNone(native_route["managedProviderID"])
            self.assertIsNone(native_route["authScheme"])
            encoded = authority.authorization.read_text(encoding="utf-8") + authority.cli_manifest.read_text(
                encoding="utf-8"
            )
            for digest in V2_LIVE_BIND_HASHES:
                self.assertNotIn(digest, encoded)

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
        self.assertIn("one exact --candidate-selection authority", billed.stderr)
        self.assertNotIn("cannot prove the absolute 4,000,000-token ceiling", billed.stderr)

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
        self.assertIn("candidate_selection=args.candidate_selection", billable_4c)
        self.assertNotIn("resume_saved_task()", billable_4c)
        self.assertNotIn("launch_installed()", billable_4c)
        self.assertIn("launch_installed(", billable_4c)
        self.assertLess(
            billable_4c.index('send_prompt(packet["prompt"])'),
            billable_4c.index("wait_for_acp_startup_outcome"),
        )
        self.assertLess(
            billable_4c.index("wait_for_acp_startup_outcome"),
            billable_4c.index("send_may_be_live = True"),
        )
        self.assertLess(
            billable_4c.index("send_may_be_live = True"),
            billable_4c.index("wait_for_marker"),
        )
        ceiling = inspect.getsource(require_absolute_ceiling_support)
        self.assertIn("cannot prove the absolute 4,000,000-token ceiling", ceiling)
        self.assertNotIn(FROZEN_CAMPAIGN_ID, ceiling)
        self.assertNotIn("require_4c_paid_identity", ceiling)
        self.assertIn("require_4c_unlock_predicate", ceiling)
        with self.assertRaises(PreflightError):
            require_absolute_ceiling_support()
        with self.assertRaises(PreflightError):
            require_absolute_ceiling_support(json.loads(V3_MANIFEST.read_text(encoding="utf-8")), source_path=V3_MANIFEST)
        require_absolute_ceiling_support(self.manifest, source_path=MANIFEST)
        main = source[source.index("def main") : source.index("def _cleanup")]
        billable_main = main[main.index("if args.billable:") :]
        four_c = billable_main[
            billable_main.index("if version == 4:") : billable_main.index("return _billable_4c(args)")
        ]
        self.assertIn("require_absolute_ceiling_support(manifest, source_path=args.manifest)", four_c)

    def test_schema4_preflight_uses_leased_pager_not_official_105_floor(self) -> None:
        source = inspect.getsource(preflight_v2)
        self.assertIn("require_4c_leased_runtime", source)
        self.assertIn('manifest.get("schemaVersion") == 4', source)
        self.assertIn("require_runtime_floor()", source)
        floor = inspect.getsource(require_runtime_floor)
        self.assertIn("1.0.5+", floor)
        leased = inspect.getsource(require_4c_leased_runtime)
        self.assertIn("OFFICIAL_CLI_SHA256", leased)
        self.assertIn("STAGED_PAGER_SHA256", leased)
        self.assertIn("1.0.4", leased)
        self.assertIn("1.0.5 (8226242)", leased)
        self.assertNotIn(FROZEN_CAMPAIGN_ID, leased)
        with self.assertRaisesRegex(PreflightError, "1.0.5\\+"):
            require_runtime_floor("grok 1.0.4")

    def test_official_104_consent_inspect_warning_is_inert(self) -> None:
        consent = {
            "target": "configKey",
            "path": "consent",
            "kind": "unknown-field",
            "reason": "unrecognized config key",
        }
        self.assertFalse(_blocking_official_inspect_warnings([]))
        self.assertFalse(_blocking_official_inspect_warnings([consent]))
        self.assertTrue(_blocking_official_inspect_warnings("nope"))
        self.assertTrue(_blocking_official_inspect_warnings([{"kind": "parse"}]))
        self.assertTrue(_blocking_official_inspect_warnings([consent, {"kind": "parse"}]))

    def test_inspect_project_root_trailing_slash_is_the_same_workspace(self) -> None:
        repo = REPO
        self.assertTrue(_same_inspect_path(str(repo), repo))
        self.assertTrue(_same_inspect_path(str(repo) + "/", repo))
        self.assertFalse(_same_inspect_path(str(repo.parent), repo))
        self.assertFalse(_same_inspect_path("", repo))

    def test_codesign_designated_requirement_reads_stdout(self) -> None:
        source = inspect.getsource(_codesign_designated_requirement)
        self.assertIn("result.stdout", source)
        self.assertIn("startswith(\"designated =>\")", source)
        self.assertNotIn("return _requirement(blob)", source)

    def test_new_chat_skips_build_mode_on_idle_tabs(self) -> None:
        source = inspect.getsource(new_chat)
        self.assertIn("_find_named(\"Message composer\", role=\"textfield\")", source)
        self.assertIn("_find_named(\"Agent mode\")", source)
        self.assertIn("Default currentMode is already Agent", source)
        self.assertIn("select_build_mode()", source)

    def test_menu_clicks_fall_back_to_headed_delivery(self) -> None:
        from scripts.acceptance.harness.driver import _click_ref
        source = inspect.getsource(_click_ref)
        self.assertIn('["click", ref]', source)
        self.assertIn('["--headed", "click", ref]', source)

    def test_send_prompt_types_then_sends_without_ax_clear(self) -> None:
        source = inspect.getsource(send_prompt)
        self.assertIn("Do not AX-clear", source)
        self.assertNotIn('["clear", ref]', source)
        self.assertNotIn("_click_ref(ref)", source)
        self.assertIn('["focus", ref]', source)
        self.assertIn("_type_into(ref, prompt)", source)
        self.assertIn("disabled", source)

    def test_wait_for_acp_startup_outcome_races_stop_against_named_failure(self) -> None:
        from scripts.acceptance.harness.driver import wait_for_acp_startup_outcome
        source = inspect.getsource(wait_for_acp_startup_outcome)
        self.assertIn("grok-acp-error-banner", source)
        self.assertIn("ACP startup failed", source)
        self.assertIn("Stop turn", source)
        self.assertIn("do not wait for first stdout before initialize", source)
        self.assertIn("AXFrontmost timeout is a driver flake", source)
        self.assertIn("continue", source)

    def test_select_model_picks_option_without_effort_restart(self) -> None:
        from scripts.acceptance.harness.driver import _open_model_menu, select_model
        source = inspect.getsource(select_model)
        opener = inspect.getsource(_open_model_menu)
        self.assertIn("grok-model-effort-selector", opener)
        self.assertIn("Do not click Low", source)
        self.assertNotIn("_click_menu_item(\"Low\")", source)
        self.assertIn("grok-model-option-", source)
        self.assertIn("if label in current:", source)

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
