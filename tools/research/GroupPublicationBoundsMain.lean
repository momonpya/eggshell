import Eggshell.NativePublication

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def reject (action : IO α) : IO Unit := do
  let rejected ← try let _ ← action; pure false catch _ => pure true
  check rejected "invalid publication group returned an ACK"

private def native (path : System.FilePath) : PendingTurn := {
  sessionId := "group-limits",turnId := "turn",cwd := path.parent.get!.toString
  prompt := "retain original evidence",profile := "work",semanticMatcher := none
  read := [path.toString],write := some path.toString,handoffChars := 120000,projection := .none
  tools := [⟨"mcp__records__read","call","{}","{\"id\":\"RECORD_42\"}",none⟩] }

private def seed (source : DB.PageMap.Snapshot) (pending : PendingTurn) : IO Unit := do
  let known : Journal.Knowledge := ⟨source.head,none,[],false,none,none⟩
  let clock := Sha256.hex "bounds clock".toUTF8
  for tool in pending.tools do
    let occurrence : Occurrence := ⟨pending.sessionId,pending.turnId,tool.useId⟩
    let _ ← Journal.append source ⟨⟨clock,10⟩,.start occurrence (canonicalToolWork tool)
      (Sha256.hex pending.prompt.toUTF8) known,some 1000⟩
    let _ ← Journal.append source ⟨⟨clock,20⟩,.finish occurrence tool.name
      (canonicalJson tool.input) (canonicalJson tool.response) none,some 1010⟩

def main (args : List String) : IO UInt32 := do
  try
    let [output] := args | throw (IO.userError "GroupPublicationBoundsMain NEW-DIRECTORY")
    let root := System.FilePath.mk output
    check (root.isAbsolute && !(← root.pathExists)) "new absolute bounds fixture required"
    IO.FS.createDir root
    let path := root / "source.egg"
    let _ ← Persistence.create path
    let initial ← DB.PageMap.pin path
    let pending := native path
    seed initial pending
    let prepared ← NativePublication.prepare pending path true
    reject (NativePublication.runPrepared path #[])
    reject (NativePublication.runPrepared path (Array.replicate (NativePublication.maxBatchRequests+1) prepared))
    reject (NativePublication.runPrepared (root / "foreign.egg") #[prepared])
    check (!(← (root / "foreign.egg").pathExists)) "foreign group target was created before rejection"
    let large := {pending with tools := [⟨"mcp__records__read","large","{}",
      String.ofList (List.replicate (NativePublication.maxBatchBytes+1) 'x'),none⟩]}
    let large ← NativePublication.prepare large path true
    reject (NativePublication.runPrepared path #[large])
    check ((← DB.PageMap.pin path).head == initial.head) "bounds rejection changed the source publication"
    -- Keep the graph authority identical and replace only storage identity.
    -- Failure occurs inside the actual writer after roots have been staged.
    let replaced : DB.PageMap.Head := {initial.head with identity := Sha256.hex "replacement DB".toUTF8}
    FileSystem.immutableBytes (DB.PageMap.dataPath path replaced) DB.PageMap.magic
    FileSystem.atomicExistingBytes (path / "head") (toJson replaced).compress.toUTF8
    reject (NativePublication.runPrepared path #[prepared])
    let rejected ← DB.PageMap.pin path
    check (rejected.head == replaced && (← Provenance.records rejected).isEmpty &&
      (← Persistence.Store.rootIds rejected).isEmpty) "stale prepared input partially published into a replacement DB"
    seed rejected pending
    let fresh ← NativePublication.prepare pending path true
    let published ← NativePublication.runPrepared path #[fresh]
    check (published.size == 1 && published.all (fun result => result.source.complete &&
      result.source.head.identity == replaced.identity && result.source.head.revision == replaced.revision+1))
      "new native input could not recover after the cancelled writer"
    IO.println (Json.mkObj [("emptyAndCountBounds",toJson true),("byteBound",toJson true),
      ("foreignTargetRejected",toJson true),("replacementRejectedBeforeAck",toJson true),
      ("noPartialPublication",toJson true),("writerRecovered",toJson true),
      ("answeringModelCalls",toJson (0 : Nat))]).compress
    return 0
  catch error => IO.eprintln error.toString; return 1
