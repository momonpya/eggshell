import hashlib

import pytest

from itsdangerous import BadPayload, BadSignature, Serializer


@pytest.mark.parametrize("value", [{"a": 1}, "é🐣", [1, 2, 3], None])
def test_serialized_byte_boundary(value):
    serializer = Serializer("test-key", serializer_kwargs={"ensure_ascii": False})
    token = serializer.dumps(value)
    size = len(serializer.dump_payload(value))
    assert serializer.loads(token, max_payload_bytes=size) == value
    assert serializer.loads(token.encode(), max_payload_bytes=size + 1) == value
    with pytest.raises(BadPayload):
        serializer.loads(token, max_payload_bytes=size - 1)
    assert serializer.loads(token, max_payload_bytes=None) == value


@pytest.mark.parametrize("limit", [-1, -99, True, False, 1.5, "10", b"10"])
def test_invalid_limit(limit):
    serializer = Serializer("test-key")
    with pytest.raises(ValueError):
        serializer.loads(serializer.dumps({}), max_payload_bytes=limit)
    with pytest.raises(ValueError):
        serializer.load_payload(b"{}", max_payload_bytes=limit)


class BinaryCodec:
    def __init__(self):
        self.calls = []

    def dumps(self, obj):
        return obj if isinstance(obj, bytes) else b"{}"

    def loads(self, payload):
        self.calls.append(payload)
        return payload


def test_binary_zero_and_no_callback_after_overflow():
    codec = BinaryCodec()
    serializer = Serializer("test-key", serializer=codec)
    assert serializer.loads(serializer.dumps(b""), max_payload_bytes=0) == b""
    codec.calls.clear()
    with pytest.raises(BadPayload):
        serializer.loads(serializer.dumps(b"\xff\x00"), max_payload_bytes=1)
    assert codec.calls == []
    assert serializer.load_payload(b"\xff\x00", max_payload_bytes=2) == b"\xff\x00"


def test_authentication_precedes_payload_decoding():
    token = Serializer("other-key").dumps("large" * 10)
    with pytest.raises(BadSignature):
        Serializer("test-key").loads(token, max_payload_bytes=0)


def test_rotation_and_fallback_keep_limit():
    old = Serializer("old", signer_kwargs={"digest_method": hashlib.sha1})
    serializer = Serializer(["old", "new"], signer_kwargs={"digest_method": hashlib.sha256},
                            fallback_signers=[{"digest_method": hashlib.sha1}])
    token = old.dumps({"value": "prior data"})
    size = len(old.dump_payload({"value": "prior data"}))
    assert serializer.loads(token, max_payload_bytes=size) == {"value": "prior data"}
    with pytest.raises(BadPayload):
        serializer.loads(token, max_payload_bytes=size - 1)


def test_none_preserves_legacy_payload_override():
    class Legacy(Serializer):
        def load_payload(self, payload, serializer=None):
            return super().load_payload(payload, serializer)

    serializer = Legacy("test-key")
    token = serializer.dumps({"ok": True})
    assert serializer.loads(token) == {"ok": True}
    assert serializer.loads(token, max_payload_bytes=None) == {"ok": True}
