import tools.research.PreparedInputChecks
import tools.research.FederationOrderReference

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Persistence.Store
open Eggshell.Persistence.Store.Federated

namespace Eggshell.Research.FederationOrderChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def node (value : Node sources) : Nat × Nat := (value.source.val,value.id)

private def unionJson (edge : UnionEdge) : Json :=
  let (kind,scope) := match edge.scope with
    | .run value => ("run",value)
    | .workspace value => ("workspace",value)
  toJson (Persistence.valueToJson edge.left,Persistence.valueToJson edge.right,
    kind,Persistence.valueToJson scope)

private def signature (catalogue : Catalogue sources) : Json :=
  let keys := (catalogue.owners.toList.map Prod.fst).mergeSort (· ≤ ·)
  Json.mkObj [
    ("identity",toJson (catalogue.identity.nodes.map fun entry =>
      (node entry.original,entry.application.map fun key =>
        (reprStr key.operator,key.arguments.map fun (pair : Authority × Nat) => (reprStr pair.1,pair.2))))),
    ("aliases",toJson (catalogue.identity.aliases.toList.mergeSort fun a b =>
      decide (a.1.1 < b.1.1 ∨ (a.1.1 = b.1.1 ∧ a.1.2 ≤ b.1.2)))),
    ("roots",toJson catalogue.roots),("orders",toJson (catalogue.roots.map fun owner => catalogue.orders[owner]?)),
    ("owners",toJson (keys.map fun key => (key,(catalogue.owners[key]?).map node))),
    ("origins",toJson (keys.map fun key => (key,(catalogue.ownerOrigins.getD key []).map node))),
    ("documents",toJson (catalogue.documents.map fun doc =>
      (node doc.node,doc.owner,doc.work,doc.ordinal,doc.original.owner,doc.original.work,
        doc.original.windows,toJson doc.original.cache))),
    ("all",toJson (catalogue.all.map (Persistence.valueToJson ∘ AllEdge.relation))),
    ("unions",toJson (catalogue.unions.map unionJson)),
    ("semanticPopulation",toJson catalogue.semanticPopulation)]

private def sourceValues (lane count : Nat) : List Value := Id.run do
  let mut values := []
  let mut works := []
  for n in [:count] do
    let shared := n%8 == 0
    let key := if shared then s!"shared{n}" else s!"lane{lane}record{n}"
    let work := Value.text ("inspect kernel evidence "++key)
    let body := Value.text (key++"\n"++String.ofList (List.replicate 5000 'x'))
    let owner := OutcomeEdge.make work body [.text ("original dependency "++key)]
      (by simp) (by simp [maxOutcomeObservations])
    values := owner.relation :: values
    works := work :: works
  let parent := Value.text s!"parent lane {lane}"
  if valid : works.reverse ≠ [] ∧ parent ∉ works.reverse then
    values := (AllEdge.make parent works.reverse valid.1 valid.2).relation :: values
  return values.reverse

private def prepareSources (root : System.FilePath) (count : Nat) : IO (Array System.FilePath) := do
  let mut paths := #[]
  for lane in [:16] do
    let path := root/s!"owner-{lane}.egg"
    let source ← PageMap.create path (Persistence.valueToJson (.text s!"federation-order-owner-{lane}")).compress
    let values := sourceValues lane count
    let _ ← PageMap.withWriter source fun writer => do
      let intern : Intern := ⟨writer,← IO.mkRef {}⟩
      let added ← values.mapM intern.root
      if lane == 0 || lane == 1 then
        let authority ← Persistence.Store.authority source
        let left := Value.text (if lane == 0 then "alias start" else "alias bridge")
        let right := Value.text (if lane == 0 then "alias bridge" else "inspect kernel evidence lane15record1")
        let edge : UnionEdge := ⟨left,right,.workspace authority,by intro _; rfl⟩
        addUnions intern [edge]
      writeChange writer {added,removed := [],unionsChanged := lane < 2}
    paths := paths.push path
  return paths

private def counters (sources : Array PageMap.Snapshot) : IO (Nat × Nat) := do
  let mut reads := 0
  let mut bytes := 0
  for source in sources do
    reads := reads+(← source.reads.get)
    bytes := bytes+(← source.readBytes.get)
  return (reads,bytes)

private def observedBefore (sources : Array PageMap.Snapshot) : IO (Catalogue sources × Json) := do
  let started ← IO.monoMsNow
  let previous ← IO.mkRef started
  let stages ← IO.mkRef ({} : Std.HashMap String (Nat × Nat × Nat))
  let result ← FederationOrderReference.prepare sources fun stage => do
    let now ← IO.monoMsNow
    let prior ← previous.get
    previous.set now
    let (ms,calls,_) := (← stages.get).getD stage (0,0,0)
    let (_,bytes) ← counters sources
    stages.modify (·.insert stage (ms+now-prior,calls+1,bytes))
  let elapsed := (← IO.monoMsNow)-started
  return (result,Json.mkObj [("elapsedMs",toJson elapsed),("physical",toJson (← counters sources)),
    ("stages",toJson (← stages.get).toList)])

