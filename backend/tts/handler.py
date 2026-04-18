"""Two handlers wrapped in one package:

* `submit`   — DynamoDB stream consumer. Triggers a Polly async task per
               new/changed book that lacks an `audio_s3_key`.
* `complete` — SNS subscriber. Polly publishes when each task finishes; we
               update the book record with the audio key.

Polly's long-form engine accepts up to ~100k characters per request and writes
the MP3 directly to S3 — no chunk-and-stitch needed for in-game books.
"""

from __future__ import annotations

import json
import logging
import os
from datetime import UTC, datetime

import boto3

from shared.dynamo import get_book, update_book

from .voices import voice_for_author

log = logging.getLogger()
log.setLevel(logging.INFO)

s3 = boto3.client("s3")
polly = boto3.client("polly")

MAX_LONG_FORM_CHARS = 100_000


def _load_text(texts_bucket: str, key: str) -> str:
    obj = s3.get_object(Bucket=texts_bucket, Key=key)
    return json.loads(obj["Body"].read())["text"]


def _audio_key(book_id: str) -> str:
    return f"{book_id}.mp3"


def submit(event: dict, _ctx) -> dict:
    """DynamoDB stream batch handler."""
    texts_bucket = os.environ["TEXTS_BUCKET"]
    audio_bucket = os.environ["AUDIO_BUCKET"]
    sns_topic = os.environ["SNS_TOPIC_ARN"]
    engine = os.environ.get("DEFAULT_ENGINE", "long-form")

    submitted = 0
    for record in event.get("Records", []):
        if record.get("eventName") not in ("INSERT", "MODIFY"):
            continue

        new_image = record.get("dynamodb", {}).get("NewImage") or {}
        # DDB stream image is in low-level format; we re-fetch the item via SDK
        # to avoid hand-deserialising every attribute.
        book_id = new_image.get("book_id", {}).get("S")
        if not book_id:
            continue

        item = get_book(book_id)
        if not item or not item.get("text_s3_key"):
            continue

        # Skip if audio is already in place AND content hasn't changed.
        if item.get("audio_s3_key"):
            old_image = record.get("dynamodb", {}).get("OldImage") or {}
            old_hash = old_image.get("content_hash", {}).get("S")
            if old_hash == item.get("content_hash"):
                continue

        text = _load_text(texts_bucket, item["text_s3_key"])
        if len(text) > MAX_LONG_FORM_CHARS:
            log.warning(
                "book %s exceeds %d chars (%d) — truncating",
                book_id, MAX_LONG_FORM_CHARS, len(text),
            )
            text = text[:MAX_LONG_FORM_CHARS]

        voice = voice_for_author(item.get("author"))
        try:
            resp = polly.start_speech_synthesis_task(
                Engine=engine,
                OutputFormat="mp3",
                OutputS3BucketName=audio_bucket,
                OutputS3KeyPrefix=f"raw/{book_id}/",
                SnsTopicArn=sns_topic,
                Text=text,
                VoiceId=voice,
            )
        except Exception:
            log.exception("polly submit failed: %s", book_id)
            continue

        task_id = resp["SynthesisTask"]["TaskId"]
        update_book(book_id, {
            "voice_id": voice,
            "tts_task_id": task_id,
        })
        submitted += 1
        log.info("submitted polly task: book=%s task=%s voice=%s", book_id, task_id, voice)

    return {"submitted": submitted}


def complete(event: dict, _ctx) -> dict:
    """SNS subscriber — Polly publishes one notification per finished task."""
    audio_bucket = os.environ["AUDIO_BUCKET"]
    updated = 0
    for record in event.get("Records", []):
        msg = json.loads(record["Sns"]["Message"])
        if msg.get("taskStatus") != "completed":
            log.warning("polly task not complete: %s", msg)
            continue

        task_id = msg["taskId"]
        # Output uri looks like: s3://bucket/raw/<book_id>/<task_id>.mp3
        uri = msg["outputUri"]
        prefix = f"s3://{audio_bucket}/raw/"
        if not uri.startswith(prefix):
            log.warning("unexpected outputUri: %s", uri)
            continue
        rest = uri[len(prefix):]
        book_id, raw_filename = rest.split("/", 1)

        # Move to the canonical key so signed URLs are stable per book.
        target_key = _audio_key(book_id)
        s3.copy_object(
            Bucket=audio_bucket,
            Key=target_key,
            CopySource={"Bucket": audio_bucket, "Key": f"raw/{book_id}/{raw_filename}"},
            ContentType="audio/mpeg",
            MetadataDirective="REPLACE",
        )
        s3.delete_object(Bucket=audio_bucket, Key=f"raw/{book_id}/{raw_filename}")

        update_book(book_id, {
            "audio_s3_key": target_key,
            "tts_generated_at": datetime.now(UTC).isoformat(),
        })
        updated += 1
        log.info("audio promoted: book=%s key=%s task=%s", book_id, target_key, task_id)

    return {"updated": updated}
