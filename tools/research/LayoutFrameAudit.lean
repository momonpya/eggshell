import tools.research.LayoutFrameDependencies
import tools.research.FrozenCanonicalBasis
import tools.research.AvailableDelivery
import Eggshell.SynapseUsage
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def fixtures : IO Unit := do
  let file : File := ⟨"arbitrary-resource",String.ofList (List.replicate 64 'a'),100⟩
  let make (file : File) (line : Nat) (code : String) : StoredRow := ⟨⟨file,line⟩,code,#[]⟩
  let rows := #[make file 1 "heading",make file 2 "  child",make file 3 "",
    make file 4 "    leaf",make file 7 "    gap",make file 8 "  sibling",
    make {file with fingerprint := String.ofList (List.replicate 64 'b')} 9 "    other"]
  let prepared := LayoutFrameDependencies.prepare rows
  let wanted : List (Fin rows.size) := [⟨3,by decide⟩]
  let some result := LayoutFrameDependencies.close? prepared wanted | throw (IO.userError "layout fixture did not close")
  check ((result.selected.map Fin.val).mergeSort (· ≤ ·) == [0,1,3]) "nested layout lost its headings"
  let some repeated := LayoutFrameDependencies.close? prepared result.selected | throw (IO.userError "layout result did not close again")
  check ((repeated.selected.map Fin.val).mergeSort (· ≤ ·) == [0,1,3]) "layout closure added rows on second pass"
  for index in [4,5,6] do
    if bound : index < rows.size then
      let some isolated := LayoutFrameDependencies.close? prepared [⟨index,bound⟩] | throw (IO.userError "isolated row rejected")
      check (isolated.selected.length == 1) "layout crossed a read gap, sibling or fingerprint"

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "new layout diagnostic directory required")
  let out : System.FilePath := .mk destination
  check (!(← out.pathExists)) "preserve previous layout diagnostic"
  fixtures
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let reader ← Persistence.Store.NodeReader.new source
  let documents ← (← Build.entries source).mapM fun entry => Build.document reader entry.id
  let reads : Array Read := rows.flatMap fun row => row.origins.map fun origin =>
    ⟨origin.occurrence,⟨row.key.file,row.key.line,row.key.line⟩,origin.binding,#[]⟩
  let start ← IO.monoMsNow
  let prepared := LayoutFrameDependencies.prepare rows
  -- Materialize before timing; do not allow a pure let to move past clocks.
  let preparedRef ← IO.mkRef prepared
  let preparationMs := (← IO.monoMsNow)-start
  let prepared ← preparedRef.get
  let mut plans := #[]
  for topic in [1,2,3] do
    let bodyPath := project / s!"docs/candidates/prepared-bindings/resumed/trial/baseline/rep-0/topic-{topic}/body.txt"
    let body ← IO.FS.readFile bodyPath
    let shown := Extraction.presented body documents reads
    let requested := (List.finRange rows.size).filter fun index =>
      shown.ranges.any (fun range => range.contains ⟨rows[index].key.file,rows[index].key.line,rows[index].key.line⟩)
    let started ← IO.monoMsNow
    let some closed := LayoutFrameDependencies.close? prepared requested | throw (IO.userError "observed layout closure is incomplete")
    let saved ← IO.mkRef closed.selected
    let closureMs := (← IO.monoMsNow)-started
    let selected ← saved.get
    let additional := selected.filter (!requested.contains ·)
    let added := additional.map fun index => rows[index]
    plans := plans.push (topic,bodyPath.toString,Sha256.hex body.toUTF8,body.length,
      requested,selected,shown.ranges,added,closureMs)
  -- Human requirements enter only after every label-independent plan is fixed.
  let frozen : Array Json ← IO.ofExcept ((← read (project /
    "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let mut reports := #[]
  for (topic,bodyPath,bodySha,bodyChars,requested,selected,shown,added,closureMs) in plans do
    let some entry := frozen[topic-1]? | throw (IO.userError "missing frozen topic")
    let available : AvailableDelivery.Frozen ← IO.ofExcept (fromJson? (entry.getObjValD "available"))
    let extraRanges := added.toArray.map fun row => (⟨row.key.file,row.key.line,row.key.line⟩ : Range)
    let baseline := AvailableDelivery.assess available shown
    let potential := AvailableDelivery.assess available (shown ++ extraRanges)
    reports := reports.push (Json.mkObj [("topic",toJson topic),("actualBody",toJson bodyPath),
      ("actualBodySha256",toJson bodySha),("baseline",toJson baseline),("layoutPotential",toJson potential),
      ("requestedRows",toJson requested.length),("closedRows",toJson selected.length),
      ("additionalRows",toJson added.length),("additionalWireChars",toJson (added.map (fun row => (Packet.rowText row).length)).sum),
      ("actualBodyChars",toJson bodyChars),("closureMs",toJson closureMs),
      ("additionalKeys",toJson (added.map (·.key)))] )
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only diagnostic changed source"
  IO.FS.createDirAll out
  IO.FS.writeFile (out / "result.json") (Json.mkObj [("source",toJson source.head),
    ("sourceRows",toJson rows.size),("parentEdges",toJson prepared.parents.size),
    ("preparationMs",toJson preparationMs),("topics",toJson reports),
    ("layoutIsSemanticAuthority",toJson false),("budgetedSelectionOrActualDelivery",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Read-only layout prerequisite diagnostic complete; no new hook or answering model"
