# Content correspondence at capture

Isolated Lean component; not a production adoption. Actual hook delivery remains
below the 95% gate. The preceding selector variants remain failed experiments
in [focus-domain.md](focus-domain.md); they are not prerequisites to carry into
the next runtime.

`SynapseSource.recordedRows` still recognizes source coordinates through a
literal shell-command plan. Handling opaque original output separately did not
remove that condition from source sharing and graph construction. The new
boundary uses the actually acquired input contents and original output records.
It receives no command name, Git identity or human reference.

Inputs can be immutable original tool observations themselves, including MCP
scalar/field records. A file counterpart is optional. The canonical record and
three relation views must not require a successful file-coordinate alias. File
and resource locations supplement original-record addresses only when their
correspondence has actually been checked.

## Implemented component

[ContentCorrespondence.lean](candidates/content-correspondence/tools/ContentCorrespondence.lean)
provides a complete reference index of immutable input records. An index may
support absence and uniqueness decisions only after its completeness check.
The full original string is the hash-map key, and a returned correspondence
also proves literal equality at its bounded input position. Hash equality alone
does not identify content. Ambiguous repeated records receive no unique source
coordinate. A unique anchor can extend to neighboring records only when the
entire proposed sequence matches; gaps are never filled from a path or command.

The capture implementation need not hold every input record in RAM. It indexes
the bounded observed output, then accepts streamed input records into three
states: absent, one position, ambiguous. Replaying the same immutable position
is idempotent. Different positions are retained as ambiguity. Ordinary Lean
proofs establish associative, commutative and idempotent merging, as well as
unchanged index size and key domain for every streamed input record. Thus a
common record such as `}` cannot accumulate an unbounded posting list.

[Checks.lean](candidates/content-correspondence/Checks.lean) passes with Lean
4.33.0 and warnings as errors. It checks Unicode, ambiguity, an incomplete
index, absent opaque MCP data, neighboring literal sequences, changed inputs,
invalid bounds, duplicate replay and distinct locations. For 10,000 input
records and three wanted output records, streaming state remains three entries.
This is a structural bound and a correctness check, not a latency or RSS
benchmark. [Audit.lean](candidates/content-correspondence/Audit.lean) exposes
the proof dependencies; there is no `sorry` or `native_decide` in the component.

[Run.lean](candidates/content-correspondence/Run.lean) takes an absolute candidate
source root, Lean toolchain root and unused output directory. It records the
commands, source hashes, actual check output and proof dependencies. The captured
[review](candidates/content-correspondence-review.json) has aggregate peak RSS
1,040,176 KiB under a 3.5 GiB guard, with no surviving processes. Completed
activation-candidate DB/cache/build data were deleted after extracting the small
records; no archive was created. Existing study input and required build parents
are retained.

## Capture/publication integration still required

1. Normalize original tool observations into records independently of shell
   grammar, retaining original offsets or checked JSON scalar paths. Use those
   immutable records for literal claim/consumption correspondence and the three
   relation views. The client capture adapter supplies actual acquired records,
   allowed scope and identities; any optional file alias needs verified content.
   The component by itself does not verify a
   filesystem, grant access, certify freshness or prove a tool execution.
2. Stream correspondence over captured originals, or combine it with an
   existing bounded fingerprint scan for an optional external input alias.
   Seal EOF, all expected input identities and version stability before accepting
   a one-position result. A prefix of an unfinished scan cannot establish
   uniqueness. Do not import a whole source tree or assume an MCP result has a
   file counterpart. Keep unmatched/ambiguous data under its original record
   identity, with the complete original body retained.
3. Publish correspondence, original bytes and portable origin together before
   durable ACK. Indexes consume that same change feed. A later chat must recover
   the relation from the DB without opening an old workspace or replaying a
   command. Payload deduplication retains all real observations and permissions;
   this content relation does not generate Work equality, Union or completed.
4. Test actual Pre/Post/Stop with mixed commands, opaque/structured MCP output,
   multiple input files, repeated content, unavailable inputs, changed versions,
   restart and DB-only recovery. The streaming adapter's result must be checked
   against the complete reference index on immutable fixtures.
5. Freeze the integrated product, acquire a new empty-DB/new-chat seed, freeze
   DB-present requirements before delivery, and run topics 1/2/3 and lap two.
   The earlier 2/4 result is not erased by a new representation. Adoption still
   requires matched repeated inclusive-token comparisons, quality and deadline
   checks under the current AGENTS instructions.

The adapter, its publication path, actual delivery, full streaming refinement,
team/NAS acceptance and total-token improvement are not established by these
component checks.
