import Main
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.LiteralRankChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def audit (sourceDirectory root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier rank audit"
  IO.FS.createDirAll root
  let project ← ProjectStore.openProject (sourceDirectory/"work.project")
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let expected := (← read (sourceDirectory/"frozen-readback.json")).getObjValD "sourceHeads"
  check (toJson (view.sources.map (·.head)) == expected) "rank audit source differs from the frozen cut"
  let some reference ← OwnerViews.load? view.sources | throw (IO.userError "rank audit needs prepared owner inputs")
  let owners ← OwnerViews.restore reference view.sources
  let (_,population) ← owners.counts
  let inputs ← view.sources.mapM fun source => do
    let some input ← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract |
      throw (IO.userError "rank audit input is not prepared")
    return input
  let queries ← (List.finRange view.sources.size).mapM fun source => do
    return (source,← capturedLexicalQuery view.sources[source] (some inputs) none)
  let readers ← Persistence.Store.NodeReaders.new view.sources
  let mut reports := #[]
  for (arm,question) in [("period","Return the recorded head and tail facts for support case-79."),
      ("no-period","Return the recorded head and tail facts for support case-79"),
      ("identifier","case-79"),("uri","mcp://support/case-79")] do
    let wanted := SearchRank.terms question
    let mut postings : Std.HashMap String (Std.HashSet Nat) := {}
    let mut frequencies : Std.HashMap String Nat := {}
    let mut matched : Std.HashSet Nat := {}
    for unit in wanted do
      let mut found : Std.HashSet Nat := {}
      for (source,query) in queries do
        let (ids,_) ← query.posting unit
        for id in ids do found := found.insert (← OwnerViews.canonical owners source.val id)
      postings := postings.insert unit found
      frequencies := frequencies.insert unit found.size
      for id in found.toList do matched := matched.insert id
    let ordered ← matched.toList.mapM fun id => do pure (← OwnerViews.ordinal owners id,id)
    let durable := (ordered.mergeSort (fun a b => a.1 ≤ b.1)).map Prod.snd
    let contains := fun id unit => (postings.getD unit {}).contains id
    let ranking := SearchRank.rankRows question durable contains (frequencies.getD · 0) false population
    let named := wanted.filter fun unit =>
      ((unit.toList.reverse.dropWhile (fun c => c == '.' || c == ':')).reverse).any fun c =>
        "_/:.".contains c || SearchUnicode.isDigit c
    let namedRow := fun index => (durable[index]?).any fun id => named.any (contains id)
    -- Counterfactual only: no product ranker is changed by this audit.
    let namedFirst := ranking.filter namedRow ++ ranking.filter (fun index => !namedRow index)
    let mut rows := #[]
    for (index,position) in ranking.zipIdx do
      let some id := durable[index]? | throw (IO.userError "rank audit row disappeared")
      let entry ← OwnerViews.entry owners id
      let some original := entry.originals.head? | throw (IO.userError "rank audit owner lost its original")
      let some source := (List.finRange view.sources.size).find? (·.val == original.source) |
        throw (IO.userError "rank audit source missing")
      let reader := readers.at source
      let outcome ← reader.outcome (← reader.locateOutcome original.node)
      let text := Persistence.Store.searchText outcome
      let terms := wanted.filter (contains id)
      let score := terms.foldl (fun sum unit => sum+RetrievalResearch.log1p
        (population.toFloat/(frequencies.getD unit 0).toFloat)) (0 : Float)
      let target := text.contains "observed-head-case-79-7b319c" && text.contains "observed-tail-case-79-d82a04"
      rows := rows.push (Json.mkObj [("id",toJson id),("rank",toJson position),
        ("namedFirstRank",toJson (namedFirst.zipIdx.find? (·.1 == index) |>.map (·.2))),
        ("targetOriginal",toJson target),("score",toJson score),("matched",toJson terms),
        ("matchedNamed",toJson (named.filter (contains id))),
        ("workPrefix",toJson ((Persistence.Store.text? outcome.work).getD "" |>.take 180 |>.toString))])
    let report := Json.mkObj [("arm",toJson arm),("population",toJson population),
      ("wanted",toJson wanted),("namedTerms",toJson named),("frequencies",toJson frequencies.toList),
      ("rows",toJson rows),("productChanged",toJson false)]
    IO.FS.writeFile (root/(arm++".json")) (report.compress++"\n")
    reports := reports.push (Json.mkObj [("arm",toJson arm),("population",toJson population),
      ("matchedOwners",toJson rows.size),("targets",toJson (rows.filter fun row => row.getObjValD "targetOriginal" == toJson true))])
  for source in view.sources do
    check ((← DB.PageMap.pin source.directory).head == source.head) "rank audit changed an original head"
  IO.FS.writeFile (root/"report.json") ((Json.mkObj [("queries",toJson reports),
    ("allOriginalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress++"\n")
  IO.println (toJson reports).compress
end Eggshell.Research.LiteralRankChecks
