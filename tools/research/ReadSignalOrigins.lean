import Eggshell.SynapseProvenance
open Lean Eggshell Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def array (value : Json) (name : String) : IO (Array Json) :=
  IO.ofExcept (value.getObjValAs? _ name)

/- Point-read native provenance for the consumers found by ReadSignalTrace.
This does not open/rebuild any derived index or simulate a graph traversal. -/
def main (args : List String) : IO Unit := do
  let [database,traceFile,destination] := args |
    throw (IO.userError "original source DB, recorded signal trace and fresh output required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve the previous native origin inspection"
  let traced ← read traceFile
  let source ← DB.PageMap.pin (.mk database)
  check (toJson source.head == traced.getObjValD "source") "native source differs from recorded hooks"
  let reader ← Persistence.Store.NodeReader.new source
  let mut known : Std.HashMap Occurrence (Option String) := {}
  let mut reports := #[]
  for topic in ← array traced "topics" do
    let receipt : System.FilePath := .mk (← IO.ofExcept (topic.getObjValAs? String "receipt"))
    let domain := (← read (receipt / "delivery-domain.json")).getObjValD "data"
    let nominated : Array String ← IO.ofExcept (domain.getObjValAs? _ "nominated")
    let hydrated : Array String ← IO.ofExcept (domain.getObjValAs? _ "hydrated")
    for unit in ← array topic "requirements" do
      for edge in ← array unit "consumed" do
        let occurrence : Occurrence ← IO.ofExcept (edge.getObjValAs? _ "consumer")
        let owner ← match known[occurrence]? with
          | some value => pure value
          | none => do
            let value ← match ← source.get (Provenance.name occurrence) with
              | none => pure none
              | some bytes => do
                let stored ← Provenance.decode (α := Provenance.Stored) bytes
                check (stored.origin.occurrence == occurrence) "metadata names a different consumer"
                let document ← Provenance.checkedDocument reader stored.origin
                let original ← reader.outcome (← reader.locateOutcome stored.origin.owner)
                check ((← Provenance.lookup? source original occurrence) == some stored.origin)
                  "consumer origin does not belong to its original native Work/Outcome"
                check (document.owner == Persistence.selectionKey original.relation)
                  "consumer document and original owner differ"
                pure (some document.owner)
            known := known.insert occurrence value
            pure value
        reports := reports.push (Json.mkObj [
          ("topic",topic.getObjValD "topic"),("names",unit.getObjValD "names"),
          ("term",edge.getObjValD "term"),("consumer",toJson occurrence),
          ("verifiedNativeOwner",toJson owner),("sourceMetadataPresent",toJson owner.isSome),
          ("nominatedRank",toJson (owner.bind fun owner =>
            (nominated.toList.zipIdx.find? fun (name,_) => name == owner).map Prod.snd)),
          ("hydrated",toJson (owner.map hydrated.contains)),
          ("actualRootEnqueueObserved",toJson false),("actualHintMembership",Json.null)])
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only provenance inspection changed source"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("uniqueConsumers",toJson known.size),
    ("consumers",toJson reports),("sourceUnchanged",toJson true),
    ("traversalExecuted",toJson false),("candidateChanged",toJson false),
    ("dbOrCacheWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println (Json.mkObj [("uniqueConsumers",toJson known.size),("sourceUnchanged",toJson true),
    ("traversalExecuted",toJson false)]).compress
