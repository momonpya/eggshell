import tools.research.ReplayReadinessChecks
import tools.research.MemoryCapacity
import tools.research.NativeTrialAudit

open Lean Eggshell
namespace Eggshell.Research.NumericalBlockStress

def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path value.compress

def projection (reply : Json) : Json := Json.mkObj [
  ("scores",reply.getObjValD "scores"),("coverage",reply.getObjValD "coverage")]

def score (client : Numerical.Client) (body : String) (count : Nat) : IO Json := do
  let reply ← IO.ofExcept (Json.parse (← client.request 66 body))
  if let .ok error := reply.getObjValAs? String "error" then throw (IO.userError error)
  let scores ← IO.ofExcept (reply.getObjValAs? (Array Json) "scores")
  let coverage ← IO.ofExcept (reply.getObjValAs? (Array (Option String)) "coverage")
  check (scores.size == count && coverage.size == count && coverage.all Option.isSome)
    "actual indexed block reply is incomplete"
  for metadata in coverage do
    let some metadata := metadata | throw (IO.userError "missing original projection coverage")
    let value : SearchProvider.EncodingCoverage ← IO.ofExcept (Json.parse metadata >>= fromJson?)
    check value.valid "original projection is not fully covered"
  return reply

def run (source root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous block evidence"
  IO.FS.createDirAll root
  let snapshot ← DB.PageMap.pin source
  let owner := DB.Sidecar.Owner.ofSnapshot snapshot
  let (windows,_) ← Warm.planWindows snapshot
  let windows := windows.toArray
  check (windows.size == 1933) "frozen discovery window domain changed"
  let query ← IO.ofExcept (SearchProvider.packVector (toJson
    ((#[1] : Array Nat) ++ Array.replicate 383 0)))
  let mut blocks : Array (String × Nat) := #[]
  for start in [:windows.size:256] do
    let rows := (windows.extract start (min (start+256) windows.size)).map fun row =>
      BlockScore.Input.indexed owner row.key
    let body := (Json.mkObj [("queries",toJson #[query]),("blockRows",toJson rows)]).compress
    blocks := blocks.push (body,rows.size)
  check (blocks.size == 8) "frozen eight-block chain changed"
  save (root/"input.json") (Json.mkObj [("snapshot",toJson snapshot.head),
    ("windowKeysDigest",toJson (Sha256.hex (toJson (windows.map (·.key))).compress.toUTF8)),
    ("windows",toJson windows.size),("blockRows",toJson (blocks.map Prod.snd)),
    ("requestBytes",toJson (blocks.map fun row => row.1.utf8ByteSize)),
    ("query",toJson "384-dimensional unit basis; exact same query for every client"),
    ("clients",toJson (4 : Nat)),("passes",toJson (2 : Nat)),
    ("chainBudgetMs",toJson (14500 : Nat)),("newModelCalls",toJson (0 : Nat)),
    ("sameRawIndexedRows",toJson true),("adopted",toJson false)])
  let some config ← Numerical.defaultConfig? | throw (IO.userError "existing MiniLM support required")
  let keeper ← Numerical.keep config
  try
    let serial ← Numerical.openClient config
    let expected ← try blocks.mapM fun (body,count) =>
        SemanticMatcher.withTaskResponseDeadline (projection <$> score serial body count) 14500
      finally serial.close
    let mut passes : Array Json := #[]
    for pass in [:2] do
      let clients ← (Array.range 4).mapM fun _ => Numerical.openClient config
      let release ← IO.Promise.new
      let tasks ← clients.mapIdxM fun index client => IO.asTask (do
        let stages ← IO.mkRef ({} : KeyedSearchClient.StageTrace)
        let mark := fun label => do
          let now ← IO.monoMsNow
          stages.modify (fun trace => trace.advance label now)
        let client := {client with onStage := mark}
        discard <| IO.wait release.result!
        let began ← IO.monoMsNow
        let completed ← IO.mkRef (0 : Nat)
        let replies ← IO.mkRef (#[] : Array Json)
        let error ← try
            SemanticMatcher.withTaskResponseDeadline (do
              for batch in [:blocks.size] do
                mark s!"batch-{batch}:start"
                let reply ← score client blocks[batch]!.1 blocks[batch]!.2
                check (projection reply == expected[batch]!) "parallel scores or coverage changed"
                replies.modify (·.push (Json.mkObj [("batch",toJson batch),
                  ("trace",reply.getObjValD "numericalTrace")]))
                completed.modify (·+1)
                mark s!"batch-{batch}:end") 14500
            pure none
          catch error => pure (some error.toString)
        let trace ← stages.get
        let result := Json.mkObj [("client",toJson index),("pass",toJson pass),
          ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("completedBlocks",toJson (← completed.get)),
          ("error",toJson error),("lastStages",toJson trace.events.reverse),
          ("omittedStages",toJson trace.omitted),("replies",toJson (← replies.get))]
        save (root/s!"pass-{pass}-client-{index}.json") result
        return result) .dedicated
      let results ← try
          let began ← IO.monoMsNow
          release.resolve ()
          let rows ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
          pure (Json.mkObj [("wallMs",toJson ((← IO.monoMsNow)-began)),("rows",toJson rows)])
        finally
          release.resolve ()
          for task in tasks do IO.cancel task
          for task in tasks do discard <| IO.wait task
          for client in clients do client.close
      save (root/s!"pass-{pass}.json") results
      passes := passes.push results
      let rows ← IO.ofExcept (results.getObjValAs? (Array Json) "rows")
      check (rows.all fun row => row.getObjValD "error" == Json.null &&
        row.getObjValD "completedBlocks" == toJson (8 : Nat)) "bounded repeated block RPC failed"
    let endpoint ← Numerical.resolve config
    let stats ← IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats"))
    save (root/"report.json") (Json.mkObj [("allPassed",toJson true),("passes",toJson passes),
      ("serialBlocks",toJson (8 : Nat)),("parallelBlocks",toJson (64 : Nat)),
      ("exactScoresAndOriginalCoverage",toJson true),("endStats",stats),
      ("fullHookOrEightyUsers",toJson false),("adopted",toJson false)])
  finally Numerical.release keeper 10000

end Eggshell.Research.NumericalBlockStress

def main (args : List String) : IO UInt32 := do
  match args with
  | ["numerical-block-stress",source,output] =>
    Eggshell.Research.NumericalBlockStress.run (.mk source) (.mk output)
    return 0
  | other => Eggshell.Research.ReplayReadinessChecks.main other
