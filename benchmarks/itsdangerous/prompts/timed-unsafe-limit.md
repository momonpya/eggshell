The preceding stages added a serialized-byte limit and bounded URL-safe
inflation. Carry `max_payload_bytes` through all loading entry points:
`load`, `loads_unsafe`, `load_unsafe`, and the TimedSerializer overrides of
`loads` and `loads_unsafe`. It remains keyword-only and follows the preceding
validation and byte-counting rules. File loaders must forward salt and timed
options by keyword to the actual subclass.

The limit excludes timestamp and signature framing. Preserve key rotation,
fallback signers, custom salts, `max_age`, and `return_timestamp`. An expired
token must still raise `SignatureExpired` before decoding its payload, and
must not continue to another signer after verified expiry.

Unsafe recovery must apply the limit both when normal verification succeeds
and when recovering a bad-signature or expired token's payload. Within the
limit, preserve `(True, value)` for valid signatures and `(False, value)` for
recoverable invalid or expired signatures. An oversized authenticated payload
raises `BadPayload`, as normal loading does. Oversized invalid/expired payloads
return `(False, None)` without invoking the data deserializer or unbounded
inflation. Invalid limit arguments still raise `ValueError`. Preserve existing
default-`None` behavior and legacy loader overrides.

Work only in `src/itsdangerous/`. Preserve existing tests, configuration and
dependencies and both preceding features. You may run upstream tests and
temporary checks outside the repository. Explain your change and report
commands you actually ran.
