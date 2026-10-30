import Eggshell.Handoff
import Eggshell.SynapseBuild
import Eggshell.Sha256
open Lean Eggshell Eggshell.Synapses

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def includes (body text : String) : Bool := !text.isEmpty && (body.splitOn text).length > 1

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh WorkGraph label diagnosis required")
  let target : System.FilePath := .mk destination
  check (!(← target.pathExists)) "preserve WorkGraph label diagnosis"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let body ← IO.FS.readFile (project / "docs/candidates/canonical-keys/hooks/baseline/rep-0/body.txt")
  let prompt ← IO.FS.readFile (study / "prompts/topic-1.txt")
  let source ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let reader ← Persistence.Store.NodeReader.new source
  let mut works : Std.HashMap String (Value × Bool × Bool) := {}
  for entry in ← Build.entries source do
    let value ← reader.work (← reader.locateOutcome entry.id)
    let display := Plugin.displayKey value
    if includes body ("WORK " ++ display) then
      let previous := works[Plugin.relationKey value]?
      works := works.insert (Plugin.relationKey value) (value,true,previous.any (·.2.2))
  for entry in ← Persistence.Store.allHeaders source do
    let value ← reader.read entry.2.header.parent
    let display := Plugin.displayKey value
    if includes body ("PARENT WORK " ++ display) then
      let previous := works[Plugin.relationKey value]?
      works := works.insert (Plugin.relationKey value) (value,previous.any (·.2.1),true)
  let mut rows := #[]
  let mut complete := 0
  let mut storedCharacters := 0
  for (key,value,native,parent) in works.toArray.qsort (fun a b => a.1 < b.1) do
    let text := Plugin.readable value
    let full := includes body text
    if full then complete := complete+1
    storedCharacters := storedCharacters+text.length
    rows := rows.push (Json.mkObj [("work",toJson key),("display",toJson (Plugin.displayKey value)),
      ("nativeOwnerWork",toJson native),("allParent",toJson parent),
      ("storedReadableChars",toJson text.length),("completeStoredReadableTextInBody",toJson full),
      ("storedTextSha256",toJson (Sha256.hex text.toUTF8)),("preview",toJson ((text.take 200).copy))])
  check ((← DB.PageMap.pin source.directory).head == source.head) "label diagnosis changed source"
  IO.FS.writeFile target (Json.mkObj [("bodySha256",toJson (Sha256.hex body.toUTF8)),
    ("referencedWorkCount",toJson works.size),("completeReadableWorkLabelsInBody",toJson complete),
    ("storedReadableCharacters",toJson storedCharacters),("rows",toJson rows),
    ("currentRequestFullyPresent",toJson (includes body prompt)),("sourceUnchanged",toJson true),
    ("labelsRequiredForAnswerNotEstablished",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Related stored Work labels: {complete}/{works.size} complete, current request preserved {includes body prompt}"
