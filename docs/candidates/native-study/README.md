# Fixed-runtime cohort restart

Status: preparation only, unadopted. No new answering-model calls or paired
topic trials. This is not evidence of 98% delivery, token improvement or
sustained 80-person performance.

The runtime is unchanged:
`e39c5aa3ee1f8f2e79dc081c33613576145c97a84ee795e9475e61abdd49b6f7`.
The old controller embeds another publication contract. The new controller is
being compiled against the selected runtime's source, with its own private
account, reviewed hook bundle and empty-DB provenance gate. Preparation code
is not yet validated. The first compile failed on a reserved identifier in
the new bootstrap code; that identifier was corrected, but the retry was
refused before startup because free space was below 2,097,152 KiB. No process
is being treated as live from a stale guard record.

Resume the existing `empty-routing-study2.settings.json` after the disk gate
passes. Do not restart paid acquisition or reuse an old seed. Complete the
new-runtime eight-operation native Pre/Post/Stop and source-only recovery
gate; inspect actual App Server model/hook metadata and trust only the exact
isolated bundle; then seal the independent seed cohort before any model call.
Keep the existing matched snapshot/source/question/model/effort/accounting
and prespecified repeated-comparison requirements. Do not substitute small
fixture delivery for LLVM topic trials.

Read-only Lean checks of the corrected bootstrap, cohort sealer and retirement
tool passed. The builder also prepared the retry settings successfully. These
checks create no native executable and do not validate the bootstrap's IO or
replace the remaining native build and integration gates.

Cleanup completed:

- [Build retirement](build-retirement.json): 2,122 unreachable generated files,
  557,358,657 logical bytes. Current link inputs, partial controller objects
  and the live source import closure were retained.
- [Ended study retirement](ended-study-retirement.json): old acquisition DBs,
  R40 history DBs, native-gate DBs, caches and raw logs were deleted. Compact
  acquisition results and usage remain in `ended-seed-1/` and
  `ended-seed-2-isolated/`. Old DB replay is no longer available.
- The old seed costs remain separate: 3,822,461 + 3,172,905 = 6,995,366
  inclusive tokens. No token saving is claimed from this cleanup.
- Retained runtime hashes and sealed harness inputs were checked before and
  after deletion. No compressed archive was created. Logical removed sizes
  do not equal newly available APFS space.

At the last observation the Mac had about 1.75 GiB available, below the 2 GiB
guard floor. Aggregate RSS remains limited to 3,670,016 KiB with the 4 GiB
absolute ceiling. The full goal remains active.
