import Eggshell.Numerical
import Eggshell.SearchProvider
import Init.System.Promise
open Lean Eggshell
namespace Eggshell.Research.NumericalParallelControls
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def payload (index : Nat) : Json := Json.mkObj [("texts",toJson (#[
  s!"Independent request {index}: a cached observation retains its source identity.",
  s!"要求{index}: " ++ String.join (List.replicate 8 "非同期の要求ごとに独立した入出力を持ち原文の末尾まで確認する。"),
  s!"요청{index}: " ++ String.join (List.replicate 6 "모든 입력과 원문을 확인하고 독립적으로 처리합니다. "),
  "case_" ++ toString index ++ "() { if (ready && owner) return source[offset]; else return pending; }" ] : Array String))]
def vectors (reply : Json) : Json := Json.mkObj [("vectors",reply.getObjValD "vectors"),("coverage",reply.getObjValD "coverage")]
def encode (client : Numerical.Client) (input : Json) : IO Json := do
  let reply ← IO.ofExcept (Json.parse (← client.request 69 input.compress))
  if let .ok error := reply.getObjValAs? String "error" then throw (IO.userError error)
  let coverage ← IO.ofExcept (reply.getObjValAs? (Array SearchProvider.EncodingCoverage) "coverage")
  let groups ← IO.ofExcept ((reply.getObjValD "vectors").getArr?)
  check (coverage.size == 4 && groups.size == 4 && coverage.all (·.valid)) "encoder coverage changed"
  for group in groups do
    let rows ← IO.ofExcept group.getArr?
    check (!rows.isEmpty) "empty encoder vector group"
    for row in rows do check ((← IO.ofExcept row.getArr?).size == 384) "encoder dimension changed"
  return reply
def event? (reply : Json) (name : String) : Option Nat := do
  let events ← ((reply.getObjValD "numericalTrace").getObjValD "events").getArr?.toOption
  let row ← events.find? fun row => ((row.getArr?.toOption.getD #[])[0]?).any (· == toJson name)
  let parts ← row.getArr?.toOption
  let value ← parts[1]?
  value.getNat?.toOption
def model? (reply : Json) : Option String := do
  let events ← ((reply.getObjValD "numericalTrace").getObjValD "events").getArr?.toOption
  let names := events.filterMap fun row => do
    let parts ← row.getArr?.toOption
    let name ← parts[0]?
    name.getStr?.toOption
  names.find? (·.startsWith "encode-model:")
def wave (config : Numerical.Config) (expected : Array Json) (root : System.FilePath) (ordinal : Nat) : IO Json := do
  let entered ← Std.Mutex.new (0 : Nat)
  let release ← IO.Promise.new
  let tasks ← (Array.range expected.size).mapM fun index => IO.asTask (do
    let client ← Numerical.openClient config
    try
      entered.atomically (modify (·+1))
      discard <| IO.wait release.result!
      let began ← IO.monoMsNow
      let reply ← encode client (payload index)
      let elapsed := (← IO.monoMsNow)-began
      check (vectors reply == expected[index]!) "parallel model changed exact vectors or coverage"
      let row := Json.mkObj [("request",toJson index),("elapsedMs",toJson elapsed),
        ("exactVectorsAndCoverage",toJson true),("model",toJson (model? reply)),
        ("kernelStart",toJson (event? reply "encode-kernel:start")),
        ("kernelEnd",toJson (event? reply "encode-kernel:end")),
        ("trace",reply.getObjValD "numericalTrace")]
      IO.FS.writeFile (root/s!"wave-{ordinal}-request-{index}.json") row.compress
      return row
    finally client.close) .dedicated
  try
    let deadline := (← IO.monoMsNow)+5000
    while (← entered.atomically get) < expected.size do
      check ((← IO.monoMsNow) < deadline) "parallel encoder launch barrier expired"
      IO.sleep 1
    let began ← IO.monoMsNow
    release.resolve ()
    let rows ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
    let elapsed := (← IO.monoMsNow)-began
    let endpoint ← Numerical.resolve config
    let stats ← IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats"))
    check (stats.getObjValD "waitingEncodes" == toJson (0 : Nat) &&
      stats.getObjValD "idleModels" == toJson (1 : Nat)) "burst retained surplus warm models"
    let mut overlapped := false
    for a in rows do
      for b in rows do
        let am := a.getObjValD "model"
        let bm := b.getObjValD "model"
        let as_ := (a.getObjValAs? Nat "kernelStart").toOption
        let ae := (a.getObjValAs? Nat "kernelEnd").toOption
        let bs := (b.getObjValAs? Nat "kernelStart").toOption
        let be := (b.getObjValAs? Nat "kernelEnd").toOption
        if let (some as_,some ae,some bs,some be) := (as_,ae,bs,be) then
          if am != Json.null && bm != Json.null && am != bm && as_ < be && bs < ae then overlapped := true
    let result := Json.mkObj [("requests",toJson rows.size),("wallMs",toJson elapsed),
      ("rows",toJson rows),("differentModelIntervalsOverlap",toJson overlapped),("endStats",stats)]
    IO.FS.writeFile (root/s!"wave-{ordinal}.json") result.compress
    return result
  finally
    release.resolve ()
    for task in tasks do IO.cancel task
    for task in tasks do discard <| IO.wait task

def run (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous numerical evidence"
  IO.FS.createDirAll root
  let some config ← Numerical.defaultConfig? | throw (IO.userError "existing MiniLM runtime required")
  let keeper ← Numerical.keep config
  try
    let client ← Numerical.openClient config
    let expected ← try (Array.range 16).mapM fun index => do
        return vectors (← encode client (payload index))
      finally client.close
    let cold ← wave config expected root 0
    let warm ← wave config expected root 1
    let endpoint ← Numerical.resolve config
    let stats ← IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats"))
    let capacity := (stats.getObjValAs? Nat "modelCapacity").toOption.getD 0
    let starts := (stats.getObjValAs? Nat "modelStarts").toOption.getD 0
    let pids ← IO.ofExcept (stats.getObjValAs? (Array Nat) "modelPids")
    check (capacity == 2 && starts ≥ 3 && pids.size == 1 &&
      stats.getObjValD "waitingEncodes" == toJson (0 : Nat) &&
      stats.getObjValD "idleModels" == toJson (1 : Nat))
      "actual service did not expand for demand and return to one warm standby"
    check (warm.getObjValD "differentModelIntervalsOverlap" == toJson true)
      "warm encoder intervals remained serialized"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("allPassed",toJson true),("stats",stats),
      ("coldWave",cold),("warmWave",warm),("referenceRequests",toJson (16 : Nat)),
      ("all48RepliesExactVectorsAndCoverage",toJson true),("pythonNumericalSourceUnchanged",toJson true),
      ("oneWarmStandbyAfterEachBurst",toJson true),
      ("fullHookOrEightyUsers",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally Numerical.release keeper 10000
end Eggshell.Research.NumericalParallelControls
