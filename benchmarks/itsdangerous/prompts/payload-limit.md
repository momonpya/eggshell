Add an optional keyword-only `max_payload_bytes` to `Serializer.loads` and
`Serializer.load_payload`. It limits the serialized payload bytes passed to
the data deserializer, excluding the signature and salt. `None` keeps the
existing behavior. A nonnegative integer is valid, including zero; booleans,
negative values and other types raise `ValueError`.

Accept a payload exactly at the limit and reject an oversized payload with
`BadPayload` before invoking the data deserializer. Count UTF-8 bytes for text,
not Unicode code points. Binary serializers and a valid empty binary payload
must work. Verify the signature before enforcing payload size; a wrong key
still raises `BadSignature`, even if its payload would exceed the size limit.
Existing key rotation, fallback signers and serializer overrides must continue
to work. Do not forward a new keyword to an existing `load_payload` override
when the limit is `None`.

Work only in `src/itsdangerous/`. Preserve the existing tests, configuration
and dependencies. You may run the upstream tests and temporary checks outside
the repository. Changes to compressed decoding, timed wrappers, file loaders
and unsafe recovery are separate follow-up tasks. Explain your change and
report commands you actually ran.
