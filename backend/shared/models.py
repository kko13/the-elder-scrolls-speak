from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

Game = Literal["skyrim", "morrowind", "oblivion", "eso", "daggerfall", "arena"]


class InGameLocation(BaseModel):
    region: str | None = None
    cell: str | None = None
    notes: str | None = None


class BookRecord(BaseModel):
    """Canonical record stored in DynamoDB."""

    book_id: str
    title: str
    game: Game
    author: str | None = None
    summary: str | None = None
    in_game_locations: list[InGameLocation] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)

    text_s3_key: str | None = None
    audio_s3_key: str | None = None
    audio_duration_sec: float | None = None
    voice_id: str | None = None

    word_count: int | None = None
    char_count: int | None = None

    imperial_library_url: str | None = None
    uesp_url: str | None = None

    content_hash: str | None = None
    ingested_at: datetime | None = None
    tts_generated_at: datetime | None = None

    def to_dynamo(self) -> dict:
        # Pydantic gives us a dict; DynamoDB doesn't accept None values, so strip them.
        raw = self.model_dump(mode="json", exclude_none=True)
        return raw
