"""Lambda entrypoint: scrape IL, fetch UESP metadata, write S3 + DynamoDB.

Invoke shape (EventBridge or manual):
    {"game": "skyrim", "limit": 10}    # optional limit for testing
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
from datetime import UTC, datetime

import boto3

from shared.models import BookRecord, InGameLocation
from shared.slug import slugify

from .fetch_uesp import list_books_by_author
from .http import polite_client
from .matcher import best_matches
from .scrape_imperial import fetch_book, list_books

log = logging.getLogger()
log.setLevel(logging.INFO)

s3 = boto3.client("s3")
ddb = boto3.resource("dynamodb")


def _content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def lambda_handler(event: dict, _ctx) -> dict:
    game = event.get("game", "skyrim")
    limit = event.get("limit")
    raw_bucket = os.environ["RAW_BUCKET"]
    texts_bucket = os.environ["TEXTS_BUCKET"]
    table = ddb.Table(os.environ["BOOKS_TABLE"])

    log.info("ingest start: game=%s limit=%s", game, limit)

    # 1. Pull UESP metadata first (cheap, single page parse).
    with polite_client() as client:
        uesp_books = list(list_books_by_author(client))
    log.info("uesp: %d entries", len(uesp_books))
    uesp_by_title = {b.title: b for b in uesp_books}

    # 2. Walk IL index for the chosen game.
    with polite_client() as client:
        il_entries = list(list_books(client, game))
    log.info("imperial: %d entries", len(il_entries))
    if limit:
        il_entries = il_entries[: int(limit)]

    # 3. Match titles. Triage misses to a review/ prefix.
    matches = {m.il_title: m for m in best_matches(
        [e.title for e in il_entries],
        list(uesp_by_title.keys()),
    )}
    unmatched = [m for m in matches.values() if m.uesp_title is None]
    if unmatched:
        s3.put_object(
            Bucket=raw_bucket,
            Key=f"review/{game}-unmatched-{datetime.now(UTC):%Y%m%dT%H%M%S}.json",
            Body=json.dumps([m.__dict__ for m in unmatched], indent=2).encode(),
        )
        log.warning("unmatched: %d titles", len(unmatched))

    # 4. Fetch each book, dedupe, persist.
    written = 0
    skipped = 0
    with polite_client() as client:
        for entry in il_entries:
            try:
                book = fetch_book(client, entry)
            except Exception:
                log.exception("fetch failed: %s", entry.url)
                continue

            book_id = slugify(book.title)
            chash = _content_hash(book.text)

            existing = table.get_item(Key={"book_id": book_id}).get("Item")
            if existing and existing.get("content_hash") == chash:
                skipped += 1
                continue

            # Cache raw HTML (90-day lifecycle on the bucket).
            s3.put_object(
                Bucket=raw_bucket,
                Key=f"imperial/{game}/{book_id}.html",
                Body=book.raw_html.encode("utf-8"),
                ContentType="text/html; charset=utf-8",
            )
            text_key = f"{game}/{book_id}.json"
            s3.put_object(
                Bucket=texts_bucket,
                Key=text_key,
                Body=json.dumps({
                    "title": book.title,
                    "text": book.text,
                    "source_url": book.url,
                }).encode("utf-8"),
                ContentType="application/json",
            )

            uesp = uesp_by_title.get(matches[entry.title].uesp_title or "")
            record = BookRecord(
                book_id=book_id,
                title=book.title,
                game=game,
                author=uesp.author if uesp else None,
                summary=uesp.summary if uesp else None,
                in_game_locations=[
                    InGameLocation(notes=loc) for loc in (uesp.locations if uesp else [])
                ],
                text_s3_key=text_key,
                imperial_library_url=book.url,
                uesp_url=uesp.url if uesp else None,
                word_count=len(book.text.split()),
                char_count=len(book.text),
                content_hash=chash,
                ingested_at=datetime.now(UTC),
            )
            table.put_item(Item=record.to_dynamo())
            written += 1

    log.info("ingest done: written=%d skipped=%d unmatched=%d", written, skipped, len(unmatched))
    return {"written": written, "skipped": skipped, "unmatched": len(unmatched)}
