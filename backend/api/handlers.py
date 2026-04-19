"""HTTP API behind API Gateway. Single Lambda, thin router.

Routes:
    GET /health
    GET /games
    GET /authors                  ?game=skyrim
    GET /books                    ?game=skyrim&author=...&limit=50&cursor=...
    GET /books/{book_id}
"""

from __future__ import annotations

import json
import logging
import os
from collections import defaultdict
from typing import Any

import boto3
from boto3.dynamodb.conditions import Key

from .signing import signed_audio_url

log = logging.getLogger()
log.setLevel(logging.INFO)

ddb = boto3.resource("dynamodb")
_TABLE = None


def _table():
    global _TABLE
    if _TABLE is None:
        _TABLE = ddb.Table(os.environ["BOOKS_TABLE"])
    return _TABLE


def _ok(body: Any, *, status: int = 200) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body, default=str),
    }


def _not_found(msg: str = "not found") -> dict:
    return _ok({"error": msg}, status=404)


# ---------- handlers ----------

def health(_event: dict) -> dict:
    return _ok({"ok": True})


def list_games(_event: dict) -> dict:
    # Trivial — derived from a constant for now; we only ship Skyrim at MVP.
    return _ok({"games": [{"id": "skyrim", "label": "Skyrim"}]})


def list_authors(event: dict) -> dict:
    game = (event.get("queryStringParameters") or {}).get("game", "skyrim")
    counts: dict[str, int] = defaultdict(int)
    last_eval = None
    while True:
        kwargs = {
            "IndexName": "game-title-index",
            "KeyConditionExpression": Key("game").eq(game),
            "ProjectionExpression": "author",
        }
        if last_eval:
            kwargs["ExclusiveStartKey"] = last_eval
        page = _table().query(**kwargs)
        for item in page.get("Items", []):
            counts[item.get("author") or "Unknown"] += 1
        last_eval = page.get("LastEvaluatedKey")
        if not last_eval:
            break
    authors = sorted(({"name": a, "book_count": c} for a, c in counts.items()),
                     key=lambda x: (-x["book_count"], x["name"]))
    return _ok({"authors": authors})


def list_books(event: dict) -> dict:
    qs = event.get("queryStringParameters") or {}
    game = qs.get("game", "skyrim")
    author = qs.get("author")
    limit = min(int(qs.get("limit", "50")), 200)
    cursor = qs.get("cursor")

    kwargs: dict[str, Any] = {
        "IndexName": "game-title-index",
        "KeyConditionExpression": Key("game").eq(game),
        "Limit": limit,
        "ProjectionExpression": "book_id, title, author, audio_duration_sec, voice_id, summary",
    }
    if cursor:
        kwargs["ExclusiveStartKey"] = json.loads(cursor)

    page = _table().query(**kwargs)
    items = page.get("Items", [])
    if author:
        items = [i for i in items if i.get("author") == author]

    next_cursor = json.dumps(page["LastEvaluatedKey"]) if page.get("LastEvaluatedKey") else None
    return _ok({"books": items, "next_cursor": next_cursor})


def get_book(event: dict) -> dict:
    book_id = event["pathParameters"]["book_id"]
    item = _table().get_item(Key={"book_id": book_id}).get("Item")
    if not item:
        return _not_found(f"book {book_id} not found")

    audio = None
    if item.get("audio_s3_key"):
        url, expires = signed_audio_url(item["audio_s3_key"])
        audio = {"url": url, "expires_at": expires.isoformat()}

    return _ok({
        "book": {
            **item,
            "audio": audio,
        },
    })


# ---------- router ----------
#
# API Gateway is configured with a single `ANY /{proxy+}` route, so every
# request lands here. We dispatch on (method, parsed path).

def lambda_handler(event: dict, _ctx) -> dict:
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    raw_path = event.get("rawPath", "/")
    parts = raw_path.strip("/").split("/")

    try:
        if method == "GET":
            if parts == ["health"]:
                return health(event)
            if parts == ["games"]:
                return list_games(event)
            if parts == ["authors"]:
                return list_authors(event)
            if parts == ["books"]:
                return list_books(event)
            if len(parts) == 2 and parts[0] == "books":
                event.setdefault("pathParameters", {})["book_id"] = parts[1]
                return get_book(event)
    except Exception:
        log.exception("handler error: %s %s", method, raw_path)
        return _ok({"error": "internal error"}, status=500)

    return _not_found(f"no route for {method} {raw_path}")
