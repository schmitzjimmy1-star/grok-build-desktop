from __future__ import annotations

import inspect
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.acceptance.harness.candidate_install import (
    DEFAULT_RUNTIME_ROOT,
    install_signed_candidate,
    rollback_signed_install,
)
from scripts.acceptance.harness.candidate_process_driver import (
    OFFICIAL_CLI,
    OFFICIAL_CLI_SHA256,
    STAGED_PAGER_SHA256,
    official_cli_sha256,
    require_staged_selection,
    sha256_file,
)
from scripts.acceptance.harness.candidate_runtime import validate_runtime_selection
from scripts.acceptance.harness.errors import HarnessError, PreflightError
from scripts.acceptance.harness.preflight_v2 import require_absolute_ceiling_support


REPO = Path(__file__).resolve().parents[3]
SELECTION_ENV = os.environ.get("GROKBUILD_SLICE4B3_RUNTIME_SELECTION") or ""


def _empty_process_zero() -> list[dict]:
    empty = {"GrokBuild": [], "grok": [], "agent-desktop": [], "owned-browser": []}
    return [
        {"at": "2026-08-19T17:00:00-0500", "pids": dict(empty)},
        {"at": "2026-08-19T17:00:05-0500", "pids": dict(empty)},
    ]


class Slice4B6InstallContracts(unittest.TestCase):
    def test_default_runtime_root_is_owner_private_application_support(self) -> None:
        self.assertEqual(
            DEFAULT_RUNTIME_ROOT,
            Path.home() / "Library" / "Application Support" / "GrokBuild" / "candidate-runtime",
        )
        self.assertNotIn(".grok", DEFAULT_RUNTIME_ROOT.parts)

    def test_install_refuses_anything_under_grok_home(self) -> None:
        with self.assertRaisesRegex(HarnessError, r"~/.grok"):
            install_signed_candidate(Path("/tmp/missing-selection.json"), Path.home() / ".grok" / "bin")
        with self.assertRaisesRegex(HarnessError, r"~/.grok"):
            install_signed_candidate(
                Path("/tmp/missing-selection.json"),
                Path.home() / ".grok" / "candidate-runtime",
            )

    def test_rollback_refuses_missing_or_incomplete_process_zero(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            selection = Path(raw) / "runtime-selection.json"
            selection.write_text("{}")
            os.chmod(selection, 0o600)
            with self.assertRaisesRegex(HarnessError, "two empty process-zero"):
                rollback_signed_install(selection, process_zero_samples=[])
            with self.assertRaisesRegex(HarnessError, "two empty process-zero"):
                rollback_signed_install(
                    selection,
                    process_zero_samples=[{"at": "now", "pids": {"grok": [1]}}, {"at": "now", "pids": {"grok": []}}],
                )

    def test_rollback_refuses_identical_process_zero_timestamps(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            selection = Path(raw) / "runtime-selection.json"
            selection.write_text("{}")
            os.chmod(selection, 0o600)
            empty = {"GrokBuild": [], "grok": [], "agent-desktop": [], "owned-browser": []}
            duplicate = [
                {"at": "2026-08-19T17:53:24-0500", "pids": dict(empty)},
                {"at": "2026-08-19T17:53:24-0500", "pids": dict(empty)},
            ]
            with self.assertRaisesRegex(HarnessError, "distinct timestamps"):
                rollback_signed_install(selection, process_zero_samples=duplicate)

    def test_rollback_refuses_a_missing_selection(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            missing = Path(raw) / "runtime-selection.json"
            with self.assertRaisesRegex(HarnessError, "existing selection"):
                rollback_signed_install(missing, process_zero_samples=_empty_process_zero())

    def test_paid_unlock_and_billable_v3_stay_locked(self) -> None:
        with self.assertRaises(PreflightError):
            require_absolute_ceiling_support()
        source = inspect.getsource(require_absolute_ceiling_support)
        self.assertIn("cannot prove the absolute 4,000,000-token ceiling", source)
        run_source = (REPO / "scripts" / "acceptance" / "run.py").read_text()
        billable = run_source[run_source.index("def _billable_v3") : run_source.index("if __name__")]
        self.assertNotIn("resume_saved_task()", billable)
        self.assertNotIn("later unlock path", billable)
        self.assertIn("4B.4 continuation", billable)
        self.assertIn("governed_fresh_process_load", billable)
        self.assertIn("launch_installed()", billable)
        self.assertNotIn("runtime_selection_file=", billable)
        self.assertIn("require_absolute_ceiling_support()", run_source)

    def test_ordinary_resolver_source_never_scans_candidate_runtime(self) -> None:
        resolver = (REPO / "GrokBuild" / "Services" / "GrokCLIRuntimeAuthority.swift").read_text()
        lookup = resolver[
            resolver.index("enum GrokCLIRuntimeResolver") : resolver.index("enum GrokCandidateRuntimeAuthority")
        ]
        self.assertNotIn("candidate-runtime", lookup)
        self.assertNotIn("Application Support/GrokBuild/candidate", lookup)
        self.assertIn(".grok/bin/grok", lookup)
        self.assertIn("never scans", resolver)

    def test_signed_install_copies_and_rollbacks_when_source_is_present(self) -> None:
        if not SELECTION_ENV:
            self.skipTest("GROKBUILD_SLICE4B3_RUNTIME_SELECTION is unset")
        if os.environ.get("CI") or os.environ.get("GITHUB_ACTIONS") == "true":
            self.skipTest("signed pager install is owner-local")
        source = Path(SELECTION_ENV)
        selected = require_staged_selection(source)
        self.assertEqual(selected["binarySHA256"], STAGED_PAGER_SHA256)
        before = official_cli_sha256() if OFFICIAL_CLI.is_file() else None
        with tempfile.TemporaryDirectory() as raw:
            dest = Path(raw) / "candidate-runtime"
            os.mkdir(dest, 0o700)
            installed = install_signed_candidate(source, dest)
            self.assertEqual(installed, dest / "runtime-selection.json")
            self.assertEqual(stat.S_IMODE(installed.stat().st_mode), 0o600)
            validated = validate_runtime_selection(installed, expected_cli_build="1.0.5 (8226242)")
            self.assertEqual(validated.binary_sha256, STAGED_PAGER_SHA256)
            pager = Path(validated.candidate_path)
            self.assertNotEqual(pager.resolve(), OFFICIAL_CLI.resolve())
            self.assertNotEqual(os.stat(Path(selected["candidatePath"])).st_ino, os.stat(pager).st_ino)
            self.assertEqual(sha256_file(pager), STAGED_PAGER_SHA256)
            listing = subprocess.run(
                ["/usr/bin/xattr", "-l", str(pager)],
                check=False,
                capture_output=True,
                text=True,
            ).stdout
            self.assertNotIn("com.apple.quarantine", listing)
            with self.assertRaisesRegex(HarnessError, "must not pre-exist"):
                install_signed_candidate(source, dest)
            receipt = rollback_signed_install(installed, process_zero_samples=_empty_process_zero())
            self.assertTrue(receipt["runtimeSelectionRemoved"])
            self.assertTrue(receipt["candidateRetained"])
            self.assertTrue(receipt["officialCLIUntouched"])
            self.assertEqual(receipt["candidateBinarySHA256"], STAGED_PAGER_SHA256)
            self.assertFalse(installed.exists())
            self.assertTrue(pager.is_file())
            self.assertTrue((dest / "rollback-receipt-v1.json").is_file())
            if before is not None:
                self.assertEqual(official_cli_sha256(), before)
                self.assertEqual(before, OFFICIAL_CLI_SHA256)
            reinstalled = install_signed_candidate(source, dest)
            self.assertTrue(reinstalled.is_file())
            rollback_signed_install(reinstalled, process_zero_samples=_empty_process_zero())
