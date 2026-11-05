import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def source := base/"frontend-quiescence-fixture-small1"
def engine := base/"metadata-ingress-candidate-build/StudyMain"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def call (args : Array String) (input : Option String := none) := IO.Process.output {cmd := engine.toString,args} input
def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "fresh selection diagnostic required")
  let root := System.FilePath.mk path
  check (root.isAbsolute && !(← root.pathExists)) "preserve earlier selection diagnostic"
  IO.FS.createDirAll root
  let heads ← (List.range 16).toArray.mapM fun i => IO.FS.readFile (source/s!"work.project/owners/{i}/source.egg/head")
  let frozen : Array (String × String × String) ← IO.ofExcept (fromJson? (← read (base/"worker-cpu-native-profile1-result/heads.json")))
  check (heads == frozen.map (·.2.1)) "source differs from the frozen original audit"
  let config ← IO.FS.readFile (base/"worker-cpu-native-profile1-result/eggshell.toml")
  IO.FS.writeFile (root/"eggshell.toml") config
  try
    let warm ← call #["egg","warm",(source/"work.project").toString]
    check (warm.exitCode == 0) "selection source is not prepared"
    let mut rows := #[]
    for index in [0,28] do
      let session := s!"selection-{index}"
      let input := Json.mkObj [("session_id",toJson session),("turn_id",toJson "turn"),
        ("cwd",toJson root.toString),("hook_event_name",toJson "UserPromptSubmit"),
        ("_eggshell_config",toJson (root/"eggshell.toml").toString),
        ("prompt",toJson s!"Return the recorded head and tail facts for support case-{index}.")]
      let started ← IO.monoMsNow
      let output ← call #["codex-hook"] (some input.compress)
      let elapsed := (← IO.monoMsNow)-started
      check (output.exitCode == 0) "selection diagnostic hook failed"
      IO.FS.writeFile (root/(session++".stdout")) output.stdout
      IO.FS.writeFile (root/(session++".stderr")) output.stderr
      let json ← IO.ofExcept (Json.parse output.stdout)
      let body ← IO.ofExcept ((json.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let baselineName := if index == 0 then "cpu-wave-a-0.stdout" else "cpu-wave-b-28.stdout"
      let baseline ← read (base/"worker-cpu-native-profile1-result"/baselineName)
      let expected ← IO.ofExcept ((baseline.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      check (body == expected) "range/input tracing changed the actual delivery body"
      rows := rows.push (Json.mkObj [("case",toJson index),("session",toJson session),("elapsedMs",toJson elapsed),
        ("head",toJson (body.contains s!"observed-head-case-{index}-7b319c")),
        ("tail",toJson (body.contains s!"observed-tail-case-{index}-d82a04")),("bodyBytes",toJson body.utf8ByteSize),
        ("sameActualBodyWithTracing",toJson true)])
    check (heads == (← (List.range 16).toArray.mapM fun i => IO.FS.readFile (source/s!"work.project/owners/{i}/source.egg/head")))
      "selection diagnostic changed original heads"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("rows",toJson rows),
      ("originalHeadsUnchanged",toJson true),("productChanged",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
  finally
    let frontend ← call #["codex-daemon","shutdown"]
    let publisher ← call #["publication-control","shutdown"]
    IO.FS.writeFile (root/"shutdown.json") (Json.mkObj [("frontendExit",toJson frontend.exitCode.toNat),
      ("publisherExit",toJson publisher.exitCode.toNat)]).pretty
