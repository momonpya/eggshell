The preceding stage added `max_payload_bytes` to the base Serializer. Extend
the URL-safe payload path to enforce that same limit on decoded, decompressed
serialized bytes, not on the base64 text or compressed input size.

For a configured limit, zlib expansion itself must be bounded: request at
most limit-plus-one output bytes in total across all calls, reject overflow
before deserialization, and
do not call an unbounded decompressor or flush pending output. Handle zero
and integers larger than the platform's native size without accidental
unlimited expansion or integer overflow. Reject truncated or malformed streams
with `BadPayload`, and preserve the existing treatment of trailing data.
Uncompressed URL-safe payloads, UTF-8 byte boundaries, exact-limit success,
argument validation and the default `None` behavior must still work.

Work only in `src/itsdangerous/`. Preserve the existing tests, configuration
and dependencies and keep the preceding stage's base-Serializer feature.
You may run upstream tests and temporary checks outside the repository.
Timed wrappers, file loaders and unsafe recovery remain a follow-up task.
Explain your change and report commands you actually ran.
