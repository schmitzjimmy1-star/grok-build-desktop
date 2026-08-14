"""Exactly-three-sentence checkpoint handoff with literal none fields."""

from __future__ import annotations

import re
from dataclasses import dataclass

from .errors import HandoffError

_SENTENCE_SPLIT = re.compile(r"(?<=\.)\s+(?=[A-Z])")
_NONE = re.compile(r"\bnone\b")


@dataclass(frozen=True)
class HandoffContext:
    repo: str
    branch: str
    commit: str
    slice: str
    checkpoint: str
    result: str
    live_state: str
    usage: str
    thread_ids: str
    cleanup: str
    risk: str
    next_action: str
    hard_stop: str


def _or_none(value: str | None) -> str:
    text = (value or "").strip()
    return text if text else "none"


def render_handoff(ctx: HandoffContext) -> str:
    sentence_one = (
        f"Canonical repo {ctx.repo} is branch {ctx.branch} at {ctx.commit}; "
        f"Slice {ctx.slice} {ctx.checkpoint} {ctx.result}."
    )
    sentence_two = (
        f"Live state is {ctx.live_state}, billable usage {_or_none(ctx.usage)}, "
        f"created test thread IDs {_or_none(ctx.thread_ids)}, cleanup {_or_none(ctx.cleanup)}, "
        f"and risk {_or_none(ctx.risk)}."
    )
    sentence_three = (
        f"The next authorized action is {ctx.next_action}; hard stop forbids {ctx.hard_stop}."
    )
    text = f"{sentence_one} {sentence_two} {sentence_three}"
    validate_handoff(text)
    return text


def split_sentences(text: str) -> list[str]:
    stripped = text.strip()
    if not stripped:
        return []
    return [part.strip() for part in _SENTENCE_SPLIT.split(stripped) if part.strip()]


def validate_handoff(text: str) -> None:
    sentences = split_sentences(text)
    count = len(sentences)
    if count != 3:
        raise HandoffError(
            f"handoff must be exactly three sentences, found {count}"
        )
    if not _NONE.search(text):
        raise HandoffError("handoff is missing literal none")
    if not sentences[0].endswith(".") or not sentences[1].endswith(".") or not sentences[2].endswith("."):
        raise HandoffError("handoff must be exactly three sentences")
