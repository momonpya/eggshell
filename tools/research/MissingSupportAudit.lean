import tools.research.AvailableDelivery
import Eggshell.SynapseBuild
import Eggshell.UsageCache
open Lean Eggshell Eggshell.Synapses Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def overlaps (unit : AvailableDelivery.Unit) (source : Range) : Bool :=
  unit.alternatives.any (fun parts => parts.any (fun wanted => (wanted.intersection? source).isSome))

private def fullyCovered (unit : AvailableDelivery.Unit) (sources : Array Range) : Bool :=
  unit.alternatives.any (fun parts => parts.all (fun wanted => covered wanted sources))

def main (args : List String) : IO Unit := do
  let [trialPath,destination] := args | throw (IO.userError "completed readonly trial and fresh diagnostic required")
  let trial := System.FilePath.mk trialPath
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve support audit"
  let source ← DB.PageMap.pin (trial / "work.egg")
  let some index ← Index.openShared? source | throw (IO.userError "completed source lost its prepared shared index")
  let facts ← Index.allFacts index.index
  let usage ← (← UsageCache.open? source).bindM fun ready => some <$> Index.allFacts ready.index
  let frozen ← IO.ofExcept ((← read (trial / "frozen-before-delivery.json")).getArr?)
  let mut rows := #[]
  for entry in frozen do
    let topic ← IO.ofExcept (entry.getObjValAs? Nat "topic")
    let available : AvailableDelivery.Frozen ← IO.ofExcept (entry.getObjValAs? _ "available")
    let audit ← read (trial / "candidate" / s!"topic-{topic}/audit.json")
    let delivery : AvailableDelivery.Result ← IO.ofExcept (audit.getObjValAs? _ "availableDelivery")
    let body ← IO.FS.readFile (trial / "candidate" / s!"topic-{topic}/body.txt")
    for unit in available.units do
      let reads := facts.filterMap fun fact => match fact with
        | .read value => if overlaps unit value.source then some value else none
        | _ => none
      let supports := facts.filterMap fun fact => match fact with
        | .supports value => if overlaps unit value.source then some value else none
        | _ => none
      let coquoted := facts.filterMap fun fact => match fact with
        | .coquoted group value => if overlaps unit value then some (group,value) else none
        | _ => none
      let consumed := facts.filterMap fun fact => match fact with
        | .consumed value => if value.rows.any (overlaps unit) then some value else none
        | _ => none
      let used := (usage.getD #[]).filterMap fun fact => match fact with
        | .used value => if overlaps unit value.source then some value else none
        | _ => none
      let matchedAnswers := supports.map (fun support => (support.claim.answer,
        decide ((body.splitOn ("WORK GRAPH " ++ support.claim.answer ++ "\n")).length > 1)))
        |>.toList.eraseDups.toArray
      rows := rows.push (Json.mkObj [("topic",toJson topic),("names",toJson unit.names),
        ("missing",toJson (delivery.missing.contains unit.names)),("partial",toJson unit.partialNames),
        ("readCount",toJson reads.size),("readsCoverWholeObligation",toJson (fullyCovered unit (reads.map (·.source)))),
        ("supportCount",toJson supports.size),("supportsCoverWholeObligation",toJson (fullyCovered unit (supports.map (·.source)))),
        ("coquotedCount",toJson coquoted.size),("consumedCount",toJson consumed.size),("usedCount",toJson used.size),
        ("supportAnswersInActualBody",toJson matchedAnswers),("reads",toJson reads),("supports",toJson supports),
        ("coquoted",toJson coquoted),("consumed",toJson consumed),("used",toJson used)])
  check ((← DB.PageMap.pin source.directory).head == source.head) "support diagnostic changed source"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("sharedIndex",toJson index.index.head),
    ("sharedFacts",toJson facts.size),("usageFacts",toJson (usage.map Array.size)),("rows",Json.arr rows),
    ("wholeIndexOfflineScan",toJson true),("sourceUnchanged",toJson true),("selectorChanges",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Audited frozen obligations against stored read/support/coquotation/consumption/usage facts"
