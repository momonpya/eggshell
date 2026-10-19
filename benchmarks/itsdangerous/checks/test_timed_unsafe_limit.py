import hashlib
import io
from datetime import timedelta

import pytest
from freezegun import freeze_time

from itsdangerous import BadPayload, BadSignature, Serializer, TimedSerializer
from itsdangerous import URLSafeSerializer, URLSafeTimedSerializer
from itsdangerous.timed import TimestampSigner


CLASSES = [Serializer, URLSafeSerializer, TimedSerializer, URLSafeTimedSerializer]
METHODS = ["loads", "load", "loads_unsafe", "load_unsafe"]


@pytest.fixture(autouse=True)
def clock():
    with freeze_time("2030-01-02 03:04:05") as frozen:
        yield frozen


def invoke(serializer, method, token, **kwargs):
    if method in ("load", "load_unsafe"):
        token = io.StringIO(token) if isinstance(token, str) else io.BytesIO(token)
    return getattr(serializer, method)(token, **kwargs)


def serialized_size(serializer, value):
    raw = serializer.serializer.dumps(value, **serializer.serializer_kwargs)
    return len(raw.encode() if isinstance(raw, str) else raw)


@pytest.mark.parametrize("cls", CLASSES)
@pytest.mark.parametrize("method", METHODS)
def test_authenticated_boundary_and_custom_salt(cls, method):
    serializer = cls("test-key", serializer_kwargs={"ensure_ascii": False})
    value = {"v": "é🐣" * 200}
    size = serialized_size(serializer, value)
    token = serializer.dumps(value, salt="task-salt")
    options = {"salt": "task-salt", "max_payload_bytes": size}
    if isinstance(serializer, TimedSerializer):
        options["max_age"] = 10
    expected = (True, value) if "unsafe" in method else value
    assert invoke(serializer, method, token, **options) == expected
    options["max_payload_bytes"] = size - 1
    with pytest.raises(BadPayload):
        invoke(serializer, method, token, **options)


@pytest.mark.parametrize("cls", CLASSES)
@pytest.mark.parametrize("method", ["loads_unsafe", "load_unsafe"])
def test_bad_signature_salvage_is_also_bounded(cls, method):
    serializer = cls("test-key")
    foreign = cls("other-key")
    value = "v" * 8192
    token = foreign.dumps(value)
    size = serialized_size(serializer, value)
    assert invoke(serializer, method, token, max_payload_bytes=size) == (False, value)
    assert invoke(serializer, method, token, max_payload_bytes=size - 1) == (False, None)


@pytest.mark.parametrize("cls", [TimedSerializer, URLSafeTimedSerializer])
@pytest.mark.parametrize("method", ["loads", "load"])
def test_expiry_precedes_payload_size_and_stops_fallback(cls, method, clock):
    calls = []

    class Fallback(TimestampSigner):
        def unsign(self, *args, **kwargs):
            calls.append(True)
            return super().unsign(*args, **kwargs)

    serializer = cls("test-key", fallback_signers=[Fallback])
    token = serializer.dumps("large" * 100)
    clock.tick(timedelta(seconds=11))
    with pytest.raises(BadSignature) as caught:
        invoke(serializer, method, token, max_age=10, max_payload_bytes=0)
    from itsdangerous import SignatureExpired
    assert isinstance(caught.value, SignatureExpired)
    assert caught.value.date_signed.tzinfo is not None
    assert calls == []


@pytest.mark.parametrize("cls", [TimedSerializer, URLSafeTimedSerializer])
@pytest.mark.parametrize("method", ["loads_unsafe", "load_unsafe"])
def test_expired_salvage_respects_size(cls, method, clock):
    serializer = cls("test-key")
    value = "large" * 100
    token = serializer.dumps(value)
    size = serialized_size(serializer, value)
    clock.tick(timedelta(seconds=11))
    assert invoke(serializer, method, token, max_age=10, max_payload_bytes=size) == (False, value)
    assert invoke(serializer, method, token, max_age=10, max_payload_bytes=size - 1) == (False, None)


@pytest.mark.parametrize("cls", [TimedSerializer, URLSafeTimedSerializer])
def test_return_timestamp_and_rotated_fallback(cls, clock):
    old = cls("old", signer_kwargs={"digest_method": hashlib.sha1})
    serializer = cls(["old", "new"], signer_kwargs={"digest_method": hashlib.sha256},
                     fallback_signers=[{"digest_method": hashlib.sha1}])
    token = old.dumps({"v": "old data"})
    value, timestamp = serializer.loads(token, return_timestamp=True, max_payload_bytes=100)
    assert value == {"v": "old data"} and timestamp.tzinfo is not None
    assert serializer.load(io.StringIO(token), max_age=10, return_timestamp=True,
                           max_payload_bytes=100) == (value, timestamp)


@pytest.mark.parametrize("cls", CLASSES)
@pytest.mark.parametrize("method", METHODS)
@pytest.mark.parametrize("limit", [-1, True, 1.5])
def test_all_entry_points_validate(cls, method, limit):
    serializer = cls("test-key")
    with pytest.raises(ValueError):
        invoke(serializer, method, serializer.dumps({}), max_payload_bytes=limit)


def test_default_none_keeps_legacy_loader_overrides():
    class Legacy(Serializer):
        def loads(self, s, salt=None):
            return super().loads(s, salt)

        def loads_unsafe(self, s, salt=None):
            return super().loads_unsafe(s, salt)

    serializer = Legacy("test-key")
    token = serializer.dumps({"v": 1})
    assert serializer.load(io.StringIO(token)) == {"v": 1}
    assert serializer.load_unsafe(io.StringIO(token), max_payload_bytes=None) == (True, {"v": 1})
