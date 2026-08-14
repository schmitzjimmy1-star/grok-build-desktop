"""Drive the installed GrokBuild UI. Never fake ACP or auto-approve."""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any
from urllib.parse import quote

from .errors import DriverError
from .preflight import process_zero_sample
from .redaction import assert_safe_text

APP_NAME = "GrokBuild"
APP_PATH = Path("/Applications/GrokBuild.app")


def _ad(args: list[str], *, timeout: int = 60) -> dict[str, Any]:
    result = subprocess.run(
        ["agent-desktop", *args],
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
    )
    payload = result.stdout.strip() or result.stderr.strip()
    try:
        data = json.loads(payload) if payload.startswith("{") else {}
    except json.JSONDecodeError as exc:
        raise DriverError("agent-desktop returned non-JSON") from exc
    if result.returncode != 0:
        code = data.get("error", {}).get("code") if isinstance(data, dict) else result.returncode
        raise DriverError(f"agent-desktop failed: {code}")
    return data


def _find(identifier: str) -> dict[str, Any]:
    data = _ad(["find", "--app", APP_NAME, "--id", identifier, "-i"])
    return data


def _click_id(identifier: str) -> None:
    snapshot = _ad(["snapshot", "--app", APP_NAME, "-i", "--compact"])
    snapshot_id = snapshot.get("data", {}).get("snapshot_id") or snapshot.get("snapshot_id")
    found = _ad(["find", "--app", APP_NAME, "--id", identifier])
    refs = (
        found.get("data", {}).get("matches")
        or found.get("data", {}).get("elements")
        or []
    )
    if not refs:
        raise DriverError(f"missing AX identifier {identifier}")
    first = refs[0]
    ref = first.get("ref") or first.get("id")
    if not ref:
        raise DriverError(f"no ref for {identifier}")
    click_args = ["click", ref]
    if snapshot_id:
        click_args.extend(["--snapshot", str(snapshot_id)])
    _ad(click_args)


def launch_installed() -> None:
    if not APP_PATH.exists():
        raise DriverError("installed app is missing")
    subprocess.run(["open", str(APP_PATH)], check=False)
    deadline = time.time() + 30
    while time.time() < deadline:
        listed = subprocess.run(
            ["pgrep", "-x", "GrokBuild"],
            capture_output=True,
            text=True,
            check=False,
        )
        if listed.stdout.strip():
            time.sleep(2)
            return
        time.sleep(0.5)
    raise DriverError("GrokBuild did not launch")


def quit_installed() -> None:
    subprocess.run(
        ["osascript", "-e", 'tell application "GrokBuild" to quit'],
        check=False,
        capture_output=True,
        text=True,
    )
    deadline = time.time() + 6
    while time.time() < deadline:
        try:
            process_zero_sample()
            return
        except Exception:
            time.sleep(0.5)
    raise DriverError("quit did not reach process-zero")


def select_model(model: str) -> None:
    _click_id("grok-model-effort-selector")
    time.sleep(0.4)
    _click_id(f"grok-model-option-{model}")
    time.sleep(0.3)
    _click_id("grok-effort-option-low")


def new_chat() -> None:
    _click_id("grok-rail-new-chat")
    time.sleep(0.8)


def send_prompt(prompt: str) -> None:
    assert_safe_text(prompt, context="composer")
    snapshot = _ad(["snapshot", "--app", APP_NAME, "-i", "--compact"])
    snapshot_id = snapshot.get("data", {}).get("snapshot_id") or snapshot.get("snapshot_id")
    found = _ad(["find", "--app", APP_NAME, "--id", "grok-message-composer"])
    refs = found.get("data", {}).get("matches") or found.get("data", {}).get("elements") or []
    if not refs:
        raise DriverError("missing grok-message-composer")
    ref = refs[0].get("ref") or refs[0].get("id")
    type_args = ["type", ref, prompt]
    if snapshot_id:
        type_args.extend(["--snapshot", str(snapshot_id)])
    _ad(type_args, timeout=30)
    time.sleep(0.2)
    _click_id("grok-send")


def wait_for_marker(marker: str, *, timeout_seconds: int) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        result = subprocess.run(
            ["agent-desktop", "find", "--app", APP_NAME, "--text", marker],
            text=True,
            capture_output=True,
            check=False,
        )
        if marker in result.stdout and "sk-" not in result.stdout.lower():
            return
        time.sleep(2)
    raise DriverError(f"timed out waiting for marker {marker}")


def capture_identities(repo: Path, marker: str) -> dict[str, str]:
    transcripts = Path.home() / "Library/Application Support/GrokBuild/Transcripts"
    tab_id = ""
    if transcripts.exists():
        listed = subprocess.run(
            ["rg", "-l", "--glob", "*.json", marker, str(transcripts)],
            text=True,
            capture_output=True,
            check=False,
        )
        files = [line for line in listed.stdout.splitlines() if line.endswith(".json") and not line.endswith(".metadata.json")]
        if files:
            tab_id = Path(files[-1]).stem
    encoded = quote(str(repo), safe="")
    grok = Path.home() / ".grok/bin/grok"
    binary = str(grok) if grok.exists() else "grok"
    search = subprocess.run(
        [binary, "sessions", "search", marker, "--limit", "5"],
        cwd=repo,
        text=True,
        capture_output=True,
        check=False,
    )
    backend_id = ""
    for line in search.stdout.splitlines():
        stripped = line.strip()
        if len(stripped) >= 32 and "-" in stripped:
            backend_id = stripped.split()[0]
            break
    if not tab_id or not backend_id:
        raise DriverError(f"could not capture exact identities for {marker}")
    return {"tabId": tab_id, "backendId": backend_id, "sessionRoot": encoded}
