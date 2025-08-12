from __future__ import annotations
from typing import Optional
try:
    import redis  # type: ignore
except ImportError:  # pragma: no cover
    redis = None  # type: ignore

class EventDedupeStore:
    def __init__(self, client, ttl: int) -> None:
        self.client = client
        self.ttl = ttl

    def mark_if_new(self, tenant: str, event_id: str) -> bool:
        key = f"{tenant}:evt:{event_id}"
        # SET key value NX EX ttl -> returns True if set, None if exists
        res = self.client.set(key, "1", nx=True, ex=self.ttl)
        return bool(res)


def build_store(settings) -> Optional[EventDedupeStore]:
    if settings.queue_backend != "redis":
        return None
    if redis is None:
        raise RuntimeError("redis package not installed")
    client = redis.from_url(settings.redis_url, decode_responses=True)
    return EventDedupeStore(client, settings.event_dedupe_ttl)
