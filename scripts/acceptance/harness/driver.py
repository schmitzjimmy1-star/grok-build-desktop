"""Drive the installed GrokBuild UI. Never fake ACP or auto-approve."""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote

from .errors import DriverError
from .evidence import _turn_messages
from .preflight import process_zero_sample
from .redaction import assert_safe_text

APP_NAME = "GrokBuild"
APP_PATH = Path("/Applications/GrokBuild.app")
INSTALLED_EXEC = APP_PATH / "Contents/MacOS/GrokBuild"
_WINDOW_ID = ""


def _running_executables() -> list[str]:
    result = subprocess.run(
        ["pgrep", "-x", APP_NAME],
        capture_output=True,
        text=True,
        check=False,
    )
    paths: list[str] = []
    for pid in result.stdout.split():
        info = subprocess.run(
            ["ps", "-p", pid, "-o", "command="],
            capture_output=True,
            text=True,
            check=False,
        )
        command = info.stdout.strip()
        if command:
            paths.append(command.split()[0])
    return paths


def _require_only_installed() -> None:
    paths = _running_executables()
    if not paths:
        raise DriverError("installed GrokBuild is not running")
    wrong = [path for path in paths if path != str(INSTALLED_EXEC)]
    if wrong:
        raise DriverError(
            "refusing to drive a non-installed GrokBuild: " + ", ".join(wrong)
        )


def _window_args() -> list[str]:
    return ["--window-id", _WINDOW_ID] if _WINDOW_ID else []


def _ad(args: list[str], *, timeout: int = 60) -> dict[str, Any]:
    result = subprocess.run(
        ["agent-desktop", *args],
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
    )
    payload = (result.stdout or "").strip()
    if not payload.startswith("{"):
        err = (result.stderr or "").strip()
        raise DriverError(f"agent-desktop returned non-JSON for {args[0]}")
    try:
        data = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise DriverError("agent-desktop returned non-JSON") from exc
    if result.returncode != 0 or data.get("ok") is False:
        error = data.get("error") if isinstance(data, dict) else {}
        code = error.get("code") if isinstance(error, dict) else result.returncode
        raise DriverError(f"agent-desktop failed: {code}")
    return data


def _matches(data: dict[str, Any]) -> list[dict[str, Any]]:
    payload = data.get("data") if isinstance(data.get("data"), dict) else data
    if isinstance(payload.get("matches"), list):
        return [item for item in payload["matches"] if isinstance(item, dict)]
    if isinstance(payload.get("elements"), list):
        return [item for item in payload["elements"] if isinstance(item, dict)]
    match = payload.get("match")
    if isinstance(match, dict):
        return [match]
    return []


def _ref(item: dict[str, Any]) -> str:
    ref = item.get("ref_id") or item.get("ref")
    if not isinstance(ref, str) or not ref.startswith("@"):
        raise DriverError("no ref on matched element")
    return ref


def _payload(data: dict[str, Any]) -> Any:
    return data.get("data") if "data" in data else data


def _walk_named(node: Any, hits: list[dict[str, str]]) -> None:
    if isinstance(node, dict):
        name = node.get("name")
        ref = node.get("ref_id") or node.get("ref")
        role = str(node.get("role") or "")
        value = str(node.get("value") or "")
        if isinstance(name, str) and isinstance(ref, str) and ref.startswith("@"):
            hits.append({"name": name, "ref": ref, "role": role, "value": value})
        for child in node.get("children") or []:
            _walk_named(child, hits)
    elif isinstance(node, list):
        for child in node:
            _walk_named(child, hits)


def _find_named(name: str, *, role: str | None = None) -> str:
    args = ["find", "--app", APP_NAME, *_window_args(), "--name", name, "--first"]
    if role:
        args.extend(["--role", role])
    found = _ad(args)
    refs = _matches(found)
    if refs:
        try:
            return _ref(refs[0])
        except DriverError:
            pass
    raise DriverError(f"missing AX name {name}")


