import Eggshell.SynapseJournal
import Eggshell.Handoff

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def publish (source : DB.PageMap.Snapshot) (values : List Value) :
    IO (DB.PageMap.Snapshot × List Nat) := do
  let (ids,_,_) ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    writeChange writer ⟨ids,[],false⟩
    return ids
  return (← DB.PageMap.pin source.directory,ids)

private def original (session : String) (tool : ToolEvent) : IO OutcomeEdge := do
  let some edge := OutcomeEdge.fromValue? (compileOperationOutcomes (.text session) (.text "turn") tool).2 |
    throw (IO.userError "invalid native fixture")
  return edge

private def family (answer read : OutcomeEdge) : IO Value := do
  if distinct : answer.work ≠ read.work then
    return (AllEdge.make answer.work [read.work] (by simp) (by simpa using distinct)).relation
  throw (IO.userError "fixture Work collision")

private def facts (source : DB.PageMap.Snapshot) : IO (Array Fact) := do
  let some ready ← Index.open? source .database .shared | throw (IO.userError "missing index")
  Index.allFacts ready.index

private def quoteChecks : IO Unit := do
  let quoted := Quotes.extract "`alpha` ``a`b`` `終端` `unfinished"
  check (quoted.map (·.text) == #["alpha","a`b","終端"]) "literal quote delimiters changed the source spelling"
  check ((Quotes.extract "`unfinished").isEmpty && (Quotes.extract "ordinary prose").isEmpty)
    "unfinished quotes or prose created quotation evidence"
  let doc : Document := {
    owner := "owner",work := "work",workText := some "mcp__any__read\n{}"
    source := some (Json.mkObj [("text",toJson "one FIRST_01\ntwo SECOND_02\nthree THIRD_03\n")]).compress
    native := true,occurrences := #[⟨"session","turn","read"⟩],files := #[]}
  let some catalog := ObservationContext.recorded "database" doc | throw (IO.userError "missing generic catalog")
  let middle := catalog.quotations.filter (·.text == "two SECOND_02")
  let some item := middle[0]? | throw (IO.userError "missing middle row")
  check (middle.size == 1 && item.read.source.file?.isNone)
    "multiline structured value did not retain an independent original row"
  let read := item.read
  let selected := project (catalog.located.flatMap (·.rows)) (read.binding.first+4) (read.binding.limit-2)
  check (selected == #[read.source]) "a native row expanded to its entire enclosing JSON member"

private def scenario (root : System.FilePath) : IO Unit := do
  let lookup : ToolEvent := {
    name := "mcp__catalog__lookup",useId := "lookup",input := "{}"
    response := (Json.mkObj [("id",toJson "RECORD_42"),("status",toJson "READY_17"),
      ("detail",toJson (String.ofList (List.replicate 5000 'x')))]).compress}
  let inspect : ToolEvent := {
    name := "mcp__catalog__inspect",useId := "inspect"
    input := (Json.mkObj [("id",toJson "RECORD_42")]).compress
    response := (Json.mkObj [("result",toJson "SUCCESS_23"),
      ("trace",toJson "one FIRST_01\ntwo SECOND_02\nthree THIRD_03\n")]).compress}
  let follow : ToolEvent := {
    name := "mcp__catalog__follow",useId := "follow"
    input := (Json.mkObj [("term",toJson "SECOND_02")]).compress
    response := (Json.mkObj [("ok",toJson true)]).compress}
  let outside : ToolEvent := {
    name := "mcp__other__lookup",useId := "outside",input := "{}"
    response := (Json.mkObj [("not_a_value",toJson "OUTSIDE_91")]).compress}
  let a ← original "first" lookup
  let again ← original "second" lookup
  let b ← original "first" inspect
  let c ← original "first" follow
  let outside ← original "first" outside
  let answer := OutcomeEdge.make (.text "question")
    (.text "The state is `READY_17`; the result is `SUCCESS_23`.\n\n`OUTSIDE_91` and `not_a_value` are not evidence here.")
    [] (by simp) (by simp [maxOutcomeObservations])
  let source ← DB.PageMap.create (root / "source.egg") "native-rebuild"
  let (source,ids) ← publish source [a.relation,again.relation,b.relation,c.relation,outside.relation,
    answer.relation,← family answer a,← family answer b,← family answer c]
  let domain := String.ofList (List.replicate 64 'a')
  let occurrence := fun session name => Occurrence.mk session "turn" name
  let some receivedUnixMs ← ObservationAge.now | throw (IO.userError "missing wall clock")
  let expiredUnixMs := receivedUnixMs-ObservationAge.monthMs-60000
  let source ← Provenance.publish source #[
    ⟨ids[2]!,occurrence "first" "inspect",domain,30,40,some (receivedUnixMs-1000)⟩,
    ⟨ids[0]!,occurrence "first" "lookup",domain,10,20,some expiredUnixMs⟩,
    ⟨ids[3]!,occurrence "first" "follow",domain,50,60,none⟩,
    ⟨ids[1]!,occurrence "second" "lookup",domain,10,20,none⟩]
  let originalTimes := (← Provenance.records source).map (·.origin)
  let before := source.head
  let first ← Build.refresh source .database
  let all ← facts source
  let reads := all.filterMap fun fact => match fact with | .read read => some read | _ => none
  let supports := all.filterMap fun fact => match fact with | .supports support => some support | _ => none
  check (first.mode == "rebuild" && first.unsupported == 0 && supports.size == 3 &&
      first.consumptionRebuilt && first.provenanceOriginals == 4 && first.provenanceIgnored == 0)
    "automatic native quotes failed, or unreachable/key-only spellings became support"
  check (supports.all (fun support => support.read.source.file?.isNone &&
      support.claim.answer == Persistence.selectionKey answer.relation))
    "general support invented a source file or another answer"
  let portable ← Provenance.derive source
  check (portable.originals == 4 && portable.ignored == 0) "portable reconstruction silently dropped a non-shell Work"
  let edges := portable.graph.snapshot.filterMap fun fact => match fact with | .consumed edge => some edge | _ => none
  check (edges.size == 2 && edges.all (!·.rows.isEmpty)) "portable MCP consumption lost its exact original ranges"
  let middle := reads.filter (fun read => read.quotations.contains (Quotes.digest "two SECOND_02"))
  check (middle.size == 1 && edges.any (fun edge => edge.term == "SECOND_02" && edge.rows == #[middle[0]!.source]))
    "MCP data flow selected the enclosing long value instead of the consumed row"
  let statuses := reads.filter (fun read => read.quotations.contains (Quotes.digest "READY_17"))
  check (statuses.size == 2 && statuses[0]!.source == statuses[1]!.source &&
    statuses[0]!.binding.owner != statuses[1]!.binding.owner)
    "cross-session native data did not share a canonical interval with distinct origins"
  let ready ← Build.refresh source .database
  check (ready.mode == "warm" && ready.hydrated == 0 && ready.index == first.index &&
      (← DB.PageMap.pin source.directory).head == before) "warm rehydrated bodies or changed native source authority"
  let unrelated := OutcomeEdge.make (.text "unrelated") (.text "no literal quotes") [] (by simp) (by simp [maxOutcomeObservations])
  let (source,_) ← publish source [unrelated.relation]
  let added ← Build.refresh source .database
  check (added.mode == "incremental" && added.hydrated == 1 && !added.consumptionRebuilt &&
      added.provenanceOriginals == 0 && (← facts source) == all)
    "unrelated answer rehydrated old native bodies or changed their graph"
  let quoted := OutcomeEdge.make (.text "followup-question") (.text "State: `READY_17`.") [] (by simp) (by simp [maxOutcomeObservations])
  let (source,_) ← publish source [quoted.relation,← family quoted a]
  let updated ← Build.refresh source .database
  check (updated.mode == "incremental" && updated.hydrated == 3 && !updated.consumptionRebuilt && updated.provenanceOriginals == 0)
    "new quotation did not hydrate only its answer and the two matching actual origins"
  let expected ← facts source
  let destination := root / "db-only.egg"
  IO.FS.createDirAll destination
  for entry in ← source.directory.readDir do
    if entry.fileName == "head" || entry.fileName.endsWith ".pages" then
      IO.FS.writeBinFile (destination / entry.fileName) (← IO.FS.readBinFile entry.path)
  let copied ← DB.PageMap.pin destination
  let rebuilt ← Build.refresh copied .database
  check (rebuilt.mode == "rebuild" && (← facts copied) == expected && copied.head == source.head)
    "DB-only rebuild disagreed with live incremental derivation/support/coquotation"
  let privateBuild ← Build.refresh copied .user
  let some privateIndex ← Index.open? copied .user .shared | throw (IO.userError "missing read-only private index")
  check ((← Index.allFacts privateIndex.index) == expected &&
      (← DB.PageMap.pin copied.directory).head == copied.head)
    "private reconstruction changed native facts or source authority"
  check ((← Provenance.records copied).map (·.origin) == originalTimes)
    "DB-only rebuild or repeated warm rewrote acquisition dates"
  let prepared ← Recommend.prepare copied false
  let owners : Array Synapses.Transport.Owner := #[
    ⟨copied.head.identity,a,[]⟩,⟨copied.head.identity,again,[]⟩,⟨copied.head.identity,b,[]⟩,⟨copied.head.identity,c,[]⟩]
  let query := String.ofList (List.replicate 64 'b')
  let plan ← Synapses.Transport.build #[prepared] #[(Persistence.selectionKey answer.relation,0)] owners query ((← IO.monoMsNow)+5000)
  let offers := plan.results.flatMap (·.admitted)
  check (plan.observations.any (·.age.status == .recent) &&
    plan.observations.any (·.age.status == .expired) &&
    plan.observations.any (·.age.status == .unknown))
    "offered canonical data lost its independent recent, expired, or unknown origins"
  check (plan.observations.all (fun item => item.age.receivedUnixMs ==
    (originalTimes.find? (·.occurrence == item.occurrence)).bind (·.receivedUnixMs)))
    "delivery annotated a different origin or fabricated an acquisition date"
  IO.FS.writeFile (root / "recommendation-before-delivery.json") (plan.receipt "").pretty
  check (plan.complete && offers.any (·.kind == "consumption") && offers.any (·.kind == "coquotation") &&
      (plan.outputRanges.flatMap (·.2)).all (fun range => range.limit-range.first < 5000))
    "automatically rebuilt native relations did not reach fragment-only recommendation"
  let families := plan.outputRanges.filterMap fun (owner,ranges) => do
    if ranges.isEmpty then none else do
      let original ← owners.find? (·.original.relation == owner)
      some ({
        owner := original.original
        template := {owner := some owner,keys := [],text := "",members := [],visibleKeys := []}
        windows := [],outputRanges := ranges} : SharedRangeAdapter.Family)
  let packet := fun (slices : List TransportSlice) => "EGGSHELL\n" ++ "\n".intercalate (slices.map (·.text)) ++ "\nEND EGGSHELL"
  let cost := fun slices => ((packet slices).length,(packet slices).utf8ByteSize)
  let some selected := SharedRangeAdapter.fit (120000,480000) cost families [] (Synapses.Bundles.project plan) |
    throw (IO.userError "automatic native graph failed the production selector")
  let body := packet selected.val
  let shown := presented body plan.documents plan.rows
  check ((offers.filterMap (·.target.source?)).all (fun source => covered source shown.ranges) &&
      !(body.splitOn "READY_17").tail.isEmpty && !(body.splitOn "SUCCESS_23").tail.isEmpty &&
      (body.splitOn "detail").length == 1 && (body.splitOn "SECOND_02").length == 1)
    "actual original-byte delivery omitted recommended evidence or included unrelated fields"
  IO.FS.writeFile (root / "delivery.txt") body
  IO.FS.writeFile (root / "receipt.json") (plan.receipt body).pretty
  IO.FS.writeFile (root / "rebuild.json") (Json.mkObj [
    ("first",toJson first),("incremental",toJson updated),("copied",toJson rebuilt),("private",toJson privateBuild),
    ("consumption",toJson edges),("supports",toJson supports),("recommendation",plan.receipt body)]).pretty
  IO.println s!"automatic native rebuild passed: {edges.size} consumption edges, {supports.size} quote supports, canonical origins, incremental and DB-only equality, fragment recommendation"

def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "SynapseNativeRebuildTests NEW-DIRECTORY")
  let root := System.FilePath.mk path
  check (root.isAbsolute && !(← root.pathExists)) "new absolute test directory required"
  IO.FS.createDirAll root
  quoteChecks
  scenario root
