"""Scrape book texts from imperial-library.info (Drupal site).

We rely on the per-game index page and individual node pages. The site does
not expose an API, so we parse HTML. Markup may shift over time — keep selectors
narrow and fail loudly.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from urllib.parse import urljoin

import httpx
from selectolax.parser import HTMLParser

BASE = "https://www.imperial-library.info"

# Drupal book listing path per game. Slugs verified manually.
GAME_INDEX = {
    "skyrim":    "/books/all/by-game/skyrim",
    "morrowind": "/books/all/by-game/morrowind",
    "oblivion":  "/books/all/by-game/oblivion",
    "eso":       "/books/all/by-game/eso",
    "daggerfall":"/books/all/by-game/daggerfall",
    "arena":     "/books/all/by-game/arena",
}


@dataclass(slots=True)
class IndexEntry:
    title: str
    url: str


@dataclass(slots=True)
class ScrapedBook:
    title: str
    url: str
    text: str
    raw_html: str


def list_books(client: httpx.Client, game: str) -> Iterator[IndexEntry]:
    """Walk all paginated index pages for a game and yield (title, url) tuples."""
    if game not in GAME_INDEX:
        raise ValueError(f"Unsupported game: {game}")

    page = 0
    while True:
        path = f"{GAME_INDEX[game]}?page={page}" if page else GAME_INDEX[game]
        resp = client.get(urljoin(BASE, path))
        resp.raise_for_status()
        tree = HTMLParser(resp.text)

        # Each book row links to its node page from a table cell.
        anchors = tree.css("table a[href^='/books/']")
        if not anchors:
            return
        for a in anchors:
            title = (a.text() or "").strip()
            href = a.attributes.get("href", "")
            if title and href:
                yield IndexEntry(title=title, url=urljoin(BASE, href))

        # Pager: if there's no "next" link, stop.
        if not tree.css_first("li.pager__item--next"):
            return
        page += 1


def fetch_book(client: httpx.Client, entry: IndexEntry) -> ScrapedBook:
    resp = client.get(entry.url)
    resp.raise_for_status()
    tree = HTMLParser(resp.text)

    # The book text lives in a div with class "field--name-field-content"
    # (Drupal field name). Fall back to the article body if that selector misses.
    body = tree.css_first("div.field--name-field-content") or tree.css_first("article")
    if body is None:
        raise RuntimeError(f"No content node found at {entry.url}")

    # Strip script/style.
    for n in body.css("script, style, .field__label"):
        n.decompose()
    text = body.text(separator="\n").strip()

    return ScrapedBook(title=entry.title, url=entry.url, text=text, raw_html=resp.text)