private def measured (paths : Array System.FilePath) (before : Bool) : IO (Json × Json) := do
  let sources ← paths.mapM PageMap.pin
  let started ← IO.monoMsNow
  let (catalogue,measurement) ← if before then observedBefore sources else do
    let catalogue ← Federated.prepare sources
    let elapsed := (← IO.monoMsNow)-started
    pure (catalogue,Json.mkObj [("elapsedMs",toJson elapsed),("physical",toJson (← counters sources))])
  return (signature catalogue,measurement)

private def classAudit (paths : Array System.FilePath) : IO Json := do
  let sources ← paths.mapM PageMap.pin
  let readers ← NodeReaders.new sources
  let mut persistent := []
  let mut values := []
  for source in List.finRange sources.size do
    persistent := persistent ++ ((← (readers.at source).unions (← authority sources[source])).map (·.edge))
    values := values ++ (← materialize sources[source]).values
  let graph := WorkGraph.fromValues values
  let some classes := WorkClassLookup.prepare? persistent [] |
    throw (IO.userError "cross-owner class setup invalid")
  let mut probes := #[]
  for query in ["alias start","inspect kernel evidence shared0","absent inquiry"] do
    let started ← IO.monoMsNow
    let owners ← readers.classOwners classes query.toUTF8
    let elapsed := (← IO.monoMsNow)-started
    let expected := graph.outcomes.filter fun edge => classes.checked.quotient.toEquality.same (.text query) edge.work
    let actual := hashDistinct (owners.map (·.2.edge.relation))
    check (Std.HashSet.ofList actual == Std.HashSet.ofList (expected.map (·.relation)))
      "indexed cross-owner certification domain differs from full graph"
    if query == "alias start" then check (!actual.isEmpty) "two-owner Union chain did not reach a third owner"
    probes := probes.push (Json.mkObj [("query",toJson query),("physicalOwners",toJson owners.length),
      ("uniqueOwners",toJson actual.length),("elapsedMs",toJson elapsed),("fullGraphEqual",toJson true)])
  let omitted ← if bound : 1 < sources.size then pure (sources.eraseIdx 1 bound)
    else throw (IO.userError "bridge source absent from fixture")
  let restricted ← NodeReaders.new omitted
  let mut allowed := []
  for source in List.finRange omitted.size do
    allowed := allowed ++ ((← (restricted.at source).unions (← authority omitted[source])).map (·.edge))
  let some restrictedClasses := WorkClassLookup.prepare? allowed [] |
    throw (IO.userError "restricted class setup invalid")
  check ((← restricted.classOwners restrictedClasses "alias start".toUTF8).isEmpty)
    "unauthorized bridge owner still participated in certification"
  return Json.mkObj [("queries",toJson probes),("omittedBridgeCannotCertify",toJson true)]

def run (root : System.FilePath) (count : Nat) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists) && [16,64,256].contains count)
    "fresh fixture and predeclared per-owner count required"
  FileSystem.privateDirectory root
  let sourceStarted ← IO.monoMsNow
  let paths ← prepareSources root count
  let sourceMs := (← IO.monoMsNow)-sourceStarted
  let heads ← paths.mapM fun path => do return (← PageMap.pin path).head
  let mut trials := #[]
  for repetition in [:3] do
    let ((reference,before),(actual,after)) ← if repetition%2 == 0 then do
        let before ← measured paths true
        let after ← measured paths false
        pure (before,after)
      else do
        let after ← measured paths false
        let before ← measured paths true
        pure (before,after)
    check (actual == reference) "linear construction changed full federation metadata or ordering"
    trials := trials.push (Json.mkObj [("repetition",toJson repetition),("before",before),("after",after),
      ("completeMetadataEqual",toJson true),("signatureSha256",toJson (Sha256.hex actual.compress.toUTF8))])
    IO.FS.writeFile (root/"trials.json") (toJson trials).pretty
  let classes ← classAudit paths
  let after ← paths.mapM fun path => do return (← PageMap.pin path).head
  check (heads == after) "read-only comparison changed original sources"
  let report := Json.mkObj [("allPassed",toJson true),("owners",toJson (16 : Nat)),
    ("recordsPerOwner",toJson count),("rawOutcomes",toJson (16*count)),("outputCharacters",toJson (5000 : Nat)),
    ("sourceBuildMs",toJson sourceMs),("trials",toJson trials),("classQueries",classes),
    ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false),("eightyPeopleEightHours",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

end Eggshell.Research.FederationOrderChecks

#print axioms Eggshell.Persistence.Store.Federated.reversed_push_order
#print axioms Eggshell.Persistence.Store.Federated.reversed_batch_order

def main (args : List String) : IO UInt32 := do
  match args with
  | ["federation-order",root,count] =>
    Eggshell.Research.FederationOrderChecks.run (.mk root) (count.toNat?.getD 0)
    return 0
  | other => preparedInputMain other
