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
        if isinstance(name, str) and isinstance(ref, str) and ref.startswith("@"):
            hits.append({"name": name, "ref": ref, "role": role})
        for child in node.get("children") or []:
            _walk_named(child, hits)
    elif isinstance(node, list):
        for child in node:
            _walk_named(child, hits)


def _find_named(name: str, *, role: str | None = None) -> str:
    args = ["find", "--app", APP_NAME, "--name", name, "--first"]
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
    "gpt-5.6-luna": "gpt-5.6-luna",
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
    if not visible:
        raise DriverError("installed GrokBuild has no visible window")
    focused = [item[0] for item in visible if item[1]]
    _WINDOW_ID = focused[0] if focused else visible[0][0]


def launch_installed() -> None:
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
    if str(INSTALLED_EXEC) not in running:
        subprocess.run(["open", str(APP_PATH)], check=False)
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
    """Prefer the mode selector. Never click empty-state Build starter cards."""
    try:
        _click_named("Agent mode")
        time.sleep(0.4)
        _click_menu_item("Build")
    except DriverError:
        return
    time.sleep(0.2)


def select_model(model: str) -> None:
    label = MODEL_LABELS.get(model, model)
    _click_named("Model and reasoning effort")
    time.sleep(0.4)
    try:
        _click_menu_item("Low")
        time.sleep(0.3)
        _click_named("Model and reasoning effort")
        time.sleep(0.4)
    except DriverError:
        pass
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


def send_prompt(prompt: str) -> None:
    assert_safe_text(prompt, context="composer")
    ref = _find_named("Message composer", role="textfield")
    try:
        _ad(["clear", ref])
    except DriverError:
        pass
    _type_into(ref, prompt)
    time.sleep(0.4)
    last_error: Exception | None = None
    deadline = time.time() + 12
    while time.time() < deadline:
        for name in SEND_LABELS:
            try:
                _click_named(name)
                return
            except DriverError as exc:
                last_error = exc
        time.sleep(0.4)
    try:
        _ad(["press", "cmd+return", "--app", APP_NAME])
        return
    except DriverError as exc:
        last_error = exc
    raise DriverError(f"could not send from composer: {last_error}")


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
    """Wait for the matching assistant turn to persist a settled checkpoint.

    The user prompt also contains the marker, so AX text matching is not a
    completion signal.
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
                if checkpoint.get("isSettled") is False:
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
            ["wait", "--app", APP_NAME, "--text", marker, "--timeout", "35000"],
            timeout=40,
        )
        _find_named("Message composer", role="textfield")
        wait_for_restore_chrome(timeout_seconds=20)
        return
    except DriverError:
        pass
    found = _ad(["find", "--app", APP_NAME, "--name", "Session:", "--limit", "20"])
    for item in _matches(found):
        try:
            _ad(["click", _ref(item)])
            time.sleep(0.6)
            _ad(
                ["wait", "--app", APP_NAME, "--text", marker, "--timeout", "12000"],
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
    if not tab_id:
        tab_id = _tab_from_rg(transcripts, marker)
    if not backend_id:
        backend_id = _backend_from_cli(repo, marker)
    if not tab_id or not backend_id:
        raise DriverError(f"could not capture exact identities for {marker}")
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


def _tab_from_rg(transcripts: Path, marker: str) -> str:
    if not transcripts.exists():
        return ""
    listed = subprocess.run(
        ["rg", "-l", "--glob", "*.json", marker, str(transcripts)],
        text=True,
        capture_output=True,
        check=False,
    )
    files = [
        line
        for line in listed.stdout.splitlines()
        if line.endswith(".json") and not line.endswith(".metadata.json")
    ]
    return Path(files[-1]).stem if files else ""


def _backend_from_cli(repo: Path, marker: str) -> str:
    grok = Path.home() / ".grok/bin/grok"
    binary = str(grok) if grok.exists() else "grok"
    search = subprocess.run(
        [binary, "sessions", "search", marker, "--limit", "5"],
        cwd=repo,
        text=True,
        capture_output=True,
        check=False,
    )
    for line in search.stdout.splitlines():
        stripped = line.strip()
        if len(stripped) >= 32 and "-" in stripped:
            return stripped.split()[0]
    return ""
