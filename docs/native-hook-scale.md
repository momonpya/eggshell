# Native hook scale investigation

The prepared-domain candidate does **not** meet the practical latency target.
Opening its catalogue quickly did not remove complete Work admission and
Outcome hydration later in discovery. These are native hook measurements, not
catalogue microbenchmarks, model trials, or a token adoption result.

## Fixed inputs and scope

The isolated complete runtime is `426dd1a710e55e9a65b027b8058655d80df935d483c723b0f8a27bd31df04008`.
It retains MiniLM, the existing ranking, selector, prompt and original-owner
authority checks. The installed study runtime remains unchanged.

`HookScaleFixture.lean` uses the existing RetrievalScale original content, with
4,096 owners per fixture publication instead of 32. It verifies every unique
original window. Changing fixture publication batching is not product compaction
or evidence of a runtime speedup. Every later comparison must share this exact
saved publication, rather than compare against a separately regenerated DB.

| Fixture | Original owners | Unique original windows | Source page bytes | Save time |
| --- | ---: | ---: | ---: | ---: |
| 10k | 9,969 | 10,000 | 55,931,677 | 56,599 ms |
| 50k | 49,969 | 50,000 | 432,031,994 | 606,930 ms |

The 10k source is OS read-only during the native trials. Warm validates 19,969
unique discovery/focus keys, with missing/invalid both zero; its initial full
preparation took 236,446 ms, outside hook timing. Warm and trial guards track
aggregate RSS and stop at 3.5 GiB, below the user's 4 GiB ceiling.

The runner uses real UserPromptSubmit stdin/stdout, a real owned manager,
publication/ACK receipts and actual manager exit. First time includes manager
startup. Continued time uses the same manager and acknowledged native history.
It is not a full Pre/Post/Stop lifecycle, answering-model run or live MCP trial.

## Actual 10k results

| Cohort | First hook | Continued hook | First original body |
| --- | ---: | ---: | ---: |
| Initial diagnostic, query cache cold | 20,474 ms | 18,519 ms | 17,803 UTF-8 bytes |
| Fresh-chat trace, query cache warm | 18,130 ms | 18,460 ms | 17,803 UTF-8 bytes |
| Instrumented, query cache warm | 20,020 ms | 18,302 ms | 17,803 UTF-8 bytes |

Each valid first case has empty prior delivery history and a current receipt
with `initialSearch=true`; continued receipts have `initialSearch=false`.
Their first body SHA-256 is identical:
`5c7a5f72c607710135747e78c438e89e9eb86351fb1fbf8df43772277a8cb264`.
Continued bodies are empty because the same content was already acknowledged;
that is not missing original delivery. All valid replies completed within 30 s.
These diagnostic pairs are **not** a predefined qualification cohort.
The user-confirmed gate is useful delivery and p99 < 30 s on a warmed 50k DB;
3 s was an aspiration, not a requirement. Query-cache and instrumentation
differences must not be described as a causal speedup or regression.

An additional trace reused a deterministic session ID and therefore inherited
prior ACK history. Both receipts were continued searches. Its labelled-first
case is rejected, preserved in `trace-10000`, and excluded from first-hook
results. The runner now generates a fresh receipt nonce, checks absent session
state before startup, and records current receipt classification and history.
ThreadState's last offered search is retained separately because it can be old
when current stdout is empty.

## Where time remains

Counters wrap existing callbacks and return the same values/exceptions. They
write counts and durations only, with a completeness flag. Instrumentation is
isolated and its actual original body is byte-identical to the fixed runtime.

| Callback, first instrumented hook | Calls | Total time |
| --- | ---: | ---: |
| Work view, prepared domain | 9,969 | 0.79 ms |
| Root ordinal, prepared domain | 19,946 | 3.49 ms |
| Original owner hydration | 9,969 | 2,504.70 ms |
| Work surface postings | 2 | 2,011.83 ms |
| Document frequencies | 9,965 | 1,596.49 ms |
| Work admission | 9,969 | 3,470.30 ms |

Admission includes nested frequency time; these rows must not be summed.
Discovery ultimately carries 9,977 outcomes although the semantic nomination
selects only eight. The warm synthetic Work texts share the query's words, so
all saved owners pass intrinsic alignment and get hydrated. Prepared catalogue
success therefore cannot be advertised as removing full owner reconstruction.

