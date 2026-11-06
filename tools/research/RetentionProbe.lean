module
public import tools.research.HeapObservation
@[expose] public section
namespace Eggshell.Research.RetentionProbe
open Lean

inductive Mode where
  | sham | collect
  deriving BEq,ToJson,FromJson

def Mode.collects : Mode → Bool | .sham => false | .collect => true
def mode? : String → Except String Mode
  | "sham" => .ok .sham
  | "collect" => .ok .collect
  | _ => .error "unknown diagnostic retention intervention"

@[extern "eggshell_research_reclaim"] opaque reclaimRaw (collect : Bool) : IO Bool

def rss : IO Nat := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString (← IO.Process.getPID),"-o","rss="]}
  unless result.exitCode == 0 do throw (IO.userError "cannot observe current process RSS")
  let some value := result.stdout.trimAscii.toString.toNat? | throw (IO.userError "invalid process RSS")
  return value

def snapshot : IO Json := do
  let observedAt ← IO.monoMsNow
  let bytes ← rss
  return Json.mkObj [("atMs",toJson observedAt),("rssKiB",toJson bytes),
    ("owner",← HeapObservation.owner),("arenas",toJson (← HeapObservation.arenasRaw))]

/-- Only the explicit diagnostic operation selects collection. It is not
called by retrieval, publication, ordinary stats or cache admission. -/
def measure (mode : Mode) : IO Json := do
  let thread ← HeapObservation.threadId
  let before ← snapshot
  let began ← IO.monoMsNow
  let osMain ← reclaimRaw mode.collects
  let collected ← IO.monoMsNow
  let immediate ← snapshot
  IO.sleep 100
  let settled ← snapshot
  return Json.mkObj [("mode",toJson mode),("collectionRequested",toJson mode.collects),
    ("thread",toJson thread),("osMainThread",toJson osMain),
    ("interventionMs",toJson (collected-began)),("before",before),("immediate",immediate),("settled",settled)]

structure Request where
  mode : Mode
  reply : IO.Promise (Except IO.Error Json)
abbrev Probe := Std.CloseableChannel Request
def Probe.new : IO Probe := Std.CloseableChannel.new (some 1)
def Probe.request (probe : Probe) (mode : Mode) : IO Json := do
  let reply ← IO.Promise.new
  unless ← probe.trySend ⟨mode,reply⟩ do throw (IO.userError "retention diagnostic mailbox unavailable")
  TaskDeadline.wait reply.result! ((← IO.monoMsNow)+2000)
def Probe.respond (probe : Probe) : IO Unit := do
  if let some request ← probe.tryRecv then
    let result ← try pure (.ok (← measure request.mode)) catch error => pure (.error error)
    request.reply.resolve result
def Probe.stop (probe : Probe) : IO Unit := do
  try probe.close catch _ => pure ()
  repeat
    let some request ← probe.tryRecv | break
    request.reply.resolve (.error (IO.userError "retention diagnostic stopped"))
end Eggshell.Research.RetentionProbe
