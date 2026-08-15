"""Refuse to print credentials or response bodies."""

from __future__ import annotations

import re
from typing import Any

_SECRET_KEY = re.compile(
    r"(api[_-]?key|authorization|bearer|password|secret|credential|oauth)",
    re.IGNORECASE,
)
_BODY_KEY = {
    "responsebody",
    "assistanttext",
    "rawoutput",
    "messagebody",
    "chainofthought",
    "hiddenreasoning",
}


def is_sensitive_key(key: str) -> bool:
    lowered = key.replace("-", "").replace("_", "").lower()
    if lowered in _BODY_KEY:
        return True
    return _SECRET_KEY.search(key) is not None


def redact_value(key: str, value: Any) -> Any:
    if is_sensitive_key(key):
        return "[redacted]"
    if isinstance(value, dict):
        return {k: redact_value(k, v) for k, v in value.items()}
    if isinstance(value, list):
        return [redact_value(key, item) for item in value]
    return value


def assert_safe_text(text: str, *, context: str) -> None:
    lowered = text.lower()
    if "sk-" in lowered or "bearer " in lowered:
        raise ValueError(f"{context}: refused to emit credential-shaped text")


def safe_print(text: str) -> None:
    assert_safe_text(text, context="stdout")
    print(text)
