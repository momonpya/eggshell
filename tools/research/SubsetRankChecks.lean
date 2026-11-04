import Main
import Eggshell.SubsetLexical
open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.SubsetRankChecks
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path (value.compress++"\n")

abbrev point := SubsetLexical.point
abbrev projected := SubsetLexical.rank
abbrev project := SubsetLexical.project

def sparsePointAudit (root : System.FilePath) : IO Json := do
  let path := root/"point-probe.egg"
  let empty ← PageMap.create path "subset-lexical-readonly-point-probe"
  let ids := [0,255,256,4095,4096,65535,65536,1000000,1000000000000]
  let (target,head,_) ← PageMap.withWriter empty fun writer => do
    let mut target := none
    for id in ids do target ← SourceBitmap.set writer target id true
    return target
  let snapshot ← PageMap.pin path
  check (snapshot.head == head) "point fixture publication lost its head"
  let reader ← SourceBitmap.Reader.new snapshot
  let some target := target | throw (IO.userError "sparse point fixture is empty")
  let all ← reader.members target.height target
  check (all == ids) "sparse reference enumeration differs"
  let probes := ids++[1,254,257,4097,65537,999999,1000001,999999999999,1000000000001,
    256*16^target.height,256*16^target.height+255]
  for id in probes do
    check ((← point reader target.height target id) == all.contains id)
      "sparse point traversal differs from independent full enumeration"
  return Json.mkObj [("height",toJson target.height),("positive",toJson ids.length),("probes",toJson probes.length)]

def run (sourceDirectory root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous subset rank trial"
  IO.FS.createDirAll root
  let sparse ← sparsePointAudit root
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
  check (identity.exitCode == 0) "missing runtime identity"
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let projectDb ← ProjectStore.openProject (sourceDirectory/"work.project")
  let view ← ProjectStore.pin projectDb ((← IO.monoMsNow)+30000)
  let expected := (← read (sourceDirectory/"frozen-readback.json")).getObjValD "sourceHeads"
  check (toJson (view.sources.map (·.head)) == expected) "source cut changed"
  let some reference ← OwnerViews.load? view.sources | throw (IO.userError "missing prepared owner inputs")
  let ownerView ← OwnerViews.restore reference view.sources
  let reader := ownerView.base
  let dictionaryBefore := (← PageMap.pin reader.dictionary.directory).head
  let some candidates := reader.candidates | throw (IO.userError "nonempty fixture lacks candidates")
  let candidates ← reader.bitmap.members candidates.height candidates
  let ordered ← candidates.mapM fun id => do return (← OwnerViews.ordinal ownerView id,id)
  let ids := (ordered.mergeSort (fun a b => a.1 ≤ b.1)).map Prod.snd
  let originals ← NodeReaders.new view.sources
  let mut texts : Std.HashMap Nat String := {}
  for id in ids do
    let entry ← OwnerViews.entry ownerView id
    let some original := entry.originals.head? | throw (IO.userError "candidate lost captured original")
    if bounded : original.source < view.sources.size then
      let source := view.sources[original.source]
      let outcome ← (originals.at ⟨original.source,bounded⟩).outcome (← locateOutcome source original.node)
      check ((Matcher.atomText? outcome.work).isSome) "lexical candidate has nontext Work"
      texts := texts.insert id (searchText outcome)
    else throw (IO.userError "candidate original crossed source inventory")
  let documents := ids.map (texts.getD · "")
  check (ids.length == 163 && documents.all (!·.isEmpty)) "fixture population changed"
  let subsets := [("empty",[]),("singleton",ids.take 1),("eight",ids.take 8),
    ("half",ids.take (ids.length/2)),("full",ids),("reverse",ids.reverse),("duplicates",ids.take 8++ids.take 8)]
  let questions := ["Return the recorded head and tail facts for support case-79.",
    "Return the recorded head and tail facts for support case-79","case-79","mcp://support/case-79",
    "警告 support case-0","커널 case-42","support case-18 head tail","NO_RECORD_FOR_THIS_8137"]
  let mut checks := #[]
  let mut memberships := 0
  for question in questions do
    let complete ← project reader question ids
    for term in SearchRank.terms question do
      let root ← reader.postingRoot term true
      let all ← match root with
        | none => pure []
        | some root => reader.bitmap.members root.height root
      for id in ids++[0,255,256,65536,1000000000000] do
        let actual ← match root with
          | none => pure false
          | some root => point reader.bitmap root.height root id
        check (actual == all.contains id) "point lookup differs from complete bitmap enumeration"
        memberships := memberships+1
      for id in ids do
        check ((complete.getD term {}).contains id == (SearchRank.terms (texts.getD id "")).contains term)
          "published membership differs from original tokenization"
    for (name,selected) in subsets do
      let table ← project reader question selected
      let before := SearchRank.lexical question (selected.map (texts.getD · ""))
      let after := projected question selected (fun id term => (table.getD term {}).contains id)
      check (before == after) "subset IDF, stable order or complete ranking changed"
      check ((← SubsetLexical.read? reader question selected) == some before) "actual prepared reader changed local ranking"
      checks := checks.push (Json.mkObj [("question",toJson question),("subset",toJson name),
        ("rows",toJson selected.length),("ranking",toJson before),("identical",toJson true)])
  save (root/"checks.json") (toJson checks)
  let mut timings := #[]
  for repetition in [:5] do
    for route in (if repetition%2 == 0 then ["parse","prepared"] else ["prepared","parse"]) do
      let began ← IO.monoNanosNow
      let ranked ← if route == "parse" then pure (SearchRank.lexical questions.head! documents)
        else do
          let some ranked ← SubsetLexical.read? reader questions.head! ids | throw (IO.userError "actual reader refused frozen candidates")
          pure ranked
      let ranked ← (← IO.mkRef ranked).get
      let elapsed := ((← IO.monoNanosNow)-began)/1000
      timings := timings.push (Json.mkObj [("repetition",toJson repetition),("route",toJson route),
        ("elapsedUs",toJson elapsed),("ranking",toJson ranked)])
      save (root/"timings.json") (toJson timings)
  for source in view.sources do check ((← PageMap.pin source.directory).head == source.head) "query changed original source"
  check ((← PageMap.pin reader.dictionary.directory).head == dictionaryBefore) "query changed prepared dictionary"
  check ((← SubsetLexical.read? reader questions.head! [1000000000000]).isNone)
    "foreign owner became an empty completed local rank"
  let report := Json.mkObj [("allPassed",toJson true),("owners",toJson view.sources.size),
    ("documents",toJson ids.length),("characters",toJson (documents.foldl (fun n text => n+text.length) 0)),
    ("questions",toJson questions.length),("subsets",toJson subsets.length),("rankChecks",toJson checks.size),
    ("pointChecks",toJson memberships),("sparse",sparse),("foreignOwnerDeclines",toJson true),
    ("originalHeadsUnchanged",toJson true),("dictionaryUnchanged",toJson true),
    ("productChanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  save (root/"report.json") report
  IO.println report.compress
end Eggshell.Research.SubsetRankChecks
