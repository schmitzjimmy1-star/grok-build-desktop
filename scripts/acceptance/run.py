#!/usr/bin/env python3
"""GrokBuild agentic acceptance harness.

Dry-run is the default. Pass --billable for fresh provider Sends after preflight.
Never prints credentials or response bodies. Never fakes ACP or guesses cleanup IDs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from harness.cleanup import require_exact_ids
from harness.authority_v2 import prepare_campaign_authority, retain_campaign_authority
from harness.authority_4c import prepare_campaign_authority as prepare_campaign_authority_4c
from harness.schema_4c import (
    dry_run_plan as dry_run_plan_4c,
    load_manifest as load_manifest_4c,
    require_4c_paid_identity,
    require_4c_send_ready,
)
from harness.driver import (
    capture_identities,
    close_current_session,
    governed_fresh_process_load,
    launch_installed,
    new_chat,
    quit_installed,
    restore_continuation,
    resume_saved_task,
    select_workspace,
    select_model,
    send_prompt,
    stop_turn,
    wait_for_terminal_checkpoint,
    wait_for_marker,
    wait_for_stop_control,
)
from harness.errors import HarnessError
from harness.evidence import extract_receipt
from harness.evidence_v2 import (
    attempt_started,
    cleanup_receipt,
    extract_terminal,
    reject_terminal,
    terminal_failure,
)
from harness.fixture import run_fixture
from harness.handoff import HandoffContext, render_handoff, validate_handoff
from harness.preflight import preflight, two_process_zero_samples
from harness.receipts import evaluate, load_ledger
from harness.redaction import redact_value, safe_print
from harness.schema import dry_run_plan as dry_run_plan_v1, load_manifest as load_manifest_v1, require_live_run_id as require_live_run_id_v1
from harness.schema_v2 import dry_run_plan as dry_run_plan_v2, load_manifest as load_manifest_v2, require_live_run_id as require_live_run_id_v2
from harness.schema_v3 import dry_run_plan as dry_run_plan_v3, load_manifest as load_manifest_v3
from harness.receipts_v2 import (
    append_row as append_row_v2,
    evaluate as evaluate_v2,
    evaluate_prefix as evaluate_prefix_v2,
    load_ledger as load_ledger_v2,
)
from harness.receipts_v3 import (
    append_row as append_row_v3,
    evaluate_fresh_process_continuation,
    load_ledger as load_ledger_v3,
)

DEFAULT_MANIFEST = ROOT / "manifests" / "installed-three-route-v1.json"
DEFAULT_LEDGER = Path("/tmp/grokbuild-s5-ledger.jsonl")
REPO = Path("/Users/jimmyschmitz/Desktop/Projects/MCP Servers/Grok Build/grok-build-desktop")
TRANSCRIPTS = Path.home() / "Library/Application Support/GrokBuild/Transcripts"
INSTALLED_PROVIDER_HELPER = Path("/Applications/GrokBuild.app/Contents/MacOS/GrokBuildProviderAuthHelper")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="GrokBuild agentic acceptance harness")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--billable", action="store_true", help="Allow fresh provider Sends after preflight")
    parser.add_argument("--run-id", dest="run_id")
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER)
    parser.add_argument("--candidate-selection", type=Path)
    parser.add_argument("--cleanup", action="store_true")
    parser.add_argument("--ids-from-ledger", type=Path)
    parser.add_argument("--guessed-id", help=argparse.SUPPRESS)
    parser.add_argument("--check-handoff", type=Path)
    parser.add_argument("--evaluate-ledger", action="store_true")
    args = parser.parse_args(argv)
    args.ledger = args.ledger.expanduser().resolve(strict=False)
    if args.ids_from_ledger is not None:
        args.ids_from_ledger = args.ids_from_ledger.expanduser().resolve(strict=False)
    if args.candidate_selection is not None:
        # Preserve the leaf exactly so validate_runtime_selection can enforce
        # O_NOFOLLOW. `resolve()` here would erase a hostile selection symlink.
        args.candidate_selection = Path(os.path.abspath(args.candidate_selection.expanduser()))

    try:
        if args.fixture:
            return run_fixture(args.fixture)
        if args.check_handoff:
            validate_handoff(args.check_handoff.read_text(encoding="utf-8"))
            safe_print("handoff accepted")
            return 0
        if args.cleanup:
            return _cleanup(args)
        if args.evaluate_ledger:
            version = _manifest_version(args.manifest)
            manifest = _load_manifest(args.manifest, args.run_id, version)
            if version == 4:
                raise HarnessError("4C ledger evaluation remains locked until paid unlock")
            if version == 3:
                summary = evaluate_fresh_process_continuation(
                    manifest["packets"],
                    load_ledger_v3(args.ledger),
                )
            elif version == 2:
                summary = evaluate_v2(manifest, load_ledger_v2(args.ledger))
            else:
                summary = evaluate(manifest, load_ledger(args.ledger))
            safe_print(json.dumps(redact_value("summary", summary)))
            return 0
        if args.billable:
            if not args.run_id:
                raise HarnessError("billable mode requires --run-id")
            version = _manifest_version(args.manifest)
            from harness.preflight_v2 import require_absolute_ceiling_support, require_runtime_floor
            if version == 4:
                # Schema-4 --billable is the locked 4C route-matrix executor.
                # The ceiling still wins before runtime discovery or Send.
                require_absolute_ceiling_support()
                return _billable_4c(args)
            if version == 3:
                # Schema-3 --billable is the 4B.4 continuation executor.
                # Paid 4C needs a separate armed route-matrix executor.
                # Refuse before runtime discovery or Send.
                require_absolute_ceiling_support()
                return _billable_v3(args)
            if version != 2:
                raise HarnessError("legacy v1 billable execution is retired; use the guarded v2 campaign")
            # This refusal is deliberately first. A locked paid campaign must not
            # start Grok even for version/catalog discovery.
            require_absolute_ceiling_support()
            require_runtime_floor()
            return _billable_v2(args)
        version = _manifest_version(args.manifest)
        manifest = _load_manifest(args.manifest, args.run_id, version)
        if version == 4:
            plan = dry_run_plan_4c(manifest)
        elif version == 3:
            plan = dry_run_plan_v3(manifest)
        elif version == 2:
            plan = dry_run_plan_v2(manifest)
        else:
            plan = dry_run_plan_v1(manifest)
        safe_print(json.dumps(redact_value("plan", plan), indent=2))
        return 0
    except HarnessError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


def _cleanup(args: argparse.Namespace) -> int:
    if args.ids_from_ledger is None:
        require_exact_ids([], None, guessed=False)
    receipts = _load_any_ledger(args.ids_from_ledger)
    ids = require_exact_ids(receipts, _ids_from_receipts(receipts), guessed=bool(args.guessed_id))
    safe_print(json.dumps({"cleanupIdentities": ids, "executed": False}))
    safe_print("cleanup IDs verified from ledger; installed Close Session still required for tabs")
    return 0


def _ids_from_receipts(receipts: list[dict]) -> list[str]:
    ids: list[str] = []
    for row in receipts:
        for key in ("tabId", "backendId"):
            value = str(row.get(key) or "").strip()
            if value:
                ids.append(value)
        ids.extend(str(item) for item in row.get("childIds") or [] if item)
        ids.extend(
            str(worker.get("childBackendSessionID"))
            for worker in row.get("workerReceipts") or []
            if worker.get("childBackendSessionID")
        )
    return ids


def _load_any_ledger(path: Path) -> list[dict]:
    try:
        first = next(line for line in path.read_text(encoding="utf-8").splitlines() if line.strip())
        version = json.loads(first).get("schemaVersion")
    except (OSError, StopIteration, json.JSONDecodeError, AttributeError) as exc:
        raise HarnessError("cleanup ledger is unreadable") from exc
    return load_ledger_v2(path) if version == 2 else load_ledger(path)


def _billable(args: argparse.Namespace) -> int:
    if not args.run_id:
        raise HarnessError("billable mode requires --run-id")
    require_live_run_id_v1(args.run_id)
    manifest = load_manifest_v1(args.manifest, run_id=args.run_id)
    report = preflight(REPO, manifest, ledger=args.ledger)
    safe_print(json.dumps({"preflight": redact_value("preflight", report)}))
    launch_installed()
    receipts: list[dict] = []
    cumulative = 0
    try:
        packets = manifest["packets"]
        for index, packet in enumerate(packets):
            ceiling = int(manifest["anomalyCeilingActualTokens"])
            if cumulative >= ceiling:
                raise HarnessError(
                    f"ceiling breach: cumulative actual tokens {cumulative} exceed {ceiling}"
                )
            continuation = packet["continuation"]
            start_new = continuation is None or int(continuation["turn"]) == 1
            if start_new:
                select_workspace(REPO)
                new_chat()
                select_model(packet["model"])
            elif continuation and continuation.get("resumeAfterQuit"):
                restore_continuation(marker=receipts[-1]["marker"])
                resume_saved_task()
            send_prompt(packet["prompt"])
            if packet.get("deliberateStop"):
                wait_for_stop_control(timeout_seconds=60)
                time.sleep(2)
                stop_turn()
            else:
                timeout = 480 if packet["childTopology"] else 300
                wait_for_marker(packet["marker"], timeout_seconds=timeout)
            identities = capture_identities(REPO, packet["marker"])
            receipt = extract_receipt(packet, identities, TRANSCRIPTS)
            if packet.get("deliberateStop"):
                receipt["outcome"] = "stopped"
            receipts.append(receipt)
            cumulative += int(receipt["tokenSplit"]["total"])
            _append_ledger(args.ledger, receipt)
            nxt = packets[index + 1] if index + 1 < len(packets) else None
            nxt_continuation = (nxt or {}).get("continuation") or {}
            if nxt_continuation.get("resumeAfterQuit"):
                quit_installed()
                two_process_zero_samples()
                launch_installed()
        summary = evaluate(manifest, receipts)
        slice_id = "6" if int(manifest["anomalyCeilingActualTokens"]) == 250000 else "5"
        if slice_id == "6":
            live_state = "installed GrokBuild after Slice 6 extraction packet"
            next_action = "exact Slice 6 cleanup then merged-main closeout"
            hard_stop = "Slice 7, releases, tags, origin, force-push, branch deletion, and configuration changes"
            checkpoint = "signed-installed Slice 6 acceptance"
        else:
            live_state = "installed GrokBuild after three-route manifest"
            next_action = "exact Slice 5 cleanup then personal PR merge"
            hard_stop = "Slice 6 until merged-main closeout, Slice 7, releases, tags, origin, force-push, branch deletion, and configuration changes"
            checkpoint = "signed-installed acceptance"
        handoff = render_handoff(
            HandoffContext(
                repo=str(REPO),
                branch="main",
                commit=report["identity"]["head"],
                slice=slice_id,
                checkpoint=checkpoint,
                result="completed",
                live_state=live_state,
                usage=str(summary["actualTokens"]),
                thread_ids=",".join(row["tabId"] for row in receipts),
                cleanup="none",
                risk="none",
                next_action=next_action,
                hard_stop=hard_stop,
            )
        )
        safe_print(handoff)
        return 0
    except HarnessError:
        if receipts:
            _write_ledger(args.ledger, receipts)
        raise


def _append_ledger(path: Path, row: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(redact_value("row", row), separators=(",", ":")) + "\n")


def _write_ledger(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(redact_value("row", row), separators=(",", ":")) + "\n")


def _manifest_version(path: Path) -> int:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HarnessError(f"manifest is unreadable: {exc}") from exc
    version = value.get("schemaVersion") if isinstance(value, dict) else None
    if version not in {1, 2, 3, 4}:
        raise HarnessError(f"unsupported schemaVersion {version}")
    return int(version)


def _load_manifest(path: Path, run_id: str | None, version: int) -> dict:
    if version == 4:
        return load_manifest_4c(path, run_id=run_id)
    if version == 3:
        return load_manifest_v3(path, run_id=run_id)
    if version == 2:
        return load_manifest_v2(path, run_id=run_id)
    return load_manifest_v1(path, run_id=run_id)


def _billable_4c(args: argparse.Namespace) -> int:
    """Armed 4C route matrix. Ceiling still refuses before this body in main().

    Clone of armed _billable_v2 control flow: four-arg launch_installed every
    epoch, no retries, no resume_saved_task, and never a bare unarmed launch.
    Committed prices stay unconfirmed, so require_4c_send_ready refuses Send
    even if the ceiling predicate is later narrowed without a price confirm.
    """
    from harness.preflight_v2 import effective_config_sha, preflight as preflight_v2

    if not args.run_id:
        raise HarnessError("billable mode requires --run-id")
    require_live_run_id_v2(args.run_id)
    manifest = load_manifest_4c(args.manifest, run_id=args.run_id)
    require_4c_paid_identity(manifest, source_path=args.manifest)
    if args.candidate_selection is None:
        raise HarnessError("4C execution requires one exact --candidate-selection authority")
    if any(packet["continuation"] is not None for packet in manifest["packets"]):
        raise HarnessError("4C packets must not continue a session")
    require_4c_send_ready(manifest)
    report = preflight_v2(REPO, manifest, ledger=args.ledger)
    safe_print(json.dumps({"preflight": redact_value("preflight", report)}))
    authority = prepare_campaign_authority_4c(manifest, candidate_selection=args.candidate_selection)
    rows: list[dict] = []
    cumulative = 0
    current_packet: dict | None = None
    current_identities: dict[str, str] = {}
    attempt_is_open = False
    terminal_is_recorded = False
    cleanup_is_recorded = False
    send_may_be_live = False
    app_launch_epoch = 0
    process_zero_samples: list[dict] | None = None
    try:
        packets = manifest["packets"]
        for index, packet in enumerate(packets):
            current_packet = packet
            current_identities = {}
            attempt_is_open = False
            terminal_is_recorded = False
            cleanup_is_recorded = False
            send_may_be_live = False
            allocation = int(packet["tokenAllocation"])
            if cumulative + allocation + int(manifest["emergencyReserveTokens"]) > int(manifest["campaignTokenCeiling"]):
                raise HarnessError(f"{packet['id']}: pre-Send reserve refusal")

            launch_installed(
                budget_file=authority.authorization,
                cli_manifest_file=authority.cli_manifest,
                budget_ledger_file=authority.ledger,
                runtime_selection_file=authority.runtime_selection,
            )
            app_launch_epoch += 1
            select_workspace(REPO)
            new_chat()
            select_model(packet["selectorModelID"])

            if _sha256(Path.home() / ".grok/config.toml") != report["configSha256"]:
                raise HarnessError("config hash drift before Send")
            if effective_config_sha(REPO) != report["effectiveConfigSha256"]:
                raise HarnessError("official effective configuration drift before Send")
            if _sha256(INSTALLED_PROVIDER_HELPER) != report["helperSha256"]:
                raise HarnessError("installed provider helper drift before Send")
            start = attempt_started(packet, manifest["runId"], app_launch_epoch)
            append_row_v2(args.ledger, start)
            rows.append(start)
            attempt_is_open = True
            send_may_be_live = True
            send_prompt(packet["prompt"])
            timeout = 480 if packet["childTopology"] else 300
            wait_for_marker(packet["marker"], timeout_seconds=timeout)
            current_identities = capture_identities(REPO, packet["marker"])
            terminal = extract_terminal(
                packet,
                manifest["runId"],
                current_identities,
                TRANSCRIPTS,
                app_launch_epoch,
            )
            current_identities["processGeneration"] = terminal["processGeneration"]
            candidate_cleanup = cleanup_receipt(
                packet,
                manifest["runId"],
                current_identities,
                app_launch_epoch,
                local_tab="closedExact",
            )
            validation_error: Exception | None = None
            if _sha256(Path.home() / ".grok/config.toml") != report["configSha256"]:
                validation_error = HarnessError("config hash drift after Send")
            elif effective_config_sha(REPO) != report["effectiveConfigSha256"]:
                validation_error = HarnessError("official effective configuration drift after Send")
            elif _sha256(INSTALLED_PROVIDER_HELPER) != report["helperSha256"]:
                validation_error = HarnessError("installed provider helper drift after Send")
            try:
                if validation_error is None:
                    evaluate_prefix_v2(manifest, rows + [terminal, candidate_cleanup])
            except Exception as error:
                validation_error = error
            if validation_error is not None:
                terminal = reject_terminal(terminal, str(validation_error))
            append_row_v2(args.ledger, terminal)
            rows.append(terminal)
            terminal_is_recorded = True
            attempt_is_open = False
            send_may_be_live = False
            if validation_error is not None:
                raise HarnessError(f"packet evidence rejected: {validation_error}") from validation_error
            close_current_session(current_identities["tabId"])
            append_row_v2(args.ledger, candidate_cleanup)
            rows.append(candidate_cleanup)
            cleanup_is_recorded = True
            evaluate_prefix_v2(manifest, load_ledger_v2(args.ledger))
            cumulative += int(terminal["usage"]["totalTokens"])
            quit_installed()
            two_process_zero_samples()

        summary = evaluate_v2(manifest, load_ledger_v2(args.ledger))
        quit_installed()
        process_zero_samples = two_process_zero_samples()
        summary["processZero"] = process_zero_samples
        safe_print(json.dumps(redact_value("summary", summary), sort_keys=True))
        return 0
    except Exception as exc:
        secondary_failures: list[str] = []
        if current_packet is not None and send_may_be_live and not terminal_is_recorded:
            try:
                stop_turn()
                wait_for_terminal_checkpoint(current_packet["marker"], timeout_seconds=45)
                current_identities = capture_identities(REPO, current_packet["marker"])
                stopped = extract_terminal(
                    current_packet,
                    manifest["runId"],
                    current_identities,
                    TRANSCRIPTS,
                    app_launch_epoch,
                )
                current_identities["processGeneration"] = stopped["processGeneration"]
                append_row_v2(args.ledger, stopped)
                rows.append(stopped)
                terminal_is_recorded = True
                attempt_is_open = False
            except Exception:
                secondary_failures.append("live turn could not be stopped and reconciled")
        if attempt_is_open and current_packet is not None and not terminal_is_recorded:
            try:
                failure = terminal_failure(
                    current_packet,
                    manifest["runId"],
                    str(exc),
                    app_launch_epoch,
                    current_identities,
                )
                append_row_v2(args.ledger, failure)
                rows.append(failure)
                terminal_is_recorded = True
            except Exception:
                secondary_failures.append("failure ledger append failed")
        if terminal_is_recorded and not cleanup_is_recorded and current_packet is not None:
            local_cleanup = "unknown"
            if current_identities.get("tabId"):
                try:
                    close_current_session(current_identities["tabId"])
                    local_cleanup = "closedExact"
                except Exception:
                    local_cleanup = "retained"
                    secondary_failures.append("exact local-tab cleanup failed")
            try:
                cleanup = cleanup_receipt(
                    current_packet,
                    manifest["runId"],
                    current_identities,
                    app_launch_epoch,
                    local_tab=local_cleanup,
                )
                append_row_v2(args.ledger, cleanup)
                rows.append(cleanup)
                cleanup_is_recorded = True
            except Exception:
                secondary_failures.append("cleanup ledger append failed")
        try:
            quit_installed()
            process_zero_samples = two_process_zero_samples()
        except Exception:
            secondary_failures.append("installed app cleanup/process-zero failed")
        if secondary_failures:
            raise HarnessError(
                "4C campaign stopped; " + "; ".join(secondary_failures)
            ) from exc
        if isinstance(exc, HarnessError):
            raise
        raise HarnessError(f"4C campaign stopped: {type(exc).__name__}") from exc
    finally:
        safe_print(json.dumps({
            "authorityRetention": retain_campaign_authority(
                authority,
                process_zero_samples=process_zero_samples,
            )
        }, sort_keys=True))


def _billable_v2(args: argparse.Namespace) -> int:
    """Run one-attempt packets under the app's live official-ACP budget guard."""
    from harness.preflight_v2 import effective_config_sha, preflight as preflight_v2

    if not args.run_id:
        raise HarnessError("billable mode requires --run-id")
    require_live_run_id_v2(args.run_id)
    manifest = load_manifest_v2(args.manifest, run_id=args.run_id)
    if args.candidate_selection is None:
        raise HarnessError("v2 execution requires one exact --candidate-selection authority")
    if any(packet["continuation"] is not None for packet in manifest["packets"]):
        raise HarnessError(
            "this manifest contains session-continuation packets; convert them to fresh, "
            "self-contained allocations before unlocking billable execution"
        )
    report = preflight_v2(REPO, manifest, ledger=args.ledger)
    safe_print(json.dumps({"preflight": redact_value("preflight", report)}))
    authority = prepare_campaign_authority(manifest, candidate_selection=args.candidate_selection)
    rows: list[dict] = []
    cumulative = 0
    current_packet: dict | None = None
    current_identities: dict[str, str] = {}
    attempt_is_open = False
    terminal_is_recorded = False
    cleanup_is_recorded = False
    send_may_be_live = False
    app_launch_epoch = 0
    process_zero_samples: list[dict] | None = None
    try:
        packets = manifest["packets"]
        for index, packet in enumerate(packets):
            current_packet = packet
            current_identities = {}
            attempt_is_open = False
            terminal_is_recorded = False
            cleanup_is_recorded = False
            send_may_be_live = False
            allocation = int(packet["tokenAllocation"])
            if cumulative + allocation + int(manifest["emergencyReserveTokens"]) > int(manifest["campaignTokenCeiling"]):
                raise HarnessError(f"{packet['id']}: pre-Send reserve refusal")

            launch_installed(
                budget_file=authority.authorization,
                cli_manifest_file=authority.cli_manifest,
                budget_ledger_file=authority.ledger,
                runtime_selection_file=authority.runtime_selection,
            )
            app_launch_epoch += 1
            select_workspace(REPO)
            new_chat()
            select_model(packet["selectorModelID"])

            if _sha256(Path.home() / ".grok/config.toml") != report["configSha256"]:
                raise HarnessError("config hash drift before Send")
            if effective_config_sha(REPO) != report["effectiveConfigSha256"]:
                raise HarnessError("official effective configuration drift before Send")
            if _sha256(INSTALLED_PROVIDER_HELPER) != report["helperSha256"]:
                raise HarnessError("installed provider helper drift before Send")
            start = attempt_started(packet, manifest["runId"], app_launch_epoch)
            append_row_v2(args.ledger, start)
            rows.append(start)
            attempt_is_open = True
            # From this boundary onward an AX click may have reached the app
            # even if the driver reports an uncertain transport failure.
            send_may_be_live = True
            send_prompt(packet["prompt"])
            timeout = 480 if packet["childTopology"] else 300
            wait_for_marker(packet["marker"], timeout_seconds=timeout)
            current_identities = capture_identities(REPO, packet["marker"])
            terminal = extract_terminal(
                packet,
                manifest["runId"],
                current_identities,
                TRANSCRIPTS,
                app_launch_epoch,
            )
            current_identities["processGeneration"] = terminal["processGeneration"]
            candidate_cleanup = cleanup_receipt(
                packet,
                manifest["runId"],
                current_identities,
                app_launch_epoch,
                local_tab="closedExact",
            )
            validation_error: Exception | None = None
            if _sha256(Path.home() / ".grok/config.toml") != report["configSha256"]:
                validation_error = HarnessError("config hash drift after Send")
            elif effective_config_sha(REPO) != report["effectiveConfigSha256"]:
                validation_error = HarnessError("official effective configuration drift after Send")
            elif _sha256(INSTALLED_PROVIDER_HELPER) != report["helperSha256"]:
                validation_error = HarnessError("installed provider helper drift after Send")
            try:
                if validation_error is None:
                    evaluate_prefix_v2(manifest, rows + [terminal, candidate_cleanup])
            except Exception as error:
                validation_error = error
            if validation_error is not None:
                terminal = reject_terminal(terminal, str(validation_error))
            append_row_v2(args.ledger, terminal)
            rows.append(terminal)
            terminal_is_recorded = True
            attempt_is_open = False
            send_may_be_live = False
            if validation_error is not None:
                # Exact paid evidence is fsync'd before cleanup or campaign stop.
                raise HarnessError(f"packet evidence rejected: {validation_error}") from validation_error
            close_current_session(current_identities["tabId"])
            append_row_v2(args.ledger, candidate_cleanup)
            rows.append(candidate_cleanup)
            cleanup_is_recorded = True
            evaluate_prefix_v2(manifest, load_ledger_v2(args.ledger))
            cumulative += int(terminal["usage"]["totalTokens"])
            quit_installed()
            two_process_zero_samples()

        # Acceptance is based on the fsync'd ledger reloaded from disk, never
        # merely on the in-memory objects the current process hoped it wrote.
        summary = evaluate_v2(manifest, load_ledger_v2(args.ledger))
        quit_installed()
        process_zero_samples = two_process_zero_samples()
        summary["processZero"] = process_zero_samples
        safe_print(json.dumps(redact_value("summary", summary), sort_keys=True))
        return 0
    except Exception as exc:
        secondary_failures: list[str] = []
        if current_packet is not None and send_may_be_live and not terminal_is_recorded:
            try:
                stop_turn()
                wait_for_terminal_checkpoint(current_packet["marker"], timeout_seconds=45)
                current_identities = capture_identities(REPO, current_packet["marker"])
                stopped = extract_terminal(
                    current_packet,
                    manifest["runId"],
                    current_identities,
                    TRANSCRIPTS,
                    app_launch_epoch,
                )
                current_identities["processGeneration"] = stopped["processGeneration"]
                append_row_v2(args.ledger, stopped)
                rows.append(stopped)
                terminal_is_recorded = True
                attempt_is_open = False
            except Exception:
                secondary_failures.append("live turn could not be stopped and reconciled")
        if attempt_is_open and current_packet is not None and not terminal_is_recorded:
            try:
                failure = terminal_failure(
                    current_packet,
                    manifest["runId"],
                    str(exc),
                    app_launch_epoch,
                    current_identities,
                )
                append_row_v2(args.ledger, failure)
                rows.append(failure)
                terminal_is_recorded = True
            except Exception:
                secondary_failures.append("failure ledger append failed")
        if terminal_is_recorded and not cleanup_is_recorded and current_packet is not None:
            local_cleanup = "unknown"
            if current_identities.get("tabId"):
                try:
                    close_current_session(current_identities["tabId"])
                    local_cleanup = "closedExact"
                except Exception:
                    local_cleanup = "retained"
                    secondary_failures.append("exact local-tab cleanup failed")
            try:
                cleanup = cleanup_receipt(
                    current_packet,
                    manifest["runId"],
                    current_identities,
                    app_launch_epoch,
                    local_tab=local_cleanup,
                )
                append_row_v2(args.ledger, cleanup)
                rows.append(cleanup)
                cleanup_is_recorded = True
            except Exception:
                secondary_failures.append("cleanup ledger append failed")
        try:
            quit_installed()
            process_zero_samples = two_process_zero_samples()
        except Exception:
            secondary_failures.append("installed app cleanup/process-zero failed")
        if secondary_failures:
            raise HarnessError(
                "v2 campaign stopped; " + "; ".join(secondary_failures)
            ) from exc
        if isinstance(exc, HarnessError):
            raise
        raise HarnessError(f"v2 campaign stopped: {type(exc).__name__}") from exc
    finally:
        safe_print(json.dumps({
            "authorityRetention": retain_campaign_authority(
                authority,
                process_zero_samples=process_zero_samples,
            )
        }, sort_keys=True))


