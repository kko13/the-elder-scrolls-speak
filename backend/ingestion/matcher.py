"""Match Imperial Library book titles to UESP entries.

Titles diverge in small ways: "The Real Barenziah, v 1" vs "The Real Barenziah,
Book I" vs "The Real Barenziah, Part 1". Casing, punctuation, and roman/arabic
numerals all vary. We normalise both sides then compare with rapidfuzz.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from rapidfuzz import fuzz, process

_ROMAN = {"i": "1", "ii": "2", "iii": "3", "iv": "4", "v": "5",
          "vi": "6", "vii": "7", "viii": "8", "ix": "9", "x": "10"}
_PUNCT = re.compile(r"[^\w\s]")
_WS = re.compile(r"\s+")


def normalise(title: str) -> str:
    t = title.lower().strip()
    t = _PUNCT.sub(" ", t)
    t = _WS.sub(" ", t).strip()
    # Replace roman numerals (whole-word only).
    out = []
    for word in t.split():
        out.append(_ROMAN.get(word, word))
    return " ".join(out)


@dataclass(slots=True)
class Match:
    il_title: str
    uesp_title: str | None
    score: int


def best_matches(
    il_titles: list[str],
    uesp_titles: list[str],
    *,
    threshold: int = 90,
) -> list[Match]:
    """For each Imperial Library title, find the best UESP candidate.

    `threshold` is the rapidfuzz token_sort_ratio cutoff. Below that, the match
    is None (caller should triage).
    """
    norm_uesp = {normalise(t): t for t in uesp_titles}
    keys = list(norm_uesp.keys())
    out: list[Match] = []
    for il in il_titles:
        norm = normalise(il)
        result = process.extractOne(norm, keys, scorer=fuzz.token_sort_ratio)
        if result and result[1] >= threshold:
            out.append(Match(il_title=il, uesp_title=norm_uesp[result[0]], score=int(result[1])))
        else:
            score = int(result[1]) if result else 0
            out.append(Match(il_title=il, uesp_title=None, score=score))
    return out
