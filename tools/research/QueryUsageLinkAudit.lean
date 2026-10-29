module
import all Eggshell.SynapseBuild
import all Eggshell.SynapticTransport
import all Eggshell.SynapseJournal
public meta import Lean
open Lean Eggshell Eggshell.Synapses

#print axioms QueryLinks.Original.exact_question
#print axioms QueryLinks.Original.same_owner

run_meta do
  let environment ← getEnv
  let mut pending := [``QueryLinks.roots]
  let mut seen : Std.HashSet Name := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    let some declaration := environment.find? name | throwError "missing query-root boundary {name}"
    if let some body := declaration.value? then
      for dependency in body.getUsedConstants do
        if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
  for forbidden in #[``DB.PageMap.withWriter,``Matcher.localUnion?,``Build.document,``Journal.append] do
    if seen.contains forbidden then throwError "query root lookup reaches {forbidden}"
  logInfo "Question roots read prepared metadata without original hydration, writes or Union"

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

public def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "new isolated output required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists) && (← Paths.dataRoot) == output / "private") "isolated fresh query-link root required"
  IO.FS.createDir output
  let source ← DB.PageMap.create (output / "fixture.egg") "question-link-fixture"
  let key := fun text => Persistence.selectionKey (.text text)
  let oldPrompt := "Earlier work which actually used both source ranges."
  let newPrompt := "A different follow-up question."
  let doc : Extraction.Document := {
    owner := key "old-answer",work := key oldPrompt,workText := some oldPrompt,
    source := some "Earlier answer",native := false,occurrences := #[],files := #[]}
  let some original := QueryLinks.original? doc | throw (IO.userError "original question was not recognized")
  check ((original.link source.head.identity 7).query == Sha256.hex oldPrompt.toUTF8)
    "question key differs from the exact saved Work"
  check (QueryLinks.original? {doc with native := true}).isNone "a native invocation became an original question"
  check (QueryLinks.original? {doc with workText := none}).isNone "missing Work text fabricated a question"
  let file : File := ⟨"source.txt",String.ofList (List.replicate 64 'a'),100⟩
  let first : Range := ⟨file,10,10⟩
  let second : Range := ⟨file,20,20⟩
  let group := Group.answer source.head.identity doc.owner
  let sharedFacts := #[Fact.coquoted group first,Fact.coquoted group second]
  let _ ← Index.replace source .database .shared sharedFacts
  let some before ← Index.openShared? source | throw (IO.userError "fixture source view missing")
  let oldQuery := Sha256.hex oldPrompt.toUTF8
  let currentQuery := Sha256.hex newPrompt.toUTF8
  let usage : Usage := {
    event := {occurrence := ⟨"prior-session","prior-turn","read"⟩,ordinal := 0}
    query := oldQuery,source := first,kind := .omittedThenRead}
  let _ ← UsageCache.publish source {
    session := "prior-session",turn := "prior-turn",source := source.head,
    view := String.ofList (List.replicate 64 'b'),count := 1} #[.used usage]
  let some privateView ← UsageCache.open? source | throw (IO.userError "private usage view missing")
  let preparedBefore : Recommend.Prepared := {source,shared := some before,usage := some privateView}
  let omitted ← Routed.collect preparedBefore #[(doc.owner,7)] currentQuery ((← IO.monoMsNow)+5000) #[]
  check (omitted.complete && omitted.hints.isEmpty) "different question already had a private root before the link"
  let _ ← Index.publishDelta source .database .shared (some source.head) {}
    (fun writer => QueryLinks.stage writer source.head.identity 7 doc)
  let some shared ← Index.openShared? source | throw (IO.userError "question link publication missing")
  let linked ← QueryLinks.roots shared #[(doc.owner,7)]
  check (linked == #[(Index.Key.query oldQuery,7)]) "saved question did not inherit the nominated owner's priority"
  let some bytes ← shared.index.get (QueryLinks.ownerName doc.owner) |
    throw (IO.userError "question link not persisted")
  check (((String.fromUTF8! bytes).splitOn oldPrompt).length == 1) "shared query link contains plaintext question text"
  let prepared : Recommend.Prepared := {source,shared := some shared,usage := some privateView}
  let routed ← Routed.collect prepared #[(doc.owner,7)] currentQuery ((← IO.monoMsNow)+5000) #[]
  let oracle ← Recommend.collect shared (some privateView) #[(doc.owner,7)] #[] currentQuery ((← IO.monoMsNow)+5000)
  check (routed.complete && oracle.complete && routed.hints.size == oracle.offers.size && routed.hints.size == 3)
    "private omission did not reach the shared coquotation relation"
  for (hint,offer) in routed.hints.zip oracle.offers do
    check (hint.target == offer.target && hint.priority == offer.priority && hint.evidence == offer.identity &&
      Routing.Store.kindName hint.kind == offer.kind)
      "routed query link differs from the full fact reader"
  check (routed.hints.all (·.priority == 7) && routed.hints.any (·.target == .range first) &&
    routed.hints.any (·.target == .range second)) "new question lost the prior range or its linked partner"
  let withoutPrivate ← Routed.collect {prepared with usage := none} #[(doc.owner,7)] currentQuery ((← IO.monoMsNow)+5000) #[]
  check (withoutPrivate.complete && withoutPrivate.hints.isEmpty) "private feedback escaped its reader scope"
  let _ ← Index.publishDelta source .database .shared (some source.head) {}
    (fun writer => QueryLinks.erase writer 7)
  let some retired ← Index.openShared? source | throw (IO.userError "retired source view missing")
  check ((← QueryLinks.roots retired #[(doc.owner,7)]).isEmpty &&
    (← QueryLinks.roots shared #[(doc.owner,7)]) == linked &&
    (← QueryLinks.roots before #[(doc.owner,7)]).isEmpty) "question retirement changed another pinned reader"
  let foreign ← DB.PageMap.create (output / "foreign.egg") "foreign-question-link"
  let _ ← Index.replace foreign .database .shared #[] (fun writer => QueryLinks.stage writer source.head.identity 7 doc)
  let some foreignView ← Index.openShared? foreign | throw (IO.userError "foreign fixture missing")
  let rejected ← try
      let _ ← QueryLinks.roots foreignView #[(doc.owner,7)]
      pure false
    catch _ => pure true
  check rejected "foreign DB question metadata was accepted"
  check ((← DB.PageMap.pin source.directory).head == source.head) "advisory link publication changed the primary source"
  let result := Json.mkObj [("differentQuestionReached",toJson true),("originalQuestionExact",toJson true),
    ("priorityInherited",toJson true),("routedEqualsFullReader",toJson true),("privateToSharedHop",toJson true),
    ("offeredRanges",toJson routed.hints.size),("noPrivateNoFeedback",toJson true),
    ("retirementAndOldPins",toJson true),("foreignDatabaseRejected",toJson true),
    ("noPlaintextQuestionCopied",toJson true),("primarySourceUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") result.pretty
  IO.println result.compress
