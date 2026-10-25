# Retiring unused study data

On 2026-10-26 the user requested removal of unnecessary DBs and caches, without
archives. `tools/research/RetireUnusedStudyData.lean` inspected the explicit old
experiment/demo/test roots, excluding the current study, shared MiniLM support,
source/build directories and symbolic-link targets. The inspected 38 targets
were then deleted: old DB files and cache remnants, plus three retired reranker
model caches. The embedding model and numeric runtime were retained.

The existing `DB.Sidecar.collect` then checked registered DB copies under its
registry/index claims. All 81 remaining private cache roots had dead owners and
were removed. Unknown, live or unreadable owners would have been retained.
Original session journals were not removed.

Evidence is in
`/Users/ovm/.codex/experiments/eggshell/study-services-20261026`:

- `unused-inspect.json`: inspected target paths and logical sizes.
- `unused-delete.json` and `unused-delete.result.json`: 38 targets totalling
  267,263,296 logical bytes, plus 4,733,769 bytes of dead-owner cache data.
- `cleanup-build.guard.json`, `cleanup-inspect.guard.json` and
  `cleanup-delete.guard.json`: successful exits and no owned processes left;
  sampled aggregate RSS was 1,333,152 / 81,008 / 81,584 KiB respectively.

The removed logical size is 271,997,065 bytes (about 259 MiB). It is not a claim
about reclaimed APFS physical extents. Free space was already about 11 GiB at
the beginning of this cleanup, before any deletion in this run. No compressed
archive was created. Source, metrics and the small deletion manifest remain.

Real-seed preparation initially failed before any answering-model process
started: its output parent `study/` did not exist, so `df` returned no rows.
The failed `seed-1.guard.json` and stderr remain. The preparation helper now
creates the parent before sealing a plan and accepts distinct attempt labels;
the next attempt uses `seed-1-ready.*`. The product runtime is unchanged.
