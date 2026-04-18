from __future__ import annotations

import re
import unicodedata

_NON_WORD = re.compile(r"[^a-z0-9]+")
_APOSTROPHES = re.compile(r"['\u2019\u2018\"]")


def slugify(text: str) -> str:
    """Stable, URL-safe slug. Used as the DynamoDB partition key for books."""
    norm = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    norm = norm.lower().strip()
    # Drop apostrophes outright so "Lusty Argonian Maid's" -> "lusty-argonian-maids",
    # not "lusty-argonian-maid-s".
    norm = _APOSTROPHES.sub("", norm)
    norm = _NON_WORD.sub("-", norm).strip("-")
    return norm or "untitled"
