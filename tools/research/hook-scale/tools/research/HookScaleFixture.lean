import Eggshell.Install
import Eggshell.CandidateDomain

open Lean Eggshell Plugin Persistence Store

namespace HookScaleFixture

/-- Same original content as RetrievalScale; only the storage transaction size
changes. Every measured arm will use the very same saved publication. -/
def work (index : Nat) : String :=
  s!"Inspect kernel realtime clock source {index}: monotonic scheduling and elapsed timer observations"

def body (index requested : Nat) : String :=
  if index == 0 && requested ≥ 32 then
    let text := String.join ((List.range 256).map fun chunk =>
      s!"ORIGINAL_CLOCK_BODY_0 chunk {chunk}: observed kernel timer and monotonic clock scheduling.\n")
    String.ofList (text.toList.take (32 * 384 - (work 0).length - 1))
  else s!"ORIGINAL_CLOCK_BODY_{index}: observed kernel timer and monotonic clock scheduling source {index}."

def owner (index requested : Nat) : OutcomeEdge :=
  OutcomeEdge.make (.text (work index)) (.text (body index requested)) [] (by simp) (by simp)

def prepare (directory : System.FilePath) (requested : Nat) : IO Json := do
  unless requested > 0 && requested ≤ 50000 do throw (IO.userError "window count must be in 1..50000")
  unless !(← directory.pathExists) do throw (IO.userError "keep existing scale fixture")
  FileSystem.privateDirectory directory
  let database := directory / "source.egg"
  let count := if requested ≥ 32 then requested-31 else requested
  let initial ← DB.PageMap.create database (Persistence.valueToJson (.text s!"practical scale {requested}")).compress
  let started ← IO.monoMsNow
  let mut snapshot := initial
  let mut saved := 0
  while saved < count do
    let stop := min count (saved+4096)
    let _ ← DB.PageMap.withWriter snapshot fun writer => do
      let intern : Intern := ⟨writer,← IO.mkRef {}⟩
      let mut ids := []
      for index in [saved:stop] do
        ids := (← intern.root (owner index requested).relation) :: ids
        if (index+1)%1024 == 0 then IO.eprintln s!"prepared {index+1}/{count} owners; transaction {saved}..{stop}"
      writeChange writer ⟨ids.reverse,[],false⟩
    snapshot ← DB.PageMap.pin database
    saved := stop
    IO.eprintln s!"committed {saved}/{count} owners; bytes={snapshot.head.bytes}"
    unless snapshot.head.bytes ≤ 2*1024*1024*1024 do throw (IO.userError "scale source exceeded 2 GiB storage budget")
  let documents ← searchDocuments snapshot
  let windows := documents.flatMap (·.windows)
  unless documents.length == count && windows.length == requested &&
      (Std.HashSet.ofList windows).size == requested do throw (IO.userError "scale population differs")
  let result := Json.mkObj [
    ("database",toJson database.toString),("source",toJson snapshot.head),
    ("owners",toJson count),("windows",toJson windows.length),("uniqueWindows",toJson requested),
    ("saveMs",toJson ((← IO.monoMsNow)-started)),("transactionOwners",toJson (4096 : Nat)),
    ("maxSourceBytes",toJson (2*1024*1024*1024 : Nat)),
    ("contentReference",toJson (Sha256.hex (include_str "../RetrievalScale.lean").toUTF8)),
    ("producer",toJson (Sha256.hex (include_str "HookScaleFixture.lean").toUTF8)),
    ("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (directory / "fixture.json") result.pretty
  return result

end HookScaleFixture

def main (args : List String) : IO UInt32 := do
  let result ← match args with
  | ["prepare",directory,count] => do
    let some count := count.toNat? | throw (IO.userError "invalid window count")
    HookScaleFixture.prepare (.mk directory) count
  | ["warm",database] => do
    let command := [(← IO.appPath).withFileName "eggshell" |>.toString,"search-provider"]
    toJson <$> Warm.run (← DB.PageMap.pin (.mk database)) command true
  | _ => throw (IO.userError "HookScaleFixture prepare NEW-DIR WINDOWS | warm DB")
  IO.println result.compress
  return 0
