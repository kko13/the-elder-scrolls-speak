"""Pick a Polly long-form voice deterministically per author.

Long-form voices (en-US) at the time of writing: Danielle, Gregory, Patrick,
Ruth, Stephen. We hash the author name into one of those so each author
consistently sounds the same.
"""

from __future__ import annotations

import hashlib

LONG_FORM_VOICES = ["Danielle", "Gregory", "Patrick", "Ruth", "Stephen"]
DEFAULT_VOICE = "Gregory"


def voice_for_author(author: str | None) -> str:
    if not author or author.lower() in {"unknown", "anonymous"}:
        return DEFAULT_VOICE
    h = hashlib.sha256(author.encode("utf-8")).digest()
    return LONG_FORM_VOICES[h[0] % len(LONG_FORM_VOICES)]
