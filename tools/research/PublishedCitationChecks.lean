module
public import Eggshell.CanonicalSourceCache
public import tools.research.PublishedCitations
@[expose] public section
namespace PublishedCitationChecks
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Persistence.Store
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
abbrev Result := Eggshell.Research.PreparedCitationCoordinates.Result
structure Sample where
  owner : OutcomeEdge
  records : List SourceEvidence.Record
  texts : List (Nat × String)
  ready : Option PublishedCitations.Ready
  parser : PreparedCitationLinks.Parser

@[noinline,nospecialize] def reference (sample : Sample) : Option Result :=
  rankedCitedObservationCoordinates sample.texts sample.owner sample.records

@[noinline,nospecialize] def published (sample : Sample) : Except String (Option Result) :=
  PublishedCitations.queryUsing sample.parser.parse sample.ready sample.owner sample.records sample.texts

def timed (input : IO.Ref (Array Sample)) (prepared : Bool) : IO (Array (Option Result) × Nat) := do
  let started ← IO.monoNanosNow
  let samples ← input.get
  let result ← samples.mapM fun sample =>
    if prepared then IO.ofExcept (published sample) else pure (reference sample)
  let result ← (← IO.mkRef result).get
  return (result,((← IO.monoNanosNow)-started)/1000)

def control : IO Nat := do
  let record : SourceEvidence.Record := {workspace := "/",files := [⟨"src/Driver.cpp",none⟩],complete := false}
  let records := [[],[record],[record,{record with files := record.files++record.files}]]
  let works : List Value := [.text "sed\n{\"cmd\":\"sed -n '10,12p' src/Driver.cpp\"}",.text "MCP arbitrary input",
    .applyList .all [(.semantic,.text "structured work")],.atom ⟨#[255]⟩]
  let sources : List Value := [.text "10\t日本語\n11\t커널 café\n12\ttail\n",
    .text "10:first\n12:last\n10:duplicate\n",.text "\"10\\tfirst\\n11\\ttail\"",.applyList .all []]
  let parents := [[],[(0,"[Driver.cpp:10-12](src/Driver.cpp:10-12)")],
    [(3,"[Driver.cpp:10-12](src/Driver.cpp#L10-L12)"),(1,"[Driver.cpp:10](src/Driver.cpp:10)")],
    [(0,"[Driver.cpp:1-1000000000](src/Driver.cpp:1-1000000000)")]]
  let mut count := 0
  let mut positive := 0
  for work in works do
    for source in sources do
      let owner := OutcomeEdge.make work source [] (by simp) (by simp [maxOutcomeObservations])
      let ready := PublishedCitations.compile (Matcher.atomText? source) (Matcher.atomText? work)
      let encoded := toJson ready
      let decoded : Option PublishedCitations.Ready ← IO.ofExcept (fromJson? encoded)
      for records in records do
        for texts in parents do
          let sample : Sample := ⟨owner,records,texts,decoded,PreparedCitationLinks.Parser.prepare texts⟩
          let result ← IO.ofExcept (published sample)
          check (result == reference sample) "published coordinate roundtrip changed result"
          if result.isSome then positive := positive+1
          count := count+1
  check (positive > 0) "positive citation controls missing"
  for (first,last,characters) in [(1,1,10),(2,1,10),(1,12,10)] do
    let bad : PublishedCitations.Stored := ⟨characters,1,#[(first,last)],[],[]⟩
    check ((fromJson? (toJson bad.pack) : Except String PublishedCitations.Ready).toOption.isNone)
      "invalid bounded citation metadata was accepted"
    count := count+1
  for (rows,numbered) in [([1],[]),([],[1]),([],[1,2])] do
    let incomplete : PublishedCitations.Packed := ⟨10,1,rows,numbered,[]⟩
    check ((fromJson? (toJson incomplete) : Except String PublishedCitations.Ready).toOption.isNone)
      "partial flat coordinate record was accepted"
    count := count+1
  return count

def run (database output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve collected component result"
  let controls ← control
  let snapshot ← DB.PageMap.pin database
  let reader ← NodeReader.new snapshot
  let all ← snapshot.foldRange ⟨"candidate:","candidate;"⟩ (fun rows row => do
    let some id := (row.1.drop "candidate:".length).toString.toNat? | return rows
    if (← getNat snapshot.get row.1) != 1 then return rows
    let owner ← reader.outcome (← reader.locateOutcome id)
    return rows.push (id,owner,← reader.sources id)) (#[] : Array (Nat × OutcomeEdge × List SourceEvidence.Record))
  let topology ← reader.topology
  let parents := all.toList.zipIdx.filterMap fun ((_,owner,_),rank) => do
    let text ← Matcher.atomText? owner.outcome
    if topology.any (·.parent == owner.work) then some (rank,text) else none
  check (!parents.isEmpty) "real completed answer citations required"
  let parseStarted ← IO.monoNanosNow
  let parser ← (← IO.mkRef (PreparedCitationLinks.Parser.prepare parents)).get
  let prepareParentsUs := ((← IO.monoNanosNow)-parseStarted)/1000
  let mut samples := #[]
  let mut prepareUs := 0
  let mut encodedBytes := 0
  for (_,owner,records) in all do
    let started ← IO.monoNanosNow
    let ready ← (← IO.mkRef (PublishedCitations.compile
      (Matcher.atomText? owner.outcome) (Matcher.atomText? owner.work))).get
    let ready ← IO.ofExcept (fromJson? (toJson ready) : Except String (Option PublishedCitations.Ready))
    prepareUs := prepareUs+((← IO.monoNanosNow)-started)/1000
    encodedBytes := encodedBytes+(toJson ready).compress.utf8ByteSize
    samples := samples.push ⟨owner,records,parents,ready,parser⟩
  let input ← IO.mkRef samples
  let mut trials := #[]
  let mut positives := 0
  for repetition in [:3] do
    let order := if repetition%2 == 0 then #[false,true] else #[true,false]
    let a ← timed input order[0]!
    let b ← timed input order[1]!
    check (a.1 == b.1) "real source citation results differ"
    positives := (a.1.filter (·.isSome)).size
    trials := trials.push (Json.mkObj [("preparedFirst",toJson order[0]!),("referenceUs",toJson (if order[0]! then b.2 else a.2)),
      ("publishedUs",toJson (if order[0]! then a.2 else b.2)),("allResultsEqual",toJson true),
      ("resultSha256",toJson (Sha256.hex (toJson a.1).compress.toUTF8))])
  check (positives > 0) "real positive citation roundtrip required"
  check ((← DB.PageMap.pin database).head == snapshot.head) "component changed original source"
  IO.FS.writeFile output (Json.mkObj [("source",toJson snapshot.head),("owners",toJson all.size),
    ("parentInterpretations",toJson parents.length),("positiveOwners",toJson positives),("controls",toJson controls),
    ("prepareAndDecodeOnceUs",toJson prepareUs),("encodedMetadataBytes",toJson encodedBytes),("trials",toJson trials),
    ("prepareParentsOnceUs",toJson prepareParentsUs),
    ("allResultsEqual",toJson true),("originalHeadUnchanged",toJson true),("notWholeHookLatency",toJson true),
    ("allParentsNotActualQuestionNomination",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end PublishedCitationChecks
def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "published-citations DATABASE OUTPUT")
  PublishedCitationChecks.run (.mk database) (.mk output)