def _billable_v3(args: argparse.Namespace) -> int:
    """Three allocated epochs, one backend, one ledger.

    T1 creates the backend with session/new. T2/T3 relaunch a fresh installed
    process, select the retained tab through governed_fresh_process_load, then
    Send. Cleanup runs only after T3. Paid 4C stays locked in main() via
    require_absolute_ceiling_support(). This body is the 4B.4 continuation
    executor, not the 4C paid route matrix; do not unlock it onto official 1.0.4.
    """
    if not args.run_id:
        raise HarnessError("billable mode requires --run-id")
    require_live_run_id_v2(args.run_id)
    manifest = load_manifest_v3(args.manifest, run_id=args.run_id)
    packets = manifest["packets"]
    if len(packets) != 3:
        raise HarnessError("schema-3 continuation requires exactly three packets")
    rows: list[dict] = []
    current_packet: dict | None = None
    current_identities: dict[str, str] = {}
    send_may_be_live = False
    terminal_is_recorded = False
    app_launch_epoch = 0
    retained_backend = ""
    campaign_ledger = str(args.ledger)
    try:
        for index, packet in enumerate(packets, start=1):
            current_packet = packet
            current_identities = {}
            terminal_is_recorded = False
            send_may_be_live = False
            quit_installed()
            two_process_zero_samples()
            launch_installed()
            app_launch_epoch += 1
            if index == 1:
                select_workspace(REPO)
                new_chat()
                select_model(packet["selectorModelID"])
            else:
                governed_fresh_process_load(
                    expected_tab=packet["continuation"]["expectedLocalTab"],
                    expected_backend=retained_backend,
                )
            send_may_be_live = True
            send_prompt(packet["prompt"])
            wait_for_marker(packet["marker"], timeout_seconds=300)
            current_identities = capture_identities(REPO, packet["marker"])
            generation = _continuation_process_generation(
                TRANSCRIPTS / f"{current_identities['tabId']}.json",
                packet["marker"],
            )
            if index == 1:
                retained_tab = current_identities["tabId"]
                retained_backend = current_identities["backendId"]
                for item in packets:
                    item["continuation"]["expectedLocalTab"] = retained_tab
            terminal = {
                "rowType": "terminal",
                "packetId": packet["id"],
                "tabId": current_identities["tabId"],
                "backendId": current_identities["backendId"],
                "appLaunchEpoch": app_launch_epoch,
                "processGeneration": generation,
                "allocationID": packet["allocationID"],
                "campaignLedger": campaign_ledger,
                "loadMethod": "session/load",
                "sessionLoadStartedFreshFallback": False,
                "loadTimePrompt": False,
                "outcome": "new" if index == 1 else "loaded",
            }
            append_row_v3(args.ledger, terminal)
            rows.append(terminal)
            terminal_is_recorded = True
            send_may_be_live = False
        close_current_session(current_identities["tabId"])
        append_row_v3(
            args.ledger,
            {
                "rowType": "cleanup",
                "packetId": packets[-1]["id"],
                "cleanup": {"localTab": "closedExact"},
            },
        )
        summary = evaluate_fresh_process_continuation(
            manifest["packets"],
            load_ledger_v3(args.ledger),
        )
        quit_installed()
        summary["processZero"] = two_process_zero_samples()
        safe_print(json.dumps(redact_value("summary", summary), sort_keys=True))
        return 0
    except Exception as exc:
        secondary_failures: list[str] = []
        if current_packet is not None and send_may_be_live and not terminal_is_recorded:
            try:
                stop_turn()
                wait_for_terminal_checkpoint(current_packet["marker"], timeout_seconds=45)
            except Exception:
                secondary_failures.append("live turn could not be stopped and reconciled")
        try:
            quit_installed()
            two_process_zero_samples()
        except Exception:
            secondary_failures.append("installed app cleanup/process-zero failed")
        if secondary_failures:
            raise HarnessError(
                "v3 continuation stopped; " + "; ".join(secondary_failures)
            ) from exc
        if isinstance(exc, HarnessError):
            raise
        raise HarnessError(f"v3 continuation stopped: {type(exc).__name__}") from exc


def _continuation_process_generation(path: Path, marker: str) -> int:
    try:
        envelope = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HarnessError("continuation transcript is unreadable") from exc
    messages = envelope.get("messages") if isinstance(envelope, dict) else None
    if not isinstance(messages, list):
        raise HarnessError("continuation transcript has no messages")
    start = None
    for index, message in enumerate(messages):
        if not isinstance(message, dict):
            continue
        role = str(message.get("role") or "").lower()
        content = str(message.get("content") or "")
        if role == "user" and marker in content:
            start = index
    if start is None:
        raise HarnessError(f"continuation transcript lacks marker {marker}")
    for message in messages[start:]:
        if not isinstance(message, dict):
            continue
        role = str(message.get("role") or "").lower()
        if role not in {"assistant", "agent"}:
            continue
        checkpoint = (message.get("assistantTrace") or {}).get("checkpoint") or {}
        if not isinstance(checkpoint, dict):
            continue
        generation = checkpoint.get("processGeneration")
        if generation:
            return int(generation)
    raise HarnessError(f"continuation transcript lacks process generation for {marker}")


def _sha256(path: Path) -> str | None:
    if not path.exists():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


if __name__ == "__main__":
    sys.exit(main())
