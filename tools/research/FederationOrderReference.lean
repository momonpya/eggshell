import Eggshell.FederatedSearch
open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store Eggshell.Persistence.Store.Federated
namespace Eggshell.Research.FederationOrderReference

def prepare (sources : Array Snapshot) (observe : String → IO Unit := fun _ => pure ()) : IO (Catalogue sources) := do
  let readers ← NodeReaders.new sources
  observe "readers"
  let mut identity : Identity sources := {}
  let mut semantic : Std.HashSet Nat := {}
  let mut topology := []
  let mut unions := []
  for source in List.finRange sources.size do
    let snapshot := sources[source]
    let reader := readers.at source
    let edges ← reader.topology
    topology := topology ++ edges
    let edges ← reader.unions (← authority snapshot)
    unions := unions ++ edges.map (·.edge)
    observe "topology-unions"
    let nodes ← directory snapshot "semanticUses"
    unless nodes.length == (← getNat snapshot.get "semanticPopulation") &&
        nodes.all (fun row => row.2 > 0) do
      throw (IO.userError "federated semantic population is incomplete")
    for (id, _) in nodes do
      let (next, canonical) ← identity.add ⟨source, id⟩
      identity := next
      semantic := semantic.insert canonical
    observe "canonical-identity"
  let mut roots := []
  let mut owners : Std.HashMap Nat (Node sources) := {}
  let mut ownerOrigins : Std.HashMap Nat (List (Node sources)) := {}
  let mut documents : List (Document sources) := []
  let mut known : Std.HashSet Nat := {}
  for source in List.finRange sources.size do
    let snapshot := sources[source]
    for (_, id) in (← rootDirectory snapshot) do
      roots := roots ++ [← identity.lookup source id]
    observe "root-directory"
    let rows ← directory snapshot "outcome"
    unless rows.length == (← getNat snapshot.get "liveOutcomes") do
      throw (IO.userError "federated Outcome population is incomplete")
    for (_, id) in rows do
      let _ ← locateOutcome snapshot id
      let canonical ← identity.lookup source id
      ownerOrigins := ownerOrigins.insert canonical (ownerOrigins.getD canonical [] ++ [⟨source, id⟩])
      unless owners.contains canonical do owners := owners.insert canonical ⟨source, id⟩
    observe "outcome-headers"
    for document in (← searchDocuments snapshot) do
      let owner ← identity.lookup source document.owner
      unless owners.contains owner do throw (IO.userError "federated candidate is not an Outcome")
      unless known.contains owner do
        known := known.insert owner
        documents := documents ++ [⟨⟨source, document.owner⟩, document, owner,
          ← identity.lookup source document.work, 0⟩]
    observe "document-directory"
  roots := hashDistinct roots
  let orders := Std.HashMap.ofList (roots.zipIdx)
  documents ← documents.mapM fun document => do
    let some ordinal := orders[document.owner]? |
      throw (IO.userError "federated document has no live source root")
    pure {document with ordinal}
  let result : Catalogue sources := {
    readers, identity, roots, orders, owners, ownerOrigins
    documents := documents.mergeSort (fun first second => first.ordinal ≤ second.ordinal)
    all := topology.eraseDups
    unions, semanticPopulation := semantic.size }
  observe "final-order"
  pure result


end Eggshell.Research.FederationOrderReference
