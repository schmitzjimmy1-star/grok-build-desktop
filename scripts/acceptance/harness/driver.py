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
        message = error.get("message") if isinstance(error, dict) else None
        verb = args[0]
        detail = f"{code} ({verb}"
        if message:
            detail += f": {message}"
        detail += ")"
        raise DriverError(f"agent-desktop failed: {detail}")
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
        native = node.get("native_id")
        if isinstance(native, dict):
            identifier = str(native.get("value") or "")
        elif isinstance(native, str):
            identifier = native
        else:
            identifier = str(node.get("identifier") or node.get("id") or "")
        if isinstance(name, str) and isinstance(ref, str) and ref.startswith("@"):
            hits.append({
                "name": name,
                "ref": ref,
                "role": role,
                "value": value,
                "identifier": identifier,
            })
        for child in node.get("children") or []:
            _walk_named(child, hits)
    elif isinstance(node, list):
        for child in node:
            _walk_named(child, hits)


def _walk_ax_text(node: Any, hits: list[dict[str, str]]) -> None:
    """Collect AX name/value/identifier even when a node has no clickable ref.

    The ACP error banner is static text. Requiring `@` refs dropped it, so the
    harness waited for Stop after initialize had already failed.
    """
    if isinstance(node, dict):
        name = str(node.get("name") or "")
        value = str(node.get("value") or "")
        native = node.get("native_id")
        if isinstance(native, dict):
            identifier = str(native.get("value") or "")
        elif isinstance(native, str):
            identifier = native
        else:
            identifier = str(node.get("identifier") or node.get("id") or "")
        if name or value or identifier:
            hits.append({
                "name": name,
                "value": value,
                "identifier": identifier,
            })
        for child in node.get("children") or []:
            _walk_ax_text(child, hits)
    elif isinstance(node, list):
        for child in node:
            _walk_ax_text(child, hits)


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


def _click_ref(ref: str) -> None:
    try:
        _ad(["click", ref])
    except DriverError:
        _ad(["--headed", "click", ref])


def _click_named(name: str, *, role: str | None = None) -> None:
    try:
        _click_ref(_find_named(name, role=role))
    except DriverError as exc:
        raise DriverError(f"click {name!r} failed: {exc}") from exc


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
            try:
                _click_ref(item["ref"])
            except DriverError as exc:
                raise DriverError(f"click menu item {label!r} failed: {exc}") from exc
            return
    raise DriverError(f"missing menu item {label}")


def _click_menu_item_starting(prefix: str) -> None:
    for item in _menu_items():
        if item["name"].startswith(prefix):
            try:
                _click_ref(item["ref"])
            except DriverError as exc:
                raise DriverError(f"click menu item prefix {prefix!r} failed: {exc}") from exc
            return
    raise DriverError(f"missing menu item prefix {prefix}")


def _find_native_id(native_id: str) -> str:
    snapshot = _ad(["snapshot", "--app", APP_NAME, *_window_args(), "--surface", "window", "-i"])
    hits: list[dict[str, str]] = []
    payload = _payload(snapshot)
    if isinstance(payload, dict):
        _walk_named(payload.get("tree"), hits)
    matches = [item for item in hits if item.get("identifier") == native_id]
    if len(matches) != 1:
        raise DriverError(f"missing AX identifier {native_id}")
    return matches[0]["ref"]


def _selector_name() -> str:
    snapshot = _ad(["snapshot", "--app", APP_NAME, *_window_args(), "--surface", "window", "-i"])
    hits: list[dict[str, str]] = []
    payload = _payload(snapshot)
    if isinstance(payload, dict):
        _walk_named(payload.get("tree"), hits)
    matches = [item for item in hits if item.get("identifier") == "grok-model-effort-selector"]
    if len(matches) != 1:
        raise DriverError("missing AX identifier grok-model-effort-selector")
    return matches[0]["name"]


