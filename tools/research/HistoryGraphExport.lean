import Eggshell.Handoff

open Lean Eggshell Eggshell.Synapses
namespace HistoryGraphExport
def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def read (path : String) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)

/-- Offline, read-only export of the already published advisory graph. The
query navigator follows these edges; it does not rediscover tool dependencies. -/
def position (offsets : Array Nat) (raw : Nat) : Nat := Id.run do
  let mut first := 0
  let mut stop := offsets.size-1
  while first < stop do
    let middle := (first+stop)/2
    if offsets[middle]! < raw then first := middle+1 else stop := middle
  return first

def run (originals database indexPath usagePath output : String) : IO Unit := do
  check (!(← (System.FilePath.mk output).pathExists)) "preserve previous graph input"
  let exported ← read originals
  let source ← DB.PageMap.pin database
  check (toJson source.head == exported.getObjValD "head") "originals and source snapshot differ"
  let index ← DB.PageMap.pin indexPath
  let some checked ← Index.atSource? source index .shared | throw (IO.userError "advisory index is not checked at the original snapshot")
  let sharedFacts ← Index.allFacts checked.index
  check (sharedFacts.size == checked.manifest.facts) "published advisory fact population differs"
  let privateIndex ← DB.PageMap.pin usagePath
  let some privateChecked ← Index.atSource? source privateIndex .usage |
    throw (IO.userError "private usage index is not checked at the same project")
  let privateFacts ← Index.allFacts privateChecked.index
  check (privateFacts.size == privateChecked.manifest.facts) "private usage fact population differs"
  let facts := sharedFacts++privateFacts
  let graph ← IO.ofExcept (Graph.ofFacts facts)
  let documents ← IO.ofExcept (exported.getObjValAs? (Array Json) "documents")
  let mut owners : Std.HashMap String Nat := {}
  let mut occurrences : Std.HashMap Occurrence Nat := {}
  let mut offsets : Array (Array Nat) := #[]
  for id in [:documents.size] do
    let document := documents[id]!
    owners := owners.insert (← IO.ofExcept (document.getObjValAs? String "owner")) id
    offsets := offsets.push (Extraction.layoutView (← IO.ofExcept (document.getObjValAs? String "source"))).offsets
    for occurrence in ← IO.ofExcept (document.getObjValAs? (Array Occurrence) "occurrences") do
      occurrences := occurrences.insert occurrence id
  let mut edges : Std.HashMap Nat (Std.HashSet String) := {}
  let addEdge (current : Std.HashMap Nat (Std.HashSet String)) (fromId toId : Nat)
      (kind : String) (fact : Json) :=
    let binding := fact.getObjValD "binding"
    let rawFirst := ((binding.getObjValAs? Nat "first").toOption).getD
      ((fact.getObjValAs? Nat "outputFirst").toOption.getD 0)
    let rawStop := ((binding.getObjValAs? Nat "limit").toOption).getD
      ((fact.getObjValAs? Nat "outputLimit").toOption.getD rawFirst)
    let first := position offsets[toId]! rawFirst
    let stop := position offsets[toId]! rawStop
    let value := (Json.mkObj [("document",toJson toId),("kind",toJson kind),
      ("first",toJson (first-80)),("length",toJson (min 2400 (max 160 (stop-first+160)))),
      ("witnessSha256",toJson (Sha256.hex fact.compress.toUTF8))]).compress
    current.insert fromId ((current[fromId]?.getD {}).insert value)
  let mut bySubject : Std.HashMap Subject (Array (Range × Binding)) := {}
  for (range,bindings) in graph.bindings.toArray do
    for binding in bindings do
      bySubject := bySubject.insert range.subject ((bySubject[range.subject]?.getD #[]).push (range,binding))
  let bindingsFor (range : Range) := (bySubject[range.subject]?.getD #[]).filterMap fun (saved,binding) =>
    if (saved.intersection? range).isSome then some binding else none
  let mut counts : Std.HashMap String Nat := {}
  for fact in facts do
    match fact with
    | .read _ => pure ()
    | .consumed edge =>
      if let some consumer := occurrences[edge.consumer]? then
        if let some producer := occurrences[edge.producer]? then
          edges := addEdge edges consumer producer "consumed" (toJson edge)
          counts := counts.insert "consumed" (counts["consumed"]?.getD 0+1)
    | .supports support =>
      if let some answer := owners[support.claim.answer]? then
        if let some observation := owners[support.binding.owner]? then
          edges := addEdge edges answer observation "supports" (toJson support)
          counts := counts.insert "supports" (counts["supports"]?.getD 0+1)
    | .coquoted group range =>
      let owner := match group with | .answer _ owner => owner | .claim claim => claim.answer
      if let some answer := owners[owner]? then
        for binding in bindingsFor range do
          if let some observation := owners[binding.owner]? then
            edges := addEdge edges answer observation "coquoted" (Json.mkObj [
              ("group",toJson group),("source",toJson range),("binding",toJson binding)])
            counts := counts.insert "coquoted" (counts["coquoted"]?.getD 0+1)
    | .used usage =>
      if let some consumer := occurrences[usage.event.occurrence]? then
        for binding in bindingsFor usage.source do
          if let some observation := owners[binding.owner]? then
            edges := addEdge edges consumer observation "used" (toJson usage)
            counts := counts.insert "used" (counts["used"]?.getD 0+1)
  let mut neighbors := #[]
  for (id,values) in edges.toArray.qsort (fun a b => a.1 < b.1) do
    let values ← (values.toArray.qsort (· < ·)).mapM (IO.ofExcept ∘ Json.parse)
    neighbors := neighbors.push (Json.mkObj [("document",toJson id),("edges",toJson values)])
  check ((← DB.PageMap.pin database).head == source.head && (← DB.PageMap.pin indexPath).head == index.head)
    "source or advisory index changed during read-only export"
  check ((← DB.PageMap.pin usagePath).head == privateIndex.head) "private usage index changed during export"
  let result := exported.setObjVal! "neighbors" (toJson neighbors)
    |>.setObjVal! "graphSourceHead" (toJson index.head)
    |>.setObjVal! "graphFacts" (toJson facts.size)
    |>.setObjVal! "graphEdgeCounts" (toJson counts.toArray)
    |>.setObjVal! "privateUsageHead" (toJson privateIndex.head)
    |>.setObjVal! "graphWasRecomputed" (toJson false)
  IO.FS.writeFile output result.compress
end HistoryGraphExport
def main : List String → IO Unit
  | [originals,database,indexPath,usagePath,output] => HistoryGraphExport.run originals database indexPath usagePath output
  | _ => throw (IO.userError "HistoryGraphExport ORIGINALS DB PUBLISHED-INDEX PRIVATE-USAGE OUTPUT")
