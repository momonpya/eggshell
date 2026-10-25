import Eggshell.Sha256
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean Eggshell

private def replaceOnce (source before after : String) : IO String := do
  unless (source.splitOn before).length == 2 do throw (IO.userError "expected one exact source location")
  return source.replace before after

def main : IO Unit := do
  let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/snapshot-refresh-20261025"
  let parent := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/canonical-delta-20261025"
  unless !(← root.pathExists) do throw (IO.userError "keep previous candidate")
  IO.FS.createDir root
  let clone ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(parent / "checkout").toString,(root / "checkout").toString]}
  unless clone.exitCode == 0 do throw (IO.userError "candidate checkout clone failed")
  let helper := "/-- Replay may publish derived provenance into the source DB. Re-pin only\n" ++
    "after verifying the exact parent chain contains no source changes. -/\n" ++
    "def refreshSource (snapshot : DB.PageMap.Snapshot) (storage : DB.Sidecar.Storage)\n" ++
    "    (deadline : Nat) : IO (DB.PageMap.Snapshot × Synapses.Journal.Result) := do\n" ++
    "  let result ← Synapses.Journal.refresh snapshot storage deadline\n" ++
    "  let current ← DB.PageMap.pin snapshot.directory\n" ++
    "  unless ← Synapses.Index.sameSources current snapshot.head 64 do\n" ++
    "    throw (IO.userError \"source facts changed during provenance preparation\")\n" ++
    "  return (current,result)\n\n"
  let mut changes := #[]
  for name in #["Warm","Worker"] do
    let relative := "Eggshell/" ++ name ++ ".lean"
    let original ← IO.FS.readFile (parent / "checkout" / relative)
    let updated ← if name == "Warm" then do
        let source ← replaceOnce original "/-- Preparation uses verified publication deltas;" (helper ++ "/-- Preparation uses verified publication deltas;")
        replaceOnce source
          "  let _ ← Synapses.Journal.refresh snapshot target.storage ((← IO.monoMsNow)+60000)"
          "  let (snapshot,_) ← refreshSource snapshot target.storage ((← IO.monoMsNow)+60000)"
      else do
        let source ← replaceOnce original
          "  let _ ← Synapses.Journal.refresh pinned target.storage ((← IO.monoMsNow)+60000)"
          "  let (pinned,_) ← Warm.refreshSource pinned target.storage ((← IO.monoMsNow)+60000)"
        replaceOnce source
          "          let indexed ← Synapses.Journal.refresh pinned target.storage ((← IO.monoMsNow)+60000)"
          "          let (pinned,indexed) ← Warm.refreshSource pinned target.storage ((← IO.monoMsNow)+60000)"
    let candidate := root / "checkout" / relative
    IO.FS.removeFile candidate
    IO.FS.writeFile candidate updated
    let retained := project / "tools/research/snapshot-refresh" / relative
    IO.FS.createDirAll retained.parent.get!
    IO.FS.writeFile retained updated
    changes := changes.push (Json.mkObj [("file",toJson relative),
      ("beforeSha256",toJson (Sha256.hex original.toUTF8)),("afterSha256",toJson (Sha256.hex updated.toUTF8))])
  let entry ← IO.FS.readFile (project / "Main.lean")
  let entry ← replaceOnce entry "public import Eggshell.SearchProvider\n"
    "public import Eggshell.SearchProvider\npublic import Eggshell.KeyedSearchProvider\n"
  let entry ← replaceOnce entry "      | \"search-provider\" :: options => Eggshell.SearchProvider.run options"
    "      | \"search-provider\" :: options => Eggshell.SearchProvider.run options\n      | \"keyed-search-provider\" :: options => Eggshell.KeyedSearchProvider.run options"
  IO.FS.removeFile (root / "checkout/Main.lean")
  IO.FS.writeFile (root / "checkout/Main.lean") entry
  IO.FS.writeFile (project / "tools/research/snapshot-refresh/Main.lean") entry
  let settings ← IO.ofExcept (Json.parse (← IO.FS.readFile "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025/build-plan.json"))
  let settings := settings.setObjVal! "core" (toJson (root / "checkout").toString)
    |>.setObjVal! "output" (toJson (root / "build").toString)
    |>.setObjVal! "force" (toJson #["Eggshell.Warm","Eggshell.Worker","Main"])
    |>.setObjVal! "mainModule" (toJson "Main")
  IO.FS.writeFile (root / "build-plan.json") (settings.pretty ++ "\n")
  IO.FS.writeFile (root / "changes.json") ((Json.mkObj [("productionAdoption",toJson false),
    ("changes",toJson changes),("answeringModelCalls",toJson (0 : Nat))]).pretty ++ "\n")
  IO.println "prepared isolated snapshot-refresh sources"
