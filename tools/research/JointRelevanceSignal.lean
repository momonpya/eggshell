import Eggshell.Handoff
import tools.research.FrozenCanonicalBasis
import tools.research.AvailableDelivery
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"

private def units (rows : Array StoredRow) : Array (List (Fin rows.size)) :=
  ((Records.catalogue rows (Records.prepare rows)).filter fun indices =>
    !("\n".intercalate (indices.map fun index => rows[index].code)).trimAscii.isEmpty).toArray

def main (args : List String) : IO Unit := do
  let [mode,rootPath] := args | throw (IO.userError "export/assess owned joint-relevance directory")
  let root : System.FilePath := .mk rootPath
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let candidates := units rows
  let texts := candidates.map fun indices => "\n".intercalate (indices.map fun index => rows[index].code)
  if mode == "export" then
    check (!(← (root / "input.json").pathExists)) "preserve previous numerical input"
    let initial ← read (study / "seed-originals.json")
    let docs : Array Json ← IO.ofExcept (initial.getObjValAs? _ "documents")
    let requests : List String ← IO.ofExcept (docs.toList.mapM fun doc => doc.getObjValAs? _ "workText")
    let mut questions := #[]
    for topic in [1,2,3] do
      let prompt ← IO.FS.readFile (study / s!"prompts/topic-{topic}.txt")
      let query := evidenceFocusQuestion prompt requests
      questions := questions.push (Json.mkObj [("topic",toJson topic),("query",toJson query),
        ("promptSha256",toJson (Sha256.hex prompt.toUTF8))])
    IO.FS.createDirAll root
    IO.FS.writeFile (root / "input.json") (Json.mkObj [("source",toJson source.head),
      ("questions",toJson questions),("texts",toJson texts),
      ("candidateKeys",toJson (candidates.map fun indices => indices.map fun index => rows[index].key)),
      ("sourceRows",toJson rows.size),("sourceTextSha256",toJson (Sha256.hex (toJson texts).compress.toUTF8))]).compress
    IO.println s!"Exported {candidates.size} bounded original units; labels not read"
    return
  check (mode == "assess") "unknown signal action"
  check (!(← (root / "assessment.json").pathExists)) "preserve earlier joint-relevance assessment"
  let input ← read (root / "input.json")
  check (input.getObjValD "source" == toJson source.head && input.getObjValD "texts" == toJson texts)
    "numerical input crossed fixed original domain"
  let result ← read (root / "scores.json")
  check (result.getObjValD "inputSha256" == toJson (Sha256.hex (← IO.FS.readBinFile (root / "input.json"))))
    "numerical result crossed input"
  let outputs : Array Json ← IO.ofExcept (result.getObjValAs? _ "topics")
  check (outputs.size == 3) "missing joint-relevance question"
  let mut ordered : Array (Nat × Array Nat × Nat) := #[]
  for output in outputs do
    let topic : Nat ← IO.ofExcept (output.getObjValAs? _ "topic")
    let scores : Array Float ← IO.ofExcept (output.getObjValAs? _ "scores")
    check (scores.size == candidates.size && scores.all (fun value => !value.isNaN && !value.isInf))
      "invalid joint-relevance numerical shape"
    let queryTokens : Nat ← IO.ofExcept (output.getObjValAs? _ "queryTokens")
    let segments : Array Json ← IO.ofExcept (output.getObjValAs? _ "segmentBounds")
    let mut coverage : Std.HashMap Nat (Nat × Nat) := {}
    for segment in segments do
      let values : Array Json ← IO.ofExcept segment.getArr?
      check (values.size == 4) "invalid token coverage coordinates"
      let owner ← IO.ofExcept (values[0]!.getNat?)
      let first ← IO.ofExcept (values[1]!.getNat?)
      let last ← IO.ofExcept (values[2]!.getNat?)
      let total ← IO.ofExcept (values[3]!.getNat?)
      let previous := coverage[owner]?.getD (0,total)
      check (owner < candidates.size && first ≤ previous.1 && first < last && last ≤ total &&
        previous.2 == total && last-first+queryTokens+3 ≤ 512) "truncated, foreign or oversized source-token segment"
      coverage := coverage.insert owner (max previous.1 last,total)
    check (coverage.size == candidates.size && coverage.toArray.all (fun entry => entry.2.1 == entry.2.2))
      "joint relevance did not cover every source token"
    let ranking := (List.range scores.size).toArray.qsort fun a b =>
      if scores[a]! == scores[b]! then a < b else scores[a]! > scores[b]!
    let prefixRows := Id.run do
      -- More optimistic than a real packet: whitespace-only original rows
      -- are supplied without charge, so a missing blank line cannot make the
      -- numerical signal fail the probe. No missing nonblank text is invented.
      let mut paid : Std.HashSet Nat := Std.HashSet.ofList ((List.finRange rows.size).filterMap
        fun index => if rows[index].code.trimAscii.isEmpty then some index.val else none)
      let mut chars := 0
      for id in ranking do
        let next := (candidates[id]!).filter fun index => !paid.contains index.val
        let cost := (next.map fun index => (Packet.rowText rows[index]).length).sum
        if 120000 < chars+cost then break
        chars := chars+cost
        for index in next do paid := paid.insert index.val
      return (paid.toArray.qsort (· < ·),chars)
    ordered := ordered.push (topic,prefixRows.1,prefixRows.2)
  -- Required labels are opened only after every numerical ranking and prefix.
  let frozen : Array Json ← IO.ofExcept ((← read (project /
    "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let mut reports := #[]
  for (topic,selected,chars) in ordered do
    let available : AvailableDelivery.Frozen ← IO.ofExcept (fromJson? (frozen[topic-1]!.getObjValD "available"))
    let shown ← selected.mapM fun index => do
      let some row := rows[index]? | throw (IO.userError "numerical rank escaped original source domain")
      return (⟨row.key.file,row.key.line,row.key.line⟩ : Range)
    reports := reports.push (Json.mkObj [("topic",toJson topic),("optimisticPrefix",toJson (AvailableDelivery.assess available shown)),
      ("originalRowWireCharsOnly",toJson chars),("selectedRows",toJson selected.size)])
  check ((← DB.PageMap.pin source.directory).head == source.head) "signal diagnostic changed original DB"
  IO.FS.writeFile (root / "assessment.json") (Json.mkObj [("reports",toJson reports),
    ("sourceRows",toJson rows.size),("candidates",toJson candidates.size),
    ("optimisticNoControlOrFramesCharged",toJson true),("actualHook",toJson false),
    ("whitespaceOriginalRowsFree",toJson true),("sourceTokenCoverageChecked",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Joint relevance signal assessed; optimistic prefix is not actual budgeted delivery"
