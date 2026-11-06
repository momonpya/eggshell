import Main
import Eggshell.ContractAudit
import tools.research.AbandonedHeap
open Lean Eggshell Eggshell.Plugin Eggshell.Research

namespace HeapOwnershipChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def waitExit (identity : Nat) : IO Unit := do
  let deadline := (← IO.monoMsNow)+5000
  repeat
    let alive ← try pure (some (← AbandonedHeap.threadAlive identity)) catch _ => pure none
    if alive == some false then return
    check ((← IO.monoMsNow) < deadline) "producer OS thread did not exit"
    IO.sleep 1
  throw (IO.userError "unreachable producer exit")

@[noinline] def produce (keep : IO.Ref (Array ByteArray)) : IO Nat := do
  let mut blocks := #[]
  for index in [:256] do
    blocks := blocks.push (ByteArray.mk (Array.replicate 65536 index.toUInt8))
  keep.set blocks
  return ← AbandonedHeap.threadId

@[noinline] def clear (keep : IO.Ref (Array ByteArray)) : IO Unit := do
  let blocks ← keep.get
  check (blocks.size == 256 && blocks.all (·.size == 65536)) "retained fixture payload changed"
  keep.set #[]

def controls (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh heap ownership control root required"
  IO.FS.createDirAll root
  AbandonedHeap.enable
  let before ← AbandonedHeap.snapshot true
  let keep ← IO.mkRef (#[] : Array ByteArray)
  let producer ← IO.asTask (produce keep) .dedicated
  let identity ← IO.ofExcept (← IO.wait producer)
  waitExit identity
  let held ← AbandonedHeap.snapshot true
  clear keep
  let releasedAreas ← AbandonedHeap.snapshot false
  let released ← AbandonedHeap.snapshot true
  let number := fun value key => (value.getObjValAs? Nat key).toOption.getD 0
  let valid := [before,held,releasedAreas,released].all (fun value => number value "complete" == 1)
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("before",before),("held",held),
    ("releasedAreas",releasedAreas),("releasedCensus",released),("producerThread",toJson identity),
    ("producerOsExitVerified",toJson true),("complete",toJson valid),
    ("onlyExternalAllocatorDiagnosticApi",toJson true),("miCollectCalled",toJson false)]).compress
  check valid "abandoned census was truncated"
  check (number held "allocatedBytes" ≥ number before "allocatedBytes"+16*1024*1024)
    "observer failed the retained sixteen MiB positive control"
  check (number released "allocatedBytes"+16*1024*1024 ≤ number held "allocatedBytes")
    "observer failed the released payload negative control"
end HeapOwnershipChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["abandoned-heap-check",root] => HeapOwnershipChecks.controls (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
      args := #["front-traffic-audit",source] }
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | _ =>
    if args == ["codex-publication-daemon"] &&
        (← IO.getEnv "EGGSHELL_RESEARCH_ABANDONED_HEAP") == some "1" then AbandonedHeap.enable
    sourceRouteEngine args