SEND_LABELS = (
    "Send and resume session",
    "Send message",
    "Send",
)


def _click_named(name: str, *, role: str | None = None) -> None:
    _ad(["click", _find_named(name, role=role)])


def _type_into(ref: str, text: str) -> None:
    try:
        _ad(["type", ref, text, "--timeout-ms", "30000"], timeout=45)
    except DriverError:
        _ad(["--headed", "type", ref, text, "--timeout-ms", "30000"], timeout=45)


def _dismiss_upgrade_notice() -> None:
    try:
        _click_named("Dismiss upgrade notice")
        time.sleep(0.3)
    except DriverError:
        pass


def _menu_items() -> list[dict[str, str]]:
    snapshot = _ad(["snapshot", "--app", APP_NAME, "--surface", "menu", "-i"])
    hits: list[dict[str, str]] = []
    payload = _payload(snapshot)
    if isinstance(payload, dict):
        _walk_named(payload.get("tree"), hits)
    return hits


def _click_menu_item(label: str) -> None:
    for item in _menu_items():
        if item["name"] == label:
            _ad(["click", item["ref"]])
            return
    raise DriverError(f"missing menu item {label}")


MODEL_LABELS = {
    "grok-4.6": "Grok 4.6",
    "gpt-5.6-terra": "gpt-5.6-terra",
    "gpt-5.6-luna": "gpt-5.6-luna",
    "deepseek-deepseek-v4-flash-0731": "DeepSeek V4 Flash 0731",
    "openai/gpt-4.1-mini": "openai/gpt-4.1-mini",
}


def _pin_installed_window() -> None:
    global _WINDOW_ID
    _require_only_installed()
    try:
        _ad(["focus-window", "--app", APP_NAME], timeout=15)
    except DriverError:
        pass
    listed = _ad(["list-windows", "--app", APP_NAME])
    payload = _payload(listed)
    windows = payload if isinstance(payload, list) else (
        payload.get("windows") or payload.get("items") or []
        if isinstance(payload, dict)
        else []
    )
    visible = []
    for window in windows:
        if not isinstance(window, dict):
            continue
        window_id = str(window.get("id") or window.get("window_id") or "")
        if not window_id:
            continue
        hidden = window.get("visible") is False or window.get("is_minimized") is True
        if hidden:
            continue
        visible.append((window_id, bool(window.get("is_focused") or window.get("focused"))))
    if len(visible) != 1:
        raise DriverError(
            f"budgeted driver requires exactly one visible GrokBuild window, found {len(visible)}"
        )
    _WINDOW_ID = visible[0][0]


def launch_installed(
    *,
    budget_file: Path | None = None,
    cli_manifest_file: Path | None = None,
    budget_ledger_file: Path | None = None,
    runtime_selection_file: Path | None = None,
) -> None:
    global _WINDOW_ID
    _WINDOW_ID = ""
    if not APP_PATH.exists():
        raise DriverError("installed app is missing")
    running = _running_executables()
    wrong = [path for path in running if path != str(INSTALLED_EXEC)]
    if wrong:
        raise DriverError(
            "another GrokBuild binary is running; quit it before driving /Applications/GrokBuild.app: "
            + ", ".join(wrong)
        )
    budgeted = (budget_file, cli_manifest_file, budget_ledger_file, runtime_selection_file)
    if any(value is not None for value in budgeted) and any(value is None for value in budgeted):
        raise DriverError("budgeted acceptance requires authorization, CLI manifest, ledger, and runtime selection together")
    if budget_file is not None and str(INSTALLED_EXEC) in running:
        raise DriverError("budgeted acceptance requires a fresh installed app process")
    if str(INSTALLED_EXEC) not in running:
        command = ["open", "-n", str(APP_PATH)]
        if budget_file is not None:
            command.extend([
                "--args",
                f"--grokbuild-acceptance-budget-file={budget_file}",
                f"--grokbuild-acceptance-cli-manifest-file={cli_manifest_file}",
                f"--grokbuild-acceptance-budget-ledger-file={budget_ledger_file}",
                f"--grokbuild-acceptance-runtime-selection-file={runtime_selection_file}",
            ])
        subprocess.run(command, check=False)
    deadline = time.time() + 30
    while time.time() < deadline:
        try:
            _require_only_installed()
            time.sleep(1.5)
            _pin_installed_window()
            _dismiss_upgrade_notice()
            return
        except DriverError:
            time.sleep(0.5)
    raise DriverError("installed /Applications/GrokBuild.app did not launch")


