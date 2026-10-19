import sys
import zlib

import pytest

from itsdangerous import BadPayload, URLSafeSerializer
from itsdangerous.encoding import base64_encode


@pytest.mark.parametrize("value", [{"v": "é🐣"}, "a" * 8192])
def test_decoded_not_wire_size(value):
    serializer = URLSafeSerializer("test-key", serializer_kwargs={"ensure_ascii": False})
    raw = serializer.serializer.dumps(value, **serializer.serializer_kwargs).encode()
    token = serializer.dumps(value)
    assert len(serializer.dump_payload(value)) != len(raw)
    assert serializer.loads(token, max_payload_bytes=len(raw)) == value
    with pytest.raises(BadPayload):
        serializer.loads(token, max_payload_bytes=len(raw) - 1)
    assert serializer.loads(token, max_payload_bytes=sys.maxsize + 1000) == value


@pytest.mark.parametrize("cut", [1, 2, 5])
def test_truncated_stream_is_not_complete_json(cut):
    serializer = URLSafeSerializer("test-key")
    raw = b'"' + b"a" * 4096 + b'"'
    payload = b"." + base64_encode(zlib.compress(raw)[:-cut])
    with pytest.raises(BadPayload):
        serializer.load_payload(payload, max_payload_bytes=len(raw))


def test_trailing_data_keeps_existing_single_stream_behavior():
    serializer = URLSafeSerializer("test-key")
    raw = b'{"ok":true}'
    payload = b"." + base64_encode(zlib.compress(raw) + b"trailing bytes")
    assert serializer.load_payload(payload) == {"ok": True}
    assert serializer.load_payload(payload, max_payload_bytes=len(raw)) == {"ok": True}


@pytest.mark.parametrize("limit", [0, 32])
def test_inflation_is_bounded_before_the_limit_check(monkeypatch, limit):
    serializer = URLSafeSerializer("test-key")
    token = serializer.dumps("x" * (2 * 1024 * 1024))
    original_decompress = zlib.decompress
    original_object = zlib.decompressobj
    calls = []
    produced = []

    def unbounded(*args, **kwargs):
        calls.append(("unbounded", 0))
        return original_decompress(*args, **kwargs)

    class Observed:
        def __init__(self, *args, **kwargs):
            self.inner = original_object(*args, **kwargs)

        def __getattr__(self, name):
            return getattr(self.inner, name)

        def decompress(self, data, max_length=0):
            calls.append(("bounded", max_length))
            output = self.inner.decompress(data, max_length)
            produced.append(len(output))
            return output

        def flush(self, *args, **kwargs):
            calls.append(("flush", 0))
            return self.inner.flush(*args, **kwargs)

    monkeypatch.setattr(zlib, "decompress", unbounded)
    monkeypatch.setattr(zlib, "decompressobj", Observed)
    with pytest.raises(BadPayload):
        serializer.loads(token, max_payload_bytes=limit)
    assert calls and all(kind == "bounded" and 0 < size <= limit + 1 for kind, size in calls)
    assert sum(produced) <= limit + 1


@pytest.mark.parametrize("limit", [-1, True, "1"])
def test_url_safe_direct_validation(limit):
    serializer = URLSafeSerializer("test-key")
    with pytest.raises(ValueError):
        serializer.load_payload(serializer.dump_payload("small"), max_payload_bytes=limit)