def _dismiss_open_menu() -> None:
    try:
        _ad(["press", "escape", "--app", APP_NAME, *_window_args()])
        time.sleep(0.2)
    except DriverError:
        pass


def _open_model_menu() -> None:
    _click_ref(_find_native_id("grok-model-effort-selector"))
    time.sleep(0.4)


MODEL_LABELS = {
    "grok-4.6": "Grok 4.6",
    "gpt-5.6-terra": "gpt-5.6-terra",
    "gpt-5.6-luna": "gpt-5.6-luna",
    "deepseek-deepseek-v4-flash-0731": "deepseek/deepseek-v4-flash-0731",
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
    """Pick the packet model only. Do not click Low: effort change restarts ACP."""
    label = MODEL_LABELS.get(model, model)
    current = _selector_name()
    if label in current:
        return
    option_id = "grok-model-option-" + model.replace("/", "-")
    _open_model_menu()
    for item in _menu_items():
        if item.get("identifier") == option_id:
            _click_ref(item["ref"])
            time.sleep(0.2)
            _dismiss_open_menu()
            return
    _click_menu_item(label)
    time.sleep(0.2)
    _dismiss_open_menu()


def new_chat() -> None:
    _dismiss_upgrade_notice()
    _click_named("New chat")
    time.sleep(0.8)
    deadline = time.time() + 10
    composer_seen = False
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            _find_named("Message composer", role="textfield")
            composer_seen = True
            try:
                _find_named("Agent mode")
            except DriverError:
                # Fresh idle tabs keep ACP unstarted, so the mode menu is absent
                # until Send. Default currentMode is already Agent.
                return
            select_build_mode()
            return
        except DriverError as exc:
            last_error = exc
            time.sleep(0.4)
    if composer_seen:
        raise DriverError(f"new chat exposed composer but could not select Build: {last_error}")
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
    try:
        _click_ref(matches[0]["ref"])
    except DriverError as exc:
        raise DriverError(f"click {expected_name!r} failed: {exc}") from exc
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

    Idle welcome composers expose AX readonly and do not implement SetValue, so
    ACP never starts until a human-style type plus Send. Do not AX-clear. Missing
    labels may be searched without cost, but once a concrete control is selected
    the harness never falls back to another click or Cmd-Return. An uncertain
    actuator result is terminal evidence, not permission to resend.
    """
    assert_safe_text(prompt, context="composer")
    _dismiss_open_menu()
    ref = _find_named("Message composer", role="textfield")
    try:
        _ad(["scroll-to", ref])
    except DriverError:
        pass
    try:
        _ad(["focus", ref])
    except DriverError:
        try:
            _ad(["click", ref])
        except DriverError as exc:
            raise DriverError(f"could not focus Message composer: {exc}") from exc
    time.sleep(0.2)
    _type_into(ref, prompt)
    time.sleep(0.4)
    deadline = time.time() + 12
    send_ref = None
    while time.time() < deadline:
        for name in SEND_LABELS:
            try:
                found = _ad([
                    "find", "--app", APP_NAME, *_window_args(),
                    "--name", name, "--first",
                ])
            except DriverError:
                continue
            refs = _matches(found)
            if not refs:
                continue
            states = refs[0].get("states") or []
            if "disabled" in states:
                continue
            try:
                send_ref = _ref(refs[0])
            except DriverError:
                continue
            break
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


ACP_STARTUP_FAILURE_MARKERS = (
    "ACP startup failed",
    "ACP initialize failed",
    "ACP initialize timed out",
    "ACP session/new failed",
    "ACP session/new timed out",
    "ACP session/load failed",
    "ACP session/load timed out",
    "stdio closed",
    "Timed out while connecting to grok.",
)


def _acp_startup_failure_text() -> str | None:
    snapshot = _ad(
        ["snapshot", "--app", APP_NAME, *_window_args(), "--surface", "window", "-i"]
    )
    hits: list[dict[str, str]] = []
    payload = _payload(snapshot)
    if isinstance(payload, dict):
        _walk_ax_text(payload.get("tree"), hits)
    for item in hits:
        identifier = item.get("identifier") or ""
        name = item.get("name") or ""
        value = item.get("value") or ""
        blob = f"{name} {value}"
        if identifier == "grok-acp-error-banner":
            return name or value or "ACP initialize failed"
        if any(marker in blob for marker in ACP_STARTUP_FAILURE_MARKERS):
            return name or value or blob.strip()
    return None


def wait_for_acp_startup_outcome(*, timeout_seconds: int = 130) -> None:
    """After Send, wait until ACP is live or a named ACP method failure is visible.

    Stop turn means `session/prompt` started. The error banner
    (`grok-acp-error-banner` / ``ACP initialize failed``) means handshake died
    before ``session/prompt``. Walk AX text even without clickable refs. Do not
    assume Stop exists just because Send was clicked, and do not wait for first stdout before initialize.
    A snapshot AXFrontmost timeout is a driver flake,
    not ACP startup failure; retry it.
    """
    deadline = time.time() + timeout_seconds
    last_error: Exception | None = None
    try:
        _ad(["focus-window", "--app", APP_NAME, *_window_args()], timeout=15)
    except DriverError:
        pass
    while time.time() < deadline:
        try:
            failure = _acp_startup_failure_text()
        except DriverError as exc:
            last_error = exc
            time.sleep(0.4)
            continue
        if failure:
            raise DriverError(failure)
        try:
            _find_named("Stop turn")
            return
        except DriverError as exc:
            last_error = exc
        time.sleep(0.4)
    raise DriverError(
        "ACP session/prompt did not start, and no named ACP method failure was visible: "
        f"{last_error}"
    )


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


def _select_retained_tab(expected_tab: str) -> None:
    snapshot = _ad(["snapshot", "--app", APP_NAME, *_window_args(), "--surface", "window", "-i"])
    hits: list[dict[str, str]] = []
    payload = _payload(snapshot)
    if isinstance(payload, dict):
        _walk_named(payload.get("tree"), hits)
    matches = [
        item for item in hits
        if item.get("value") == expected_tab
        or item.get("identifier", "").endswith(expected_tab)
    ]
    if len(matches) != 1:
        raise DriverError("exact retained tab is not uniquely available")
    _ad(["click", matches[0]["ref"]])
    time.sleep(0.6)


def _retained_backend_id(expected_tab: str) -> str:
    transcripts = Path.home() / "Library/Application Support/GrokBuild/Transcripts"
    envelope_path = transcripts / f"{expected_tab}.json"
    if not envelope_path.is_file():
        raise DriverError("retained tab transcript is unavailable")
    try:
        envelope = json.loads(envelope_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise DriverError("retained tab transcript is unreadable") from exc
    if not isinstance(envelope, dict):
        raise DriverError("retained tab transcript is unreadable")
    backend = _backend_from_envelope(envelope)
    if not backend:
        raise DriverError("retained tab does not expose the expected backend")
    return backend


def governed_fresh_process_load(*, expected_tab: str, expected_backend: str) -> None:
    """Select the retained tab after allocation so later Send uses ACP session/load.

    Requires the installed app. Does not send a prompt.
    """
    if not expected_tab or not expected_backend:
        raise DriverError("governed load requires the exact retained tab and backend")
    _require_only_installed()
    _select_retained_tab(expected_tab)
    deadline = time.time() + 25
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            _find_named("Message composer", role="textfield")
            observed = _retained_backend_id(expected_tab)
            if observed != expected_backend:
                raise DriverError("retained tab/backend identity drift")
            return
        except DriverError as exc:
            last_error = exc
            time.sleep(0.5)
    raise DriverError(f"governed session/load tab is not ready: {last_error}")


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
