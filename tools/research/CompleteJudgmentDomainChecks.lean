import tools.research.CompleteJudgmentDomain
import tools.research.AvailableDelivery
import Lean.Data.Json.Parser
open Lean Eggshell CompleteJudgmentDomain
namespace CompleteJudgmentDomainChecks
def check (condition : Bool) (message : String) : IO Unit := unless condition do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def fixtures : IO Unit := do
  let first : Document := ⟨"owner-a","work-a","opaque MCP read",
    "{\"環境\":\"production\",\"policy\":\"条件\\n末尾\"}"⟩
  let duplicate := {first with owner := "owner-b",work := "work-b"}
  let different : Document := ⟨"owner-c","work-c","arbitrary tool",
    String.ofList (List.replicate 4801 'x')++"\nFINAL-GUARD"⟩
  let catalogue ← IO.ofExcept (prepare (toJson "scope-a/head") #[first,duplicate,different] 2400)
  check (catalogue.paths[0]! == catalogue.paths[1]! && (catalogue.units[0]?).any (·.origins.size == 2))
    "equal payloads did not retain both original Work identities"
  check (catalogue.paths[2]!.size == 3 && (catalogue.units.back?).any (·.text.endsWith "FINAL-GUARD"))
    "non-divisible original tail was omitted"
  check (completeScores 3 #[2,0,1] && !completeScores 3 #[0,1] &&
    !completeScores 3 #[0,1,1] && !completeScores 3 #[0,1,3]) "score coverage accepted missing, duplicate or foreign pages"
  check (!(prepare Json.null #[first] 0).isOk && !(prepare Json.null #[first] 2401).isOk)
    "reader page bound was bypassed"
  for size in [0,1,2399,2400,2401,4800,4801] do
    let doc : Document := ⟨"boundary","boundary-work","opaque",
      String.ofList (List.replicate size '語')⟩
    let value ← IO.ofExcept (prepare Json.null #[doc] 2400)
    let texts ← value.paths[0]!.toList.mapM fun id => do
      let some page := value.units[id]? | throw (IO.userError "fixture path names absent page")
      pure page.text
    let text := String.join texts
    check (text == doc.source && value.units.all (·.text.length ≤ 2400)) "boundary or Unicode coverage changed"

def run (original frozen output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve independent complete-domain observation"
  fixtures
  let exported ← read original
  let reference ← read frozen
  check (exported.getObjValD "head" == reference.getObjValD "originalHead") "fixed source snapshot differs"
  let documents ← IO.ofExcept (exported.getObjValAs? (Array Document) "documents")
  let started ← IO.monoMsNow
  let catalogue ← IO.ofExcept (prepare (exported.getObjValD "head") documents 2400)
  let elapsed := (← IO.monoMsNow)-started
  let shown ← IO.ofExcept (ranges catalogue)
  let mut direct := #[]
  for page in catalogue.units do
    for origin in page.origins do
      let some doc := documents[origin.document]? | throw (IO.userError "page lost its original document")
      direct := direct.push (Synapses.Range.original
        (Synapses.ObservationContext.originalSubject doc.work doc.source) origin.first origin.stop)
  check (shown == direct) "cached original identities differ from direct original recomputation"
  let mut topics := #[]
  for topic in ← IO.ofExcept (reference.getObjValAs? (Array Json) "topics") do
    let frozen ← IO.ofExcept (fromJson? (α := Research.AvailableDelivery.Frozen) (topic.getObjValD "frozen"))
    let result := Research.AvailableDelivery.assess frozen shown
    topics := topics.push (Json.mkObj [("topic",topic.getObjValD "topic"),("inputAvailability",toJson result)])
  let chars := catalogue.units.foldl (fun n page => n+page.text.length) 0
  let report := Json.mkObj [("source",exported.getObjValD "head"),("documents",toJson documents.size),
    ("pages",toJson catalogue.units.size),("references",toJson (catalogue.paths.foldl (fun n path => n+path.size) 0)),
    ("fullCharactersForScoring",toJson chars),("maximumPageCharacters",toJson
      (catalogue.units.foldl (fun n page => max n page.text.length) 0)),("prepareMs",toJson elapsed),
    ("topics",toJson topics),("wholeOriginalRestorationChecked",toJson true),
    ("cachedRangesMatchDirect",toJson true),
    ("queryAndGoldenUsedToPrepare",toJson false),("modelCalls",toJson (0 : Nat)),
    ("actualHookDelivery",toJson false),("adopted",toJson false)]
  write output report
  write (output.withExtension "catalogue.json") (Json.mkObj [("source",catalogue.snapshot),
    ("documents",toJson (catalogue.documents.map fun doc => Json.mkObj [("owner",toJson doc.owner),("work",toJson doc.work)])),
    ("paths",toJson catalogue.paths),("units",toJson catalogue.units)])

/-- Prepare all complete numerical inputs before any inference. The queries
are unchanged from the earlier failed capsule experiment; no golden is read. -/
def scorePlans (catalogue originals previous template output : System.FilePath) (deadline : Nat := 30) : IO Unit := do
  check (0 < deadline && deadline ≤ 120) "bounded numerical deadline required"
  check (!(← output.pathExists)) "preserve the frozen full-domain numerical inputs"
  let data ← read catalogue
  let original ← read originals
  check (data.getObjValD "source" == original.getObjValD "head") "numerical pages and originals use different snapshots"
  let docs ← IO.ofExcept (original.getObjValAs? (Array Document) "documents")
  let pages ← IO.ofExcept (data.getObjValAs? (Array Json) "units")
  let mut documents := #[]
  for page in pages do
    let origins ← IO.ofExcept (page.getObjValAs? (Array Origin) "origins")
    let mut operations : Array String := #[]
    for origin in origins do
      let some doc := docs[origin.document]? | throw (IO.userError "numerical page has an absent original operation")
      unless operations.contains doc.invocation do operations := operations.push doc.invocation
    let text ← IO.ofExcept (page.getObjValAs? String "text")
    documents := documents.push ("Recorded operation:\n"++String.intercalate "\n" operations.toList++
      "\nOriginal output slice:\n"++text)
  let prior ← read previous
  let native ← read template
  IO.FS.createDir output
  for index in [:3] do
    let request := (prior.getObjValD s!"numerical-request-{index}.json").getObjValD "record"
    let query ← IO.ofExcept (request.getObjValAs? String "query")
    let body := Json.mkObj [("query",toJson query),("documents",toJson documents),("top_n",toJson documents.size)]
    let plan := native.setObjVal! "requests" (toJson #[Json.mkObj [
        ("name",toJson s!"complete-topic-{index+1}"),("body",body),("expectedFirst",Json.null)]])
      |>.setObjVal! "contextTokens" (toJson (4096 : Nat))
      |>.setObjVal! "requestDeadlineSeconds" (toJson deadline)
      |>.setObjVal! "output" (toJson (output/s!"topic-{index+1}").toString)
    write (output/s!"plan-{index+1}.json") plan
  write (output/"policy.json") (Json.mkObj [("allPages",toJson documents.size),
    ("sourceBeforeRanking",data.getObjValD "source"),("modelOrQueryChanged",toJson false),
    ("inputChange",toJson "all original-read pages and their recorded operations, instead of one shortened capsule per observation"),
    ("deadlineSeconds",toJson deadline),
    ("stop",toJson "each topic must return every page score within its frozen deadline; no width/model/prompt tuning"),
    ("actualHookDelivery",toJson false),("adopted",toJson false)])

/-- Complete the payload and its cost before opening the frozen labels.
Every cap is reported; the labels never choose a cutoff for production. -/
def assessScores (catalogue original scores frozen output : System.FilePath)
    (prior : Option System.FilePath := none) : IO Unit := do
  check (!(← output.pathExists)) "preserve the ranked-page effect measurement"
  let data ← read catalogue
  let originalData ← read original
  check (data.getObjValD "source" == originalData.getObjValD "head") "ranked pages use another source"
  let docs ← IO.ofExcept (originalData.getObjValAs? (Array Document) "documents")
  let source := store (data.getObjValD "source") docs
  let pages ← IO.ofExcept (data.getObjValAs? (Array PagePayload) "units")
  let identities := docs.map fun doc => Synapses.ObservationContext.originalSubject doc.work doc.source
  let headers := docs.mapIdx fun id doc => Json.mkObj [("document",toJson id),("owner",toJson doc.owner),
    ("original",toJson identities[id]!),("invocation",toJson doc.invocation)]
  let mut records := #[]
  let mut coordinates := #[]
  for page in pages do
    let mut spans := #[]
    for origin in page.origins do
      let some observed := source.originals[origin.document]? | throw (IO.userError "ranked page lacks an original")
      let some identity := identities[origin.document]? | throw (IO.userError "ranked page lacks original identity")
      check (page.content == identity.content && page.text == HistoryAccess.slice observed.text page.first page.stop &&
        observed.offsets[page.first]? == some origin.first && observed.offsets[page.stop]? == some origin.stop)
        "ranked page text or coordinates differ from the fixed original"
      spans := spans.push (Synapses.Range.original identity origin.first origin.stop)
    records := records.push (Json.mkObj [("origins",toJson page.origins),("text",toJson page.text)])
    coordinates := coordinates.push spans
  let result ← read scores
  let measurements ← IO.ofExcept (result.getObjValAs? (Array Json) "measurements")
  check (measurements.size == 1) "one fixed ranked question required"
  let measurement := measurements[0]!
  let rows ← IO.ofExcept ((measurement.getObjValD "response").getObjValAs? (Array Json) "results")
  let ids ← rows.mapM fun row => IO.ofExcept (row.getObjValAs? Nat "index")
  check (completeScores pages.size ids) "ranked source omitted, duplicated or invented a page"
  let pageOrigins := pages.map (·.origins)
  let packet := fun (indices : Array Nat) => Id.run do
    let used := Std.HashSet.ofArray (indices.flatMap fun id => pageOrigins[id]!.map (·.document))
    let origins := headers.zipIdx.filterMap fun (header,id) => if used.contains id then some header else none
    return Json.mkObj [("status",toJson "advisory"),("source",data.getObjValD "source"),
      ("originals",toJson origins),("observations",toJson (indices.map fun id => records[id]!))]
  let mut packets := #[]
  for limit in [8000,16000,32000,64000,120000] do
    let mut selected : Array Nat := #[]
    for id in ids do
      let proposal := selected.push id
      let rendered := (packet proposal).compress
      if rendered.length ≤ limit && rendered.utf8ByteSize ≤ limit*4 then selected := proposal
    let body := (packet selected).compress
    let shown := selected.flatMap fun id => coordinates[id]!
    packets := packets.push (limit,selected,body,shown)
  -- Only now is the answer-key file opened.
  let expected ← read frozen
  check (expected.getObjValD "originalHead" == data.getObjValD "source") "effect labels use another source"
  let topics ← IO.ofExcept (expected.getObjValAs? (Array Json) "topics")
  let name ← IO.ofExcept (measurement.getObjValAs? String "name")
  let number := (name.splitOn "-").getLast!.toNat?.getD 0
  let some topic := topics.find? (·.getObjValD "topic" == toJson number) | throw (IO.userError "ranked question has no fixed labels")
  let frozen ← IO.ofExcept (fromJson? (α := Research.AvailableDelivery.Frozen) (topic.getObjValD "frozen"))
  let reports := packets.map fun (limit,selected,body,shown) =>
    let coverage := Research.AvailableDelivery.assess frozen shown
    Json.mkObj [("limit",toJson limit),("characters",toJson body.length),("bytes",toJson body.utf8ByteSize),
      ("selectedPages",toJson selected),("eligible",toJson coverage.eligible),("included",toJson coverage.delivered),
      ("missing",toJson coverage.missing),("body",toJson body)]
  if let some previous := prior then
    check ((← read previous).getObjValD "caps" == toJson reports)
      "reference diagnosis changed a previously frozen ranked packet"
  -- An answer-key witness only. It is deliberately unavailable to the
  -- ranker and packet choices above, and is never sent to a product hook.
  let mut witness : Array Nat := #[]
  for required in frozen.units do
    let mut best : Option (Array Nat) := none
    for alternative in required.alternatives do
      let matchingPages := (Array.range pages.size).filter fun id => coordinates[id]!.any fun observed =>
        alternative.any fun wanted => (observed.intersection? wanted).isSome
      let proposal := (witness.toList++matchingPages.toList).eraseDups.toArray
      let shown := proposal.flatMap fun id => coordinates[id]!
      let checked := Research.AvailableDelivery.assess ⟨#[required],#[]⟩ shown
      if checked.delivered != 1 then continue
      if best.isNone || (packet proposal).compress.length < (packet best.get!).compress.length then best := some proposal
    let some selected := best | throw (IO.userError "complete input has no realizable reference-page witness")
    witness := selected
  let witnessBody := (packet witness).compress
  let witnessCoverage := Research.AvailableDelivery.assess frozen (witness.flatMap fun id => coordinates[id]!)
  write output (Json.mkObj [("topic",toJson number),("caps",toJson reports),
    ("referenceOnlyWitness",Json.mkObj [("characters",toJson witnessBody.length),("bytes",toJson witnessBody.utf8ByteSize),
      ("eligible",toJson witnessCoverage.eligible),("included",toJson witnessCoverage.delivered),
      ("pages",toJson witness),("body",toJson witnessBody),("globallyMinimumClaim",toJson false),
      ("usedByCandidateOrHook",toJson false)]),
    ("elapsedMs",measurement.getObjValD "elapsedMs"),("usage",(measurement.getObjValD "response").getObjValD "usage"),
    ("allPageScoresChecked",toJson true),("labelsReadAfterPacking",toJson true),
    ("actualHookDelivery",toJson false),("mainAnsweringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
end CompleteJudgmentDomainChecks
#print axioms CompleteJudgmentDomain.character_has_page
#print axioms CompleteJudgmentDomain.complete_scores_size
#print axioms CompleteJudgmentDomain.complete_scores_cover
#print axioms CompleteJudgmentDomain.Catalogue.original_identities
def main : List String → IO Unit
  | ["witness-all",catalogue,original,scoring,frozen,directory] => do
      for topic in [1,2,3] do
        CompleteJudgmentDomainChecks.assessScores (.mk catalogue) (.mk original)
          (System.FilePath.mk scoring/s!"topic-{topic}/result.json") (.mk frozen)
          (System.FilePath.mk directory/s!"effect-witness-{topic}.json")
          (some (System.FilePath.mk directory/s!"effect-{topic}.json"))
  | ["assess-scores",catalogue,original,scores,frozen,output,previous] =>
      CompleteJudgmentDomainChecks.assessScores (.mk catalogue) (.mk original) (.mk scores) (.mk frozen) (.mk output) (some (.mk previous))
  | ["plans",catalogue,original,previous,template,output,seconds] =>
      CompleteJudgmentDomainChecks.scorePlans (.mk catalogue) (.mk original) (.mk previous) (.mk template) (.mk output) (seconds.toNat?.getD 0)
  | ["assess-scores",catalogue,original,scores,frozen,output] =>
      CompleteJudgmentDomainChecks.assessScores (.mk catalogue) (.mk original) (.mk scores) (.mk frozen) (.mk output)
  | ["plans",catalogue,original,previous,template,output] =>
      CompleteJudgmentDomainChecks.scorePlans (.mk catalogue) (.mk original) (.mk previous) (.mk template) (.mk output)
  | [original,frozen,output] => CompleteJudgmentDomainChecks.run (.mk original) (.mk frozen) (.mk output)
  | _ => throw (IO.userError "CompleteJudgmentDomainChecks ORIGINAL FROZEN OUTPUT")
