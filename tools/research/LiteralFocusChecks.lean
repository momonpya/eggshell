module
public import Eggshell.CanonicalSourceCache
public import tools.research.PreparedLiteralFocus
@[expose] public section
namespace Eggshell.Research.LiteralFocusChecks
open Lean Synapses
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"

/-- Independent literal old loop; no candidate rewrite can optimize this arm. -/
@[noinline,nospecialize] def reference (question : String) (documents : List String)
    (ranked : List Nat) : QueryLiterals.Focus :=
  let literals := QueryLiterals.query question
  let words := if literals.isEmpty then [] else documents.map QueryLiterals.identifiers
  let channels := literals.map fun literal =>
    let matching := (words.zipIdx.filter fun (names,_) => names.any fun identifier =>
      literal.length < identifier.length && QueryLiterals.suffix literal identifier).map Prod.snd
    (ranked.filter matching.contains ++ matching.filter (fun index => !ranked.contains index)).toArray
  let hints := (List.range documents.length).flatMap fun rank => channels.filterMap (·[rank]?)
  let selected := SearchRank.select documents.length ranked.length [] (hints ++ ranked)
  {windows := selected,anchors := selected.filter hints.contains}
theorem reference_exact (question : String) (documents : List String) (ranked : List Nat) :
    reference question documents ranked = QueryLiterals.focus question documents ranked := rfl
#print axioms reference_exact
#print axioms PreparedLiteralFocus.Ready.focus_exact

structure Sample where
  owner : String
  documents : List String
  prepared : PreparedLiteralFocus.Ready documents

def selected (fast : Bool) (samples : Array Sample) (question : String) (ranked : Bool) : Array (List Nat × List Nat) :=
  samples.map fun sample =>
    let order := (List.range sample.documents.length).reverse.take (if ranked then 16 else 0)
    let result := if fast then sample.prepared.focus question order else reference question sample.documents order
    (result.windows,result.anchors)

def timed (input : IO.Ref (Array Sample × String)) (fast : Bool) : IO (Array (List Nat × List Nat) × Nat) := do
  let started ← IO.monoMsNow
  let (samples,question) ← input.get
  let result ← (← IO.mkRef (selected fast samples question true)).get
  let finished ← IO.monoMsNow
  return (result,finished-started)

def run (destination : System.FilePath) : IO Unit := do
  check (!(← destination.pathExists)) "preserve previous literal-focus observation"
  let documents := [[],[""],["OPT_x x -x __foo_bar foo_bar"],
    ["--foo-bar", "OPT_FooBar", "ロシア Россия café 커널 Ｆｏｏ", "x"],
    ["OPT_x", "OPT_x", "F_x", "nested_json_key"]]
  let questions := ["", "plain prose", "-x", "--foo-bar", "x -42 --- -", "-x -x --bar -Ｆｏｏ"]
  let mut controls := 0
  for rows in documents do
    let ready := PreparedLiteralFocus.prepare rows
    for question in questions do
      for order in [[],[0],[99,0,1,0],(List.range rows.length).reverse] do
        let before := reference question rows order
        let after := ready.focus question order
        check (before.windows == after.windows && before.anchors == after.anchors) "literal-focus boundary changed"
        controls := controls+1
  let sourcePath := base/"real-source-search-read-trial-result/work.egg"
  let source ← DB.PageMap.pin sourcePath
  let locate (storage : DB.Sidecar.Storage) : IO (Option DB.PageMap.Snapshot) := do
    if let some ready ← CanonicalSource.Cache.open? source storage then
      let directory ← CanonicalSource.Cache.directory source storage
      return ← CanonicalSource.Cache.preparedAt? source directory ready.metadata
    return none
  let prepared ← locate .database
  let prepared ← if prepared.isSome then pure prepared else locate .user
  let some index := prepared | throw (IO.userError "frozen original view unavailable")
  let reader ← Persistence.Store.NodeReader.new source
  let raw ← index.foldRange ⟨"view-document:","view-document;"⟩ (fun rows row => do
    let some id := (row.1.drop "view-document:".length).toString.toNat? | return rows
    let document ← Build.document reader id
    let state ← index.readPayload (CanonicalSource.Cache.stateName id) >>= CanonicalSource.Cache.decode (α := CanonicalSource.Cache.OwnerState)
    check (document.owner == state.owner) "original owner directory changed"
    let windows := PreparedFocusFacts.evidence (document.workText.getD "") (document.source.getD "")
    return rows.push (document.owner,windows)) (#[] : Array (String × List String))
  check (raw.size == 40) "all forty original owners required"
  let input ← IO.mkRef raw
  let began ← IO.monoMsNow
  let rows ← input.get
  let samples ← (← IO.mkRef (rows.map fun (owner,documents) =>
    ({owner,documents,prepared := PreparedLiteralFocus.prepare documents} : Sample))).get
  let preparedMs := (← IO.monoMsNow)-began
  let specification ← IO.ofExcept (Json.parse (← IO.FS.readFile (base/"real-source-search-read-input.json")))
  let topics ← IO.ofExcept (specification.getObjValAs? (Array Json) "topics")
  check (topics.size == 3) "all frozen questions required"
  let mut results := #[]
  for topic in topics do
    let artifact := topic.getObjValD "prompt"
    let question ← IO.FS.readFile (.mk (← IO.ofExcept (artifact.getObjValAs? String "path")))
    check (artifact.getObjValD "sha256" == toJson (Sha256.hex question.toUTF8)) "frozen question changed"
    check (selected false samples question false == selected true samples question false) "empty input rank changed"
    let input ← IO.mkRef (samples,question)
    let mut pairs := #[]
    for pair in [:3] do
      let candidateFirst := pair == 1
      let first ← timed input candidateFirst
      let second ← timed input (!candidateFirst)
      check (first.1 == second.1) "complete original windows or anchors changed"
      let (before,after) := if candidateFirst then (second.2,first.2) else (first.2,second.2)
      pairs := pairs.push (Json.mkObj [("candidateFirst",toJson candidateFirst),("referenceMs",toJson before),
        ("candidateMs",toJson after),("allWindowsAndAnchorsExact",toJson true)])
    results := results.push (Json.mkObj [("topic",topic.getObjValD "topic"),("queryLiterals",toJson (QueryLiterals.query question)),
      ("questionSha256",artifact.getObjValD "sha256"),("pairs",toJson pairs)])
  let after ← DB.PageMap.pin sourcePath
  check (source.head == after.head) "original publication changed"
  IO.FS.writeFile destination (Json.mkObj [("controls",toJson controls),("owners",toJson samples.size),
    ("windows",toJson (raw.foldl (fun count row => count+row.2.length) (0 : Nat))),
    ("preparedMs",toJson preparedMs),("results",toJson results),("source",toJson source.head),
    ("originalHeadUnchanged",toJson true),("actualHooks",toJson (0 : Nat)),("newEightyLoadRuns",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end Eggshell.Research.LiteralFocusChecks
def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "literal focus result required")
  Eggshell.Research.LiteralFocusChecks.run (.mk destination)
