module
public import Eggshell.CanonicalSourceCache
public import tools.research.PreparedCitationCoordinates
@[expose] public section

namespace Eggshell.Research.PreparedCitationChecks
open Lean Plugin Synapses Persistence.Store

def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
abbrev Result := PreparedCitationCoordinates.Result
structure Sample where
  name : String
  owner : OutcomeEdge
  records : List SourceEvidence.Record
  texts : List (Nat × String)
  prepared : Option (Sigma PreparedCitationCoordinates.Data)

@[noinline,nospecialize] def original (texts : List (Nat × String)) (owner : OutcomeEdge)
    (records : List SourceEvidence.Record) : Option Result :=
  rankedCitedObservationCoordinates texts owner records

def timed (input : IO.Ref (Array Sample)) (prepared : Bool) : IO (Array (String × Option Result) × Nat) := do
  let samples ← input.get
  let started ← IO.monoMsNow
  let result ← (← IO.mkRef (samples.map fun sample => (sample.name,
    if prepared then PreparedCitationCoordinates.query sample.prepared sample.texts
    else original sample.texts sample.owner sample.records))).get
  return (result,(← IO.monoMsNow)-started)

def controls : IO Nat := do
  let record : SourceEvidence.Record := {workspace := "/",files := [⟨"src/Driver.cpp",none⟩],complete := false}
  let records := [[],[record],[record,{record with files := record.files++record.files}]]
  let works : List Value := [.text "sed -n '10,12p' src/Driver.cpp",.text "MCP: arbitrary tool input",
    .applyList .all [(.semantic,.text "structured work")],.atom ⟨#[255]⟩]
  let outputs : List Value := [.text "10\t日本語\n11\t커널 café\n12\ttail\n",
    .text "10:first\n12:last\n10:duplicate\n",.text "{\"text\":\"10\\tfirst\\n11\\ttail\"}",
    .applyList .all []]
  let parents : List (List (Nat × String)) := [[],[(0,"[Driver.cpp:10-12](src/Driver.cpp:10-12)")],
    [(3,"[Driver.cpp:10-12](src/Driver.cpp#L10-L12)"),(1,"[Driver.cpp:10](src/Driver.cpp:10)")],
    [(0,"[Driver.cpp:1-1000000000](src/Driver.cpp:1-1000000000)")]]
  let mut cases := 0
  for work in works do
    for output in outputs do
      let owner := OutcomeEdge.make work output [] (by simp) (by simp [maxOutcomeObservations])
      for records in records do
        let ready := PreparedCitationCoordinates.prepare owner records
        for texts in parents do
          check (original texts owner records == PreparedCitationCoordinates.query ready texts)
            "compiled citation coordinates changed windows, ranks, complete ranges or absence"
          cases := cases+1
  let positive := OutcomeEdge.make (.text "read") (.text "10\tfirst\n11\ttail\n") []
    (by simp) (by simp [maxOutcomeObservations])
  check ((original [(0,"[Driver.cpp:10-11](src/Driver.cpp:10-11)")] positive [record]).isSome)
    "positive numbered citation control did not resolve original rows"
  return cases

def run (database output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve previous citation coordinate result"
  let cases ← controls
  let source ← DB.PageMap.pin database
  let some metadata ← CanonicalSource.Cache.open? source .user | throw (IO.userError "prepared original metadata unavailable")
  let path ← CanonicalSource.Cache.directory source .user
  let some index ← CanonicalSource.Cache.preparedAt? source path metadata.metadata |
    throw (IO.userError "original metadata changed its pinned head")
  let reader ← NodeReader.new source
  let originals ← index.foldRange ⟨"view-document:","view-document;"⟩ (fun rows row => do
    let some id := (row.1.drop "view-document:".length).toString.toNat? | return rows
    let owner ← reader.outcome (← reader.locateOutcome id)
    let records ← reader.sources id
    return rows.push (id,owner,records)) (#[] : Array (Nat × OutcomeEdge × List SourceEvidence.Record))
  check (originals.size == 40) "all forty original owners required"
  let topology ← reader.topology
  let authority ← Persistence.Store.authority source
  let persistent := (← reader.unions authority).map (·.edge)
  let allCandidates ← source.foldRange ⟨"candidate:","candidate;"⟩ (fun rows row => do
    let some id := (row.1.drop "candidate:".length).toString.toNat? | return rows
    if (← getNat source.get row.1) != 1 then return rows
    let owner ← reader.outcome (← reader.locateOutcome id)
    return rows.push owner) (#[] : Array OutcomeEdge)
  let parents := allCandidates.toList.zipIdx.filterMap fun (owner,rank) => do
    let text ← Matcher.atomText? owner.outcome
    if topology.any (·.parent == owner.work) then some (rank,owner.work,text) else none
  let mut samples := #[]
  let mut preparationMs := 0
  for (_,owner,records) in originals do
    let texts := parents.filterMap fun (rank,work,text) =>
      if (sourceNeighborhood [work] topology persistent).any (·.work == owner.work) then some (rank,text) else none
    let began ← IO.monoMsNow
    let prepared ← (← IO.mkRef (PreparedCitationCoordinates.prepare owner records)).get
    preparationMs := preparationMs+((← IO.monoMsNow)-began)
    samples := samples.push {name := relationKey owner.relation,owner,records,texts,prepared}
  let input ← IO.mkRef samples
  let mut rows := #[]
  let mut positive := 0
  for repetition in [:3] do
    let order := if repetition%2 == 0 then #[false,true] else #[true,false]
    let a ← timed input order[0]!
    let b ← timed input order[1]!
    check (a.1 == b.1) "actual owner citation coordinates differ"
    positive := (a.1.filter (·.2.isSome)).size
    rows := rows.push (Json.mkObj [("repetition",toJson repetition),("preparedFirst",toJson order[0]!),
      ("originalMs",toJson (if order[0]! then b.2 else a.2)),("preparedMs",toJson (if order[0]! then a.2 else b.2)),
      ("outputSha256",toJson (Sha256.hex (toJson a.1).compress.toUTF8)),("fullOutputEqual",toJson true)])
  let after ← DB.PageMap.pin database
  check (source.head == after.head) "citation preparation changed original publication"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("metadata",toJson metadata.metadata),
    ("owners",toJson samples.size),("liveOriginalCandidates",toJson allCandidates.size),
    ("parentInterpretations",toJson parents.length),("positiveOwners",toJson positive),
    ("actualSavedCitationsExercised",toJson (decide (positive > 0))),("positiveNumberedCitationControl",toJson true),
    ("compiledRows",toJson (samples.foldl (fun total sample => total+
      (sample.prepared.map (fun view => view.2.numbered.length)).getD 0) (0 : Nat))),
    ("prepareOnceMs",toJson preparationMs),("controls",toJson cases),("rows",toJson rows),
    ("originalHeadUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("scope",toJson "all persisted owners, all original interpretation parents in directory order, original reachability; not actual query nomination order or full hook latency")]).compress

end Eggshell.Research.PreparedCitationChecks
def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "citation coordinates DATABASE OUTPUT")
  Eggshell.Research.PreparedCitationChecks.run (.mk database) (.mk output)
