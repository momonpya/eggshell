# An immutable operation deadline

Status: isolated candidate;unadopted. The product core and README performance
claims remain unchanged. Answering-model calls0;paid matched comparisons0/18.

The operation client processes a framed connection sequentially. Its progress
callback runs between frame reads on that same owner. Nevertheless,the old
API passed a `Mutex Nat` through connect/send/read and locked it on each
five-millisecond poll. No second task updated this particular deadline.

The replacement passes an immutable absolute cutoff. A pure checked progress
transition validates the original request identity and arrival time,derives
the next cutoff using the existing finishReady policy,and returns the value
to the same connection owner. No mutable deadline reference,mutex or CAS is
carried by this transport API. Worker and client use one shared pure policy.
The separate legacy pipe reader/supervisor actually has concurrent deadline
access;its synchronization remains outside this change.

Lean checks that accepted progress cannot exceed the original upstream
deadline and that timely same-identity progress implements the existing
policy. The existing unready/late/foreign/upstream laws remain unchanged.
The existing derived identity comparison now also has generated ReflBEq and
LawfulBEq proofs. Exact-length receives require positive bounded fragments,
use terminating recursion,and cancel/join their native read on every exit.

Native checks cover valid/unready/late/foreign/unexpected progress,fragmented
70,000-byte frames,cancellation,deadline,EOF and a live unaffected connection.
The first native check caught a cancellation-join error before any candidate
hooks ran: `Promise.result!` blocked forever when cancellation dropped the
promise. A live PID and native stack confirmed that wait;the owned process
was terminated and its guard drained. A second check showed that switching to
`result?` was insufficient while retaining the promise owner in the finalizer.
Use the existing `Daemon.withOwnedReceive` implementation:convert to an
AsyncTask,release the promise owner before waiting,cancel the native receive,
then join the task that handles a legitimate dropped state. Keep both failed
checks alongside the corrected check;do not label those failures successful.
The ordinary hook comparison uses the sealed a80cad client and the same
16-source frozen development fixture as readonly-pages. Actual body equality,
required originals,ACKs and semantic handoffs are separate checks.

The final native checks pass. The ordinary16-client/two-wave control delivers
all32 required originals with ACKs and32 semantic handoffs. All32 complete
output bytes match readonly-pages;maximum latency is8,902ms and related peak
RSS2,717,312KiB. This single control is not a measured latency improvement.
The final source audit binds the executable SHA and251 native modules:only
the declared four source files differ. PublicationWire's implementation-ID
container changes only by embedding those exact changed source bytes.
[Native-source comparison](native-sources-final.json).
Earlier audit attempts are retained as checker failures:an insufficient
compiler heap setting,an incomplete native-object mapping,and failure to
distinguish embedded identity inputs from direct source changes. The final
audit checks both the module table and exact embedded before/after bytes.

[Patch](candidate.patch),[checks and controls](controls.json),
[actual outputs](evidence.json),[independent body verification](verification.json).
Do not infer80-client memory safety,80-person sustained traffic,real98%
evidence recall,answer quality or token reduction from this synchronization
change. No80-client full-hook repeat is authorized by this trial plan;the
separate allocator/live-state diagnosis remains unresolved.
