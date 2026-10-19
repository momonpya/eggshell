# DB cache lifetime

DB-contained vectors and index tickets live under
`DB/derived/<database identity>/`. Removing that DB removes its contained
derived data. Read-only sources use the user's
`read-cache/<database identity>/` overlay. Questions remain in the independent
private `queries/` cache.

An overlay records observed DB locations in `owners/<owner digest>.json`.
Each record contains only the DB identity and absolute directory. A digest
nominates a slot; reading checks the complete record, its slot and its DB
directory. Private preparation records an owner before writing vectors or
tickets. Cache lookup, explicit warm/doctor and remembered index targets also
observe an existing overlay, so a currently used copy retains the shared
derived data. Registration changes private metadata only.

A missing DB directory or a successfully opened replacement with another
identity retires that location. An unreadable head, permission failure or
malformed owner record retains the overlay. Unknown overlays without ownership
records also remain: deletion cannot be inferred from an unknown location.
Warm or lookup against a known source attaches its current location. An
unobserved move/copy is not a registered live location; the next explicit warm
can rebuild its hints from that DB.

The installation-wide index maintenance lane runs reclamation before draining
index work, using a short time allocation. Most live roots are filtered without
an exclusive claim. A possible orphan takes the stable private
`cache-owners.guard` exclusively and rechecks ownership. Registrations share
that claim and wait at most 25 ms for admission. An active per-DB index claim
defers retirement. Neither claim acquires the graph writer or a session lock.

Dead location records are retired at most 64 per root in one sweep. The final
checked record remains until the directory is atomically renamed to a unique
`.retired-<identity>-<nonce>` sibling. This allows progress after many moves or
copies, and after interruption, while fencing new registrations. A replacement
DB at the same pathname retains its own separate overlay.

Retired trees are pruned in native descriptor-relative steps of at most 128
entries, with a finite directory-depth bound. Every directory open uses
`O_NOFOLLOW`; a symlink child is unlinked as a leaf. Deletion resumes from the
retired directory on later maintenance turns. This keeps large cleanup work
out of foreground hooks. Private cache files owned by a DB use the same
existing-parent atomic publisher as DB-contained files: a concurrent retirement
cannot make a late write recreate an ownerless parent directory.

`eggshell_tests cache-reclaim-tests` requires an isolated absolute
`EGGSHELL_DATA_ROOT`. It checks read-only copy registration, last registered
copy removal, changed DB identity, damaged heads/owners, index and registration
claims, incremental old-route removal, bounded resumed deletion, symlink
protection, retirement during publication, late writes and recovery by the
production daemon without a pending turn or index-provider registration.

This is an isolated development candidate. Cache lifetime checks and the fixed
latency diagnostic do not establish inclusive-token or answer-quality adoption
against the latest public release, and do not complete the paper goal.
