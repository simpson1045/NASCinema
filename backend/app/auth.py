"""Password hashing (scrypt) and signed tokens (itsdangerous).

Ported in concept from NASRadio: scrypt for passwords, itsdangerous signed
tokens for sessions, and a separate scoped token for media URLs that can play
but can't touch the library.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import os

from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

from .config import get_settings

# scrypt cost parameters (RFC 7914). Tunable; these are a sane interactive default.
_N = 2**14
_R = 8
_P = 1
_DKLEN = 32


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    dk = hashlib.scrypt(password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=_DKLEN)
    return "scrypt${}${}".format(
        base64.b64encode(salt).decode(), base64.b64encode(dk).decode()
    )


def verify_password(password: str, stored: str) -> bool:
    try:
        scheme, salt_b64, dk_b64 = stored.split("$")
        if scheme != "scrypt":
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(dk_b64)
    except (ValueError, TypeError):
        return False
    actual = hashlib.scrypt(
        password.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=len(expected)
    )
    return hmac.compare_digest(actual, expected)


def _serializer(salt: str) -> URLSafeTimedSerializer:
    return URLSafeTimedSerializer(get_settings().secret_key, salt=salt)


def create_session_token(user_id: int, token_version: int) -> str:
    """Bearer token proving who the user is."""
    return _serializer("session").dumps({"uid": user_id, "tv": token_version})


def verify_session_token(token: str, max_age: int = 60 * 60 * 24 * 30) -> dict | None:
    try:
        return _serializer("session").loads(token, max_age=max_age)
    except (BadSignature, SignatureExpired):
        return None


def create_media_token(user_id: int, scope: str = "play") -> str:
    """Scoped, read-only token for stream/artwork URLs and share links."""
    return _serializer("media").dumps({"uid": user_id, "scope": scope})


def verify_media_token(token: str, max_age: int = 60 * 60 * 12) -> dict | None:
    try:
        return _serializer("media").loads(token, max_age=max_age)
    except (BadSignature, SignatureExpired):
        return None
