import Eggshell.SynapseTransport
open Lean Eggshell Eggshell.Synapses

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def array (value : Json) (name : String) : IO (Array Json) :=
  IO.ofExcept (value.getObjValAs? _ name)

structure BindingDocument where
  document : Extraction.Document
  capturedFiles : Array File

private def load (reader : Persistence.Store.NodeReader source) (owner : String) : IO BindingDocument := do
  check (owner.startsWith "v") "original binding owner is not a native selection key"
  let ids ← Persistence.Store.getIds source.get ("owner:" ++ (owner.drop 1).toString)
  let live ← ids.filterM fun id => return (← source.get (Persistence.Store.key "member" id)).isSome
  let [id] := live | throw (IO.userError "original owner is missing or ambiguous")
  let edge ← reader.outcome (← reader.locateOutcome id)
  check (Persistence.selectionKey edge.relation == owner) "owner hash lookup crossed a complete native relation"
  let provenance ← reader.sources id
  let transportOwner : Transport.Owner := {database := source.head.identity,original := edge,provenance}
  let document ← IO.ofExcept transportOwner.document
  let captured ← ContentMetadata.load? source id document
  let files := captured.map (fun capture => capture.inputs.filterMap fun input =>
    input.content.map fun content => (⟨input.relative,content.root,content.bytes⟩ : File)) |>.getD #[]
  return ⟨document,files⟩

/- Diagnose the existing product predicate, without relaxing it. A proposed
metadata union is measured only; no document, DB or selector is modified. -/
def main (args : List String) : IO Unit := do
  let [database,signalsPath,destination] := args |
    throw (IO.userError "original source, frozen missing-signal audit and fresh output")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve the previous binding predicate audit"
  let signals ← read signalsPath
  let source ← DB.PageMap.pin (.mk database)
  check (toJson source.head == signals.getObjValD "source") "signals differ from the original publication"
  let reader ← Persistence.Store.NodeReader.new source
  let mut originals : Std.HashMap String BindingDocument := {}
  let mut reports := #[]
  for unit in ← array signals "rows" do
    if unit.getObjValD "missing" != toJson true then continue
    let mut rows := #[]
    for value in ← array unit "reads" do
      let recorded : Read ← IO.ofExcept (fromJson? value)
      let owner := recorded.binding.owner
      let prepared ← match originals[owner]? with
        | some prepared => pure prepared
        | none => do
          let prepared ← load reader owner
          originals := originals.insert owner prepared
          pure prepared
      let before := ObservationContext.OriginalOwner.prepare? prepared.document
      let beforePasses := before.any fun original =>
        Transport.boundTo source.head.identity prepared.document original.identity recorded
      let augmented := {prepared.document with
        files := (hashDistinct (prepared.document.files.toList ++ prepared.capturedFiles.toList)).toArray}
      let after := ObservationContext.OriginalOwner.prepare? augmented
      let afterPasses := after.any fun original => Transport.boundTo source.head.identity augmented original.identity recorded
      rows := rows.push (Json.mkObj [
        ("owner",toJson owner),("source",toJson recorded.source),("binding",toJson recorded.binding),
        ("originalFileRecorded",toJson (recorded.source.file?.map prepared.document.files.contains)),
        ("capturedFileRecorded",toJson (recorded.source.file?.map prepared.capturedFiles.contains)),
        ("originalPredicate",toJson beforePasses),("withCapturedFilesPredicate",toJson afterPasses)])
    reports := reports.push (Json.mkObj [("topic",unit.getObjValD "topic"),("names",unit.getObjValD "names"),
      ("reads",toJson rows)])
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only binding diagnosis changed source"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("sourceUnchanged",toJson true),
    ("ownersRead",toJson originals.size),("requirements",toJson reports),
    ("productionPredicateUsed",toJson true),("candidateChanged",toJson false),
    ("dbOrCacheWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println (Json.mkObj [("ownersRead",toJson originals.size),("requirements",toJson reports.size),
    ("sourceUnchanged",toJson true)]).compress
