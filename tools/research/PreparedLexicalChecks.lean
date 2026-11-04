import Main
open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.PreparedLexicalChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path (value.compress++"\n")
abbrev Lookup := String → IO (List Nat × Nat)
def prepared (reader : SourceOwners.Reader) (unit : String) : IO (List Nat × Nat) := do
  let some root ← reader.postingRoot unit true | return ([],0)
  return (← reader.bitmap.members root.height root,root.count)
def sameNominations (left right : IndexedSemanticNominations) : Bool :=
  left.durable == right.durable && left.staged == right.staged &&
  left.durableRanking == right.durableRanking && left.stagedRanking == right.stagedRanking &&
  left.durableWindows == right.durableWindows && left.stagedWindows == right.stagedWindows &&
  left.presentationOrder == right.presentationOrder && left.focused == right.focused
def run (sourceDirectory root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier prepared lexical audit"
  IO.FS.createDirAll root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identity.exitCode == 0) "missing audit runtime identity"
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let project ← ProjectStore.openProject (sourceDirectory/"work.project")
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let expected := (← read (sourceDirectory/"frozen-readback.json")).getObjValD "sourceHeads"
  check (toJson (view.sources.map (·.head)) == expected) "audit source changed its frozen cut"
  let some reference ← OwnerViews.load? view.sources | throw (IO.userError "complete prepared owners are missing")
  check (OwnerViews.common reference) "audit requires one project dictionary"
  let owners ← OwnerViews.restore reference view.sources
  let (_,population) ← owners.counts
  let dictionaryBefore := (← PageMap.pin owners.base.dictionary.directory).head
  let inputs ← view.sources.mapM fun source => do
    let some input ← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "captured prepared input missing")
    return input
  let queries ← (List.finRange view.sources.size).mapM fun source => do
    return (source,← capturedLexicalQuery view.sources[source] (some inputs) none)
  let legacy : Lookup := fun unit => do
    let mut result : Std.HashSet Nat := {}
    for (source,query) in queries do
      let (ids,_) ← query.posting unit
      for id in ids do result := result.insert (← OwnerViews.canonical owners source.val id)
    return (result.toList,result.size)
  let modern : Lookup := prepared owners.base
  let mut terms : Std.HashSet String := {}
  for source in view.sources do
    let some lexical ← RetrievalResearch.Index.open? source | throw (IO.userError "lexical reverse terms missing")
    let count ← getNat lexical.index.get "terms"
    for id in [:count] do terms := terms.insert (← readTerm lexical.index lexical.index.get id)
  let began ← IO.monoMsNow
  let mut positives := 0
  let mut postingMembers := 0
  let mut rows := #[]
  for unit in terms.toList++["PNOT_IN_ANY_PREPARED_LEXICON_8137"] do
    let before ← legacy unit
    let after ← modern unit
    check (Std.HashSet.ofList before.1 == Std.HashSet.ofList after.1 &&
      before.2 == after.2 && after.1.length == after.2) "prepared postings or exact global frequency differ"
    if before.2>0 then positives := positives+1
    postingMembers := postingMembers+before.2
    rows := rows.push (unit,before.2)
  save (root/"postings.json") (toJson rows)
  let postingAuditMs := (← IO.monoMsNow)-began
  let questions := ["Return the recorded head and tail facts for support case-79.",
    "Return the recorded head and tail facts for support case-79","case-79","mcp://support/case-79",
    "警告 support case-0","커널 case-42","support case-18 head tail","NO_RECORD_FOR_THIS_8137"]
  let mut ranking := #[]
  for question in questions do
    let before ← lexicalNominations population legacy (OwnerViews.ordinal owners) question []
    let after ← lexicalNominations population modern (OwnerViews.ordinal owners) question []
    check (sameNominations before after) "complete lexical nomination/ranking/window observation differs"
    ranking := ranking.push (Json.mkObj [("question",toJson question),("nominated",toJson before.durable),
      ("allRanked",toJson before.durableRanking),("identical",toJson true)])
  save (root/"ranking.json") (toJson ranking)
  let mut timings := #[]
  for repetition in [:5] do
    for route in (if repetition%2 == 0 then ["source","prepared"] else ["prepared","source"]) do
      let lookup := if route == "source" then legacy else modern
      let began ← IO.monoNanosNow
      let result ← lexicalNominations population lookup (OwnerViews.ordinal owners) questions.head! []
      let elapsed := ((← IO.monoNanosNow)-began)/1000
      timings := timings.push (Json.mkObj [("repetition",toJson repetition),("route",toJson route),
        ("elapsedUs",toJson elapsed),("allRanked",toJson result.durableRanking),
        ("nominated",toJson result.durable)])
      save (root/"timings.json") (toJson timings)
  for source in view.sources do
    check ((← PageMap.pin source.directory).head == source.head) "lexical audit changed original head"
  check ((← PageMap.pin owners.base.dictionary.directory).head == dictionaryBefore) "lexical audit published derived rows"
  let report := Json.mkObj [("allPassed",toJson true),("owners",toJson view.sources.size),("population",toJson population),
    ("terms",toJson (terms.size+1)),("positiveTerms",toJson positives),("postingMembers",toJson postingMembers),
    ("postingAuditMs",toJson postingAuditMs),("questions",toJson questions.length),("pairedRepetitions",toJson (5 : Nat)),
    ("allOriginalHeadsUnchanged",toJson true),("dictionaryUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  save (root/"report.json") report
  IO.println report.compress
end Eggshell.Research.PreparedLexicalChecks