def quit_installed() -> None:
    global _WINDOW_ID
    _WINDOW_ID = ""
    subprocess.run(
        ["osascript", "-e", 'tell application "GrokBuild" to quit'],
        check=False,
        capture_output=True,
        text=True,
    )
    deadline = time.time() + 25
    while time.time() < deadline:
        try:
            process_zero_sample()
            return
        except Exception:
            time.sleep(0.5)
    raise DriverError("quit did not reach process-zero")


def select_build_mode() -> None:
    """Select Build from the exact mode menu; absence is a hard acceptance stop."""
    _click_named("Agent mode")
    time.sleep(0.4)
    _click_menu_item("Build")
    time.sleep(0.2)


def select_model(model: str) -> None:
    label = MODEL_LABELS.get(model, model)
    _click_named("Model and reasoning effort")
    time.sleep(0.4)
    _click_menu_item("Low")
    time.sleep(0.3)
    _click_named("Model and reasoning effort")
    time.sleep(0.4)
    _click_menu_item(label)
    time.sleep(0.2)


def new_chat() -> None:
    _dismiss_upgrade_notice()
    _click_named("New chat")
    time.sleep(0.8)
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            _find_named("Message composer", role="textfield")
            select_build_mode()
            return
        except DriverError:
            time.sleep(0.4)
    raise DriverError("new chat did not expose Message composer")


def select_workspace(path: Path) -> None:
    """Select the one exact repo row so UI launch cwd matches official inspect cwd."""
    snapshot = _ad(["snapshot", "--app", APP_NAME, *_window_args(), "--surface", "window", "-i"])
    hits: list[dict[str, str]] = []
    payload = _payload(snapshot)
    if isinstance(payload, dict):
        _walk_named(payload.get("tree"), hits)
    expected_name = f"Project {path.name}"
    matches = [item for item in hits if item["name"] == expected_name and item.get("value") == str(path)]
    if len(matches) != 1:
        raise DriverError("exact acceptance project row is not uniquely available")
    _ad(["click", matches[0]["ref"]])
    time.sleep(0.6)


def close_current_session(tab_id: str) -> None:
    """Close only the selected run-created tab and prove no sibling transcript moved."""
    transcripts = Path.home() / "Library/Application Support/GrokBuild/Transcripts"
    target = transcripts / f"{tab_id}.json"
    metadata = transcripts / f"{tab_id}.metadata.json"
    if not target.is_file():
        raise DriverError("exact run-created transcript is unavailable before cleanup")
    before = {path.name for path in transcripts.glob("*.json")}
    snapshot = _ad(["snapshot", "--app", APP_NAME, *_window_args(), "--surface", "window", "-i"])
    hits: list[dict[str, str]] = []
    payload = _payload(snapshot)
    if isinstance(payload, dict):
        _walk_named(payload.get("tree"), hits)
    actions = [item for item in hits if item["name"].startswith("Session actions for ")]
    if len(actions) != 1:
        raise DriverError("exactly one selected Session actions control is required for cleanup")
    _ad(["click", actions[0]["ref"]])
    time.sleep(0.3)
    _click_menu_item("Close Local Tab")
    deadline = time.time() + 15
    while time.time() < deadline and target.exists():
        time.sleep(0.25)
    if target.exists():
        raise DriverError("exact run-created local tab did not close")
    after = {path.name for path in transcripts.glob("*.json")}
    expected_removed = {target.name}
    if metadata.name in before:
        expected_removed.add(metadata.name)
    if metadata.exists() or before - expected_removed != after:
        raise DriverError("cleanup changed a transcript outside the exact run-created tab")


