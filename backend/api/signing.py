"""Generate CloudFront canned-policy signed URLs for audio.

Uses the RSA private key stored in Secrets Manager (provisioned by the
`frontend` Terraform module). Cached in module scope so warm Lambda
invocations don't repeatedly fetch the secret.
"""

from __future__ import annotations

import base64
import json
import os
import time
from datetime import UTC, datetime, timedelta
from functools import lru_cache

import boto3
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding


@lru_cache(maxsize=1)
def _private_key():
    arn = os.environ["CLOUDFRONT_PRIVATE_KEY_SECRET_ARN"]
    pem = boto3.client("secretsmanager").get_secret_value(SecretId=arn)["SecretString"]
    return serialization.load_pem_private_key(pem.encode(), password=None)


def _b64(data: bytes) -> str:
    # CloudFront uses URL-safe base64 with `+/=` mapped to `-_~`.
    return base64.b64encode(data).decode().translate(str.maketrans("+/=", "-_~"))


def sign_url(url: str, ttl_seconds: int) -> str:
    expires = int(time.time()) + ttl_seconds
    policy = json.dumps({
        "Statement": [{
            "Resource": url,
            "Condition": {"DateLessThan": {"AWS:EpochTime": expires}},
        }],
    }, separators=(",", ":")).encode()

    signature = _private_key().sign(policy, padding.PKCS1v15(), hashes.SHA1())
    key_pair_id = os.environ["CLOUDFRONT_KEY_PAIR_ID"]

    sep = "&" if "?" in url else "?"
    return (
        f"{url}{sep}Expires={expires}"
        f"&Signature={_b64(signature)}"
        f"&Key-Pair-Id={key_pair_id}"
    )


def signed_audio_url(audio_key: str) -> tuple[str, datetime]:
    domain = os.environ["CLOUDFRONT_AUDIO_DOMAIN"]
    ttl = int(os.environ.get("SIGNED_URL_TTL_SECONDS", "3600"))
    url = sign_url(f"https://{domain}/{audio_key}", ttl)
    expires_at = datetime.now(UTC) + timedelta(seconds=ttl)
    return url, expires_at
