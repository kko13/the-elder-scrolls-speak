from __future__ import annotations

import os
import time
from collections.abc import Iterator
from contextlib import contextmanager

import httpx

DEFAULT_UA = "tes-speak-ingest/0.1 (+https://github.com/your-org/the-elder-scrolls-speak)"


@contextmanager
def polite_client(*, base_url: str = "", min_interval_sec: float = 1.0) -> Iterator[httpx.Client]:
    """httpx client with a fixed delay between requests.

    Single-threaded ingestion, so we sleep before every request to keep traffic
    well below 1 req/s. Crude but sufficient for one-shot crawls.
    """
    last = [0.0]

    def _sleep(_request: httpx.Request) -> None:
        elapsed = time.monotonic() - last[0]
        if elapsed < min_interval_sec:
            time.sleep(min_interval_sec - elapsed)
        last[0] = time.monotonic()

    client = httpx.Client(
        base_url=base_url,
        headers={"User-Agent": os.environ.get("USER_AGENT", DEFAULT_UA)},
        timeout=httpx.Timeout(30.0, connect=10.0),
        follow_redirects=True,
        event_hooks={"request": [_sleep]},
    )
    try:
        yield client
    finally:
        client.close()
