"""Fetch book metadata from UESP via the MediaWiki API.

We pull the parsed HTML of `Lore:Books_by_Author`, walk the author headings,
and yield (title, author, uesp_url) tuples. Per-book pages can be fetched
later for richer metadata (in-game locations, summaries) — keep that in
`fetch_book_detail` so the matcher can be written without it.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass, field
from urllib.parse import quote

import httpx
from selectolax.parser import HTMLParser

API = "https://en.uesp.net/w/api.php"
WIKI = "https://en.uesp.net/wiki"


@dataclass(slots=True)
class UespBook:
    title: str
    author: str
    url: str
    games: list[str] = field(default_factory=list)
    summary: str | None = None
    locations: list[str] = field(default_factory=list)


def _api_parse(client: httpx.Client, page: str) -> str:
    resp = client.get(API, params={
        "action": "parse",
        "page": page,
        "prop": "text",
        "format": "json",
        "formatversion": "2",
        "redirects": "1",
    })
    resp.raise_for_status()
    return resp.json()["parse"]["text"]


def list_books_by_author(client: httpx.Client) -> Iterator[UespBook]:
    """Walk the Books_by_Author page and emit one record per book listing.

    The page structure is roughly:
      <h2 id="Author_Name">...</h2>
      <ul>
        <li><a href="/wiki/Lore:Book_Title">Book Title</a> ...</li>
      </ul>

    Authors of unknown identity are grouped under "Anonymous" / "Unknown".
    """
    html = _api_parse(client, "Lore:Books_by_Author")
    tree = HTMLParser(html)

    # Author headings are h2/h3 with a span.mw-headline child.
    current_author = "Unknown"
    body = tree.css_first("div") or tree.root
    for node in body.iter():
        if node.tag in ("h2", "h3"):
            headline = node.css_first("span.mw-headline")
            if headline is not None:
                current_author = (headline.text() or "Unknown").strip()
        elif node.tag == "li":
            link = node.css_first("a[href^='/wiki/Lore:']")
            if link is None:
                continue
            title = (link.text() or "").strip()
            href = link.attributes.get("href", "")
            if not title or not href:
                continue
            yield UespBook(title=title, author=current_author, url=f"https://en.uesp.net{href}")


def fetch_book_detail(client: httpx.Client, book: UespBook) -> UespBook:
    """Pull the per-book page and try to extract a short summary + locations.

    UESP infoboxes vary; we keep extraction defensive — missing fields are fine.
    """
    page = book.url.removeprefix(f"{WIKI}/")
    html = _api_parse(client, page)
    tree = HTMLParser(html)

    # First non-empty <p> after the infobox is usually the lede.
    for p in tree.css("p"):
        text = (p.text() or "").strip()
        if text and len(text) > 60:
            book.summary = text
            break

    # Naive: any link to a Skyrim:Places-style page in the body counts as a location hint.
    locations = []
    for a in tree.css("a[href*=':']"):
        href = a.attributes.get("href", "")
        if any(g in href for g in ("/wiki/Skyrim:", "/wiki/Morrowind:", "/wiki/Oblivion:")):
            txt = (a.text() or "").strip()
            if txt and txt not in locations:
                locations.append(txt)
        if len(locations) >= 10:
            break
    book.locations = locations

    return book


def page_to_url(title: str) -> str:
    return f"{WIKI}/{quote(title.replace(' ', '_'))}"