def send_prompt(prompt: str) -> None:
    """Perform exactly one billable Send actuator.

    Missing labels may be searched without cost, but once a concrete control is
    selected the harness never falls back to another click or Cmd-Return. An
    uncertain actuator result is terminal evidence, not permission to resend.
    """
    assert_safe_text(prompt, context="composer")
    ref = _find_named("Message composer", role="textfield")
    _ad(["clear", ref])
    _type_into(ref, prompt)
    time.sleep(0.4)
    deadline = time.time() + 12
    send_ref = None
    while time.time() < deadline:
        for name in SEND_LABELS:
            try:
                send_ref = _find_named(name)
                break
            except DriverError:
                continue
        if send_ref is not None:
            break
        time.sleep(0.4)

    if send_ref is None:
        raise DriverError("could not find one exact Send control")
    try:
        _ad(["click", send_ref])
        return
    except DriverError as exc:
        raise DriverError(f"single Send actuator returned an uncertain failure: {exc}") from exc


def wait_for_stop_control(*, timeout_seconds: int = 45) -> None:
    """Wait until the live Stop turn control is exposed after Send."""
    deadline = time.time() + timeout_seconds
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            _find_named("Stop turn")
            return
        except DriverError as exc:
            last_error = exc
            time.sleep(0.4)
    raise DriverError(f"Stop turn did not appear: {last_error}")


def stop_turn() -> None:
    """Click the installed Stop turn control. Never fakes ACP cancellation."""
    wait_for_stop_control()
    _click_named("Stop turn")
    deadline = time.time() + 40
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            _find_named("Stop turn")
            time.sleep(0.4)
        except DriverError:
            return
    raise DriverError(f"Stop turn remained after click: {last_error}")


def wait_for_restore_chrome(*, timeout_seconds: int = 25) -> None:
    """Wait until launch restore has exposed composer and resume or send chrome."""
    deadline = time.time() + timeout_seconds
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            _find_named("Message composer", role="textfield")
            for name in ("Resume current task", *SEND_LABELS):
                try:
                    _find_named(name)
                    return
                except DriverError as exc:
                    last_error = exc
        except DriverError as exc:
            last_error = exc
        time.sleep(0.5)
    raise DriverError(f"restore chrome did not appear: {last_error}")


def resume_saved_task() -> None:
    """ACP session/load with no provider prompt. Required after quit/relaunch."""
    wait_for_restore_chrome()
    deadline = time.time() + 35
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            _click_named("Resume current task")
            time.sleep(2.0)
            _wait_until_resume_clicked(timeout_seconds=40)
            return
        except DriverError as exc:
            last_error = exc
            time.sleep(0.5)
    raise DriverError(f"missing Resume current task: {last_error}")