The initial numerical trace separately reports about 2.9 s cache loading,
2.4 s transport/scoring versus 42 ms numerical scoring itself, and 1.4 s query
processing with a cold encoder. Original source encoding during the hook is
zero. Matrix/batched transport remains a separate measured optimization target.

## Isolated batched-index candidate

Runtime `fa29b60acfc0784705fdb3996fba266f7ba2639dc0f865229a8c9d39d0582fd3`
prepares ordered Work postings during warm in two bounded atomic sidecar files.
Readiness is tied to the checked candidate-domain digest and actual code bytes.
A hook reads and verifies that index once; missing/invalid data takes the
original source-postings path, without rebuilding. Accepted owners still need
their complete original authority and Work/native agreement.

Demanded Work document frequencies are prefetched in a single batched read
before admission, with the same original counters and complete per-admission
frequency checks. Numerical ranking, selector and prompt are unchanged. Warm
also reuses prepared documents/Work views rather than enumerating those source
directories again; bounded original focus-prefix reads remain.

Against the fixed read-only 10k source, seven query shapes retain the exact
complete persisted posting order, including duplicate surfaces, empty/missing
terms, multilingual text and an arbitrary tool invocation. All 140 frequency
terms equal independent original point reads. Corrupt payloads and a foreign
domain digest are rejected; unchanged warm does not rebuild; source unchanged.
The prepared posting file is 2,878,414 bytes. Ordinary Lean proofs connect the
spelling function to the production owner function; this is not a proof of
all external cache IO behavior. No `native_decide` was added.

| Same-source diagnostic pair, query cache warm | First | Continued |
| --- | ---: | ---: |
| Instrumented reference | 20,020 ms | 18,302 ms |
| Instrumented batched candidate | 16,873 ms | 15,297 ms |

Both first and continued body hashes equal their corresponding reference
hashes, and current receipt strata/ACK history are valid. First candidate
postings time is 56.64 ms, frequency IO 1,057.86 ms, admission 1,485.66 ms and
prefetch 1,301.67 ms; nested counts overlap. All 9,969 owners still hydrate
(2,227.48 ms), so this does **not** remove broad admission. This is one
diagnostic pair, not p99 qualification, a statistical speedup claim, token/quality evidence
or adoption. ContractAudit passes. Actual CLI warm of the new runtime returns
identical 19,969-key coverage, zero missing/invalid and zero new encoding;
9,247 ms versus the preceding reference preparation's 10,403 ms is likewise
only diagnostic. Latest batched 50k hooks remain unqualified.

The callback counters were added separately first and their body equivalence
was checked before this optimization. An initial posting microbenchmark let
the compiler move pure calculations outside adjacent clock reads; its zero
timings are rejected and retained as `invalid-timers`. No-inline IO boundaries
now delimit the measured pure work. The original-order/frequency assertions
in that run were valid, but its timings are not evidence.

This candidate does not solve broad admission, multi-DB preparation,
incremental warm, historical-page growth or packed numerical transport. Those
remain necessary before practical qualification and live MCP use.

## Shared original-code receipt correction

The latest isolated runtime is
`9b64b26c42d426a30eb99265f464e561e5f0a4acc92be0a278ec8834eb9dcdf2`.
Native lifecycle testing first found that original CODE rows were present but
the delivery telemetry did not recognize the shared file format. The first
parser then recognized the final file while missing earlier consecutive files:
splitting on the next SOURCE header consumed the previous terminator's newline.
The corrected parser accepts a complete END SOURCE line at that split boundary
and rejects forged suffixes and incomplete frames.

An initially suspected canonical-representative mismatch was not the root
cause. A provisional extra registry/receipt path was removed. The final change
uses the existing immutable document/row domain, full source fingerprint and
line identity, raw scalar coordinates, code and declared DB/owner/Work/
occurrence. A typed witness retains membership in the original saved rows.
It recognizes the renderer's own format; it does not filter captured tools by
command name. No Work, Union, Match or authority rule changed.

Ordinary Lean regression checks cover matching code, shared occurrences,
multiple consecutive files, changed code/fingerprint/origin, wrong raw
coordinates, non-native data, location-only references, forged terminators and
incomplete frames. The actual native lifecycle then passes four shell calls,
Pre/Post/Stop, a new-chat stdout packet and all support, consumption,
coquotation and omitted-then-read delivery labels. Completion remains equal to
the baseline (one, with blocksCurrent false); damaged optional data retains
the baseline packet. ContractAudit passes. The guard exits zero with no owned
survivor, peak aggregate RSS 2,135,328 KiB. Failed earlier lifecycles are kept;
their actually delivered original bytes are not rewritten as missing data.