def _wait_until_resume_clicked(*, timeout_seconds: int) -> None:
    """Give session/load time to leave the Saved-task chrome before T3 Send."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            _find_named("Resume current task")
            time.sleep(0.5)
        except DriverError:
            return
    # Send can still complete resume if the chrome lingers; do not fail here.


def wait_for_marker(marker: str, *, timeout_seconds: int) -> None:
    """Compatibility name for a marker-correlated terminal-checkpoint wait."""
    wait_for_terminal_checkpoint(marker, timeout_seconds=timeout_seconds)


def wait_for_terminal_checkpoint(marker: str, *, timeout_seconds: int) -> None:
    """Wait for the matching assistant turn to persist a settled checkpoint.

    This correlates the frozen user-prompt marker to its assistant checkpoint;
    it never requires that a stopped assistant response contain the marker.
    """
    assert_safe_text(marker, context="marker")
    transcripts = Path.home() / "Library/Application Support/GrokBuild/Transcripts"
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        tab_id, _backend = _identities_from_transcripts(transcripts, marker)
        if tab_id:
            path = transcripts / f"{tab_id}.json"
            try:
                envelope = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                time.sleep(2)
                continue
            turn = _turn_messages(envelope.get("messages") or [], marker)
            for message in turn:
                role = str(message.get("role") or "").lower()
                if role not in {"assistant", "agent"}:
                    continue
                trace = message.get("assistantTrace") or {}
                checkpoint = trace.get("checkpoint") or {}
                if not isinstance(checkpoint, dict) or not checkpoint:
                    continue
                if checkpoint.get("isSettled") is not True:
                    continue
                if (
                    checkpoint.get("processGeneration")
                    or checkpoint.get("modelID")
                    or checkpoint.get("usageReceipt")
                    or checkpoint.get("parentBackendSessionID")
                ):
                    return
        time.sleep(2)
    raise DriverError(f"timed out waiting for settled checkpoint {marker}")


def restore_continuation(*, marker: str) -> None:
    """Bring the restored continuation tab forward after quit/relaunch."""
    assert_safe_text(marker, context="restore-marker")
    try:
        _ad(
            ["wait", "--app", APP_NAME, *_window_args(), "--text", marker, "--timeout", "35000"],
            timeout=40,
        )
        _find_named("Message composer", role="textfield")
        wait_for_restore_chrome(timeout_seconds=20)
        return
    except DriverError:
        pass
    found = _ad(["find", "--app", APP_NAME, *_window_args(), "--name", "Session:", "--limit", "20"])
    for item in _matches(found):
        try:
            _ad(["click", _ref(item)])
            time.sleep(0.6)
            _ad(
                ["wait", "--app", APP_NAME, *_window_args(), "--text", marker, "--timeout", "12000"],
                timeout=16,
            )
            _find_named("Message composer", role="textfield")
            wait_for_restore_chrome(timeout_seconds=20)
            return
        except DriverError:
            continue
    raise DriverError(f"could not restore continuation tab for {marker}")


def capture_identities(repo: Path, marker: str) -> dict[str, str]:
    transcripts = Path.home() / "Library/Application Support/GrokBuild/Transcripts"
    deadline = time.time() + 20
    tab_id = ""
    backend_id = ""
    while time.time() < deadline:
        tab_id, backend_id = _identities_from_transcripts(transcripts, marker)
        if tab_id and backend_id:
            return {"tabId": tab_id, "backendId": backend_id, "sessionRoot": quote(str(repo), safe="")}
        time.sleep(0.5)
    if not tab_id or not backend_id:
        raise DriverError(f"app-owned typed checkpoint lacks exact identities for {marker}")
    return {"tabId": tab_id, "backendId": backend_id, "sessionRoot": quote(str(repo), safe="")}


def _identities_from_transcripts(transcripts: Path, marker: str) -> tuple[str, str]:
    if not transcripts.exists():
        return "", ""
    newest = ""
    newest_mtime = -1.0
    backend = ""
    for path in transcripts.glob("*.json"):
        if path.name.endswith(".metadata.json"):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        if marker not in text:
            continue
        mtime = path.stat().st_mtime
        if mtime < newest_mtime:
            continue
        newest_mtime = mtime
        newest = path.stem
        try:
            envelope = json.loads(text)
        except json.JSONDecodeError:
            continue
        backend = _backend_from_envelope(envelope) or backend
    return newest, backend


def _backend_from_envelope(envelope: dict[str, Any]) -> str:
    for message in reversed(envelope.get("messages") or []):
        if not isinstance(message, dict):
            continue
        trace = message.get("assistantTrace") or {}
        checkpoint = trace.get("checkpoint") or {}
        if not isinstance(checkpoint, dict):
            continue
        backend = str(checkpoint.get("parentBackendSessionID") or "").strip()
        if backend:
            return backend
    return ""