The 10k timing table belongs to the preceding batched runtime, not a newly
measured p99 for this telemetry correction. No latest-runtime 50k speed or token
adoption claim follows from the lifecycle check.

## Pre/Post cumulative cost

The real seed captured earlier with runtime `efb9a11d...` has 147 paired
started/completed caller notifications. A streaming Lean auditor groups unique
thread/turn/run identities, rejects duplicate notifications, reports unmatched
starts and terminals, and retains every terminal status and duration. It does
not run a hook, query, answering model or new seed. All pairs match here and
all handlers completed.

| Caller-reported handler | Count | Median | Maximum | Sum |
| --- | ---: | ---: | ---: | ---: |
| PreToolUse | 72 | 2,615 ms | 3,877 ms | 178,743 ms |
| PostToolUse | 72 | 1,626 ms | 2,762 ms | 114,058 ms |

The combined handler cost is **292,801 ms (4 min 52.8 s)**. Durations can
overlap, so this is not measured elapsed turn overhead. These measurements
belong to an initially empty, growing DB and the older runtime, not to the
latest 9b64b26c... candidate at 10k/50k. They establish that cumulative tool-hook
cost deserves its own measurement, even when individual hooks are in deadline.

In `PluginHooks.deliverForWork`, automatic projection with a configured matcher
and absent evidence enables semantic search. PreToolUse invokes that path;
PostToolUse usually passes its nonempty result as evidence, so it avoids that
semantic scheduling branch but still invokes Work search. Empty Post results
can take the semantic path. The recent four-tool lifecycle fixture instead
uses projection `none` during Pre/Post; its small durations cannot establish
search performance. Latest-runtime, warmed large-DB Pre/Post latency and
per-turn accumulation remain unqualified.

The next predefined scale cohort uses 100 attempts per stratum, reports sample
p99, maximum, deadline margin and every delivery failure. Full matrix scoring
retains O(N*d); nearly constant time on doubling is not required. Neither a
rough linear extrapolation nor a 29-second incomplete notice qualifies scale.

## Remaining gates

The actual 50k source has been created. Full warm completed in 1,411,113 ms,
adding 80,000 keys after 19,969 source-vector hints were reused. All 99,969
unique discovery/focus keys are valid, missing/invalid are zero, and source
head/pages/writer hashes are unchanged. Peak aggregate RSS was 2,171,248 KiB,
including small helper builds observed by the same guard; it exited zero with
no surviving owned process. Full-hook qualification must finish before any
50k latency claim.

The first actual warmed 50k attempt took 29,372 ms; its following same-chat
attempt took 28,994 ms. Both delivered only the 356-byte SEARCH INCOMPLETE
notice, with no original body. Stdout was fully flushed but `search.json` and
a successful delivery ACK were absent; `replyComplete=true` means complete
notice bytes, not a successful memory search. Both attempts remain failures.
The second has zero acknowledged delivery history because the first failed;
it does not qualify the successful-history stratum. The guard exited zero,
peak aggregate RSS 1,683,120 KiB, no survivors, and source hashes unchanged.

Read-only private preparation added zero vectors and reused the shared lexical
index, but still took 179,777 ms outside hook timing. Its catalogue preparation
was 32,955 ms. A sample locates repeated preparation time in
`Warm.planWindows → Store.searchDocuments`; idempotent preparation also needs
to reuse the prepared domain. Within a failed hook, a partial numerical record
had processed only 10,272 of 50,000 windows after 5,594 ms. It is not a completed
full-ranking timing. The final failure reports `daemon receive deadline
expired`. This reinforces packed numerical transport and complete-hook work,
rather than claiming a fast catalogue solves scale.

Keep cold preparation separate from warmed hooks and preserve every
timeout/incomplete attempt. Follow the fixed p99 protocol in
[practical readiness](practical-readiness.md).

MCP private capture, trusted server policy and credential exclusion still must
precede a real-server day/week trial. Practical speed and ordinary Lean proofs
do not replace the matched inclusive-token, quality and deadline adoption
conditions in AGENTS.md. No answering model or new seed was called in this
investigation; no new token-reduction result or adoption is claimed.
