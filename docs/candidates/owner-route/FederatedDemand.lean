module
public import Eggshell.WorkClassLookup

@[expose] public section
namespace Eggshell.Persistence.Store.FederatedDemand

/-- A union's distinct Values never need more fuel than the total original
domains. Applying this to disk allocation additionally relies on each checked
source's node-domain contract; this is not a proof of filesystem IO. -/
theorem distinct_original_bound (domains : List (List Value)) :
    (hashDistinct domains.flatten).length ≤ (domains.map List.length).sum := by
  simpa using HashDistinct.length_le domains.flatten

structure Member (sources : Array Snapshot) where
  source : Fin sources.size
  demand : DemandTopology sources[source]

structure Reader (sources : Array Snapshot) where
  members : List (Member sources)

def new (readers : NodeReaders sources) : IO (Reader sources) := do
  let members ← (List.finRange sources.size).mapM fun source => do
    return (⟨source,← DemandTopology.new (readers.at source)⟩ : Member sources)
  return ⟨members⟩

def Reader.full (reader : Reader sources) : IO (List AllEdge) := do
  let reversed ← reader.members.foldlM (init := []) fun known member => do
    return (← member.demand.reader.topology).reverse++known
  return reversed.reverse.eraseDups

def Reader.bound (reader : Reader sources) : IO Nat := do
  reader.members.foldlM (init := 0) fun total member => do
    return total+(← getNat sources[member.source].get "nodes")

def Reader.selected (reader : Reader sources) (chosen : Std.HashSet (Nat × Nat)) : IO (List AllEdge) := do
  let mut reversed := []
  for member in reader.members do
    let loaded ← member.demand.loaded.get
    let rows := loaded.toList.filterMap fun (id,row) =>
      if chosen.contains (member.source.val,id) then some row else none
    let edges := (rows.mergeSort (fun a b => a.1 ≤ b.1)).map (·.2)
    reversed := edges.reverse++reversed
  return reversed.reverse.eraseDups

/-- One queue spans the entire captured inventory. Closing each source on
its own would lose a parent reached through another source's child. -/
def Reader.read (reader : Reader sources) (edges : List UnionEdge)
    (requested : List Value) : IO (List AllEdge) := do
  let some classes := QuotientBuilder.AtomQuotient.prepare edges | return ← reader.full
  let rec visit : Nat → List Value → Std.HashSet Value → Std.HashSet (Nat × Nat) →
      IO (Option (Std.HashSet (Nat × Nat)))
    | _,[],_,chosen => return some chosen
    | 0,_::_,_,_ => throw (IO.userError "joint All demand exceeded its original finite domain")
    | fuel+1,work::pending,seen,chosen => do
      if seen.contains work then return ← visit fuel pending seen chosen
      let .atom bytes := work | return none
      let seen := seen.insert work
      let mut pending := pending
      let mut chosen := chosen
      for alias in classes.aliases bytes do
        for member in reader.members do
          for id in ← member.demand.parentIds alias do
            let location := (member.source.val,id)
            unless chosen.contains location do
              let edge ← member.demand.edge id
              chosen := chosen.insert location
              pending := hashDistinct (edge.children++pending) |>.filter (!seen.contains ·)
      visit fuel pending seen chosen
  let some chosen ← visit ((← reader.bound)+requested.length+1) (hashDistinct requested) {} {} |
    return ← reader.full
  reader.selected chosen

def Reader.neighborhood (reader : Reader sources) (edges : List UnionEdge)
    (requested : List Value) : IO (List AllEdge) := do
  let initial := hashDistinct requested
  let rec visit : Nat → Nat → Array Value → Std.HashSet Value → Std.HashSet (Nat × Nat) →
      IO (Std.HashSet (Nat × Nat))
    | fuel,cursor,queue,scheduled,chosen => do
      let some work := queue[cursor]? | return chosen
      let remaining+1 := fuel | throw (IO.userError "joint source component exceeded its original finite domain")
      let mut neighbors := edges.flatMap fun edge =>
        (if edge.left == work then [edge.right] else [])++(if edge.right == work then [edge.left] else [])
      let mut chosen := chosen
      for member in reader.members do
        for id in (← member.demand.parentIds work)++(← literalAllChildren sources[member.source] work) do
          let edge ← member.demand.edge id
          let some incident := IncidentAll.check? work edge | throw (IO.userError "joint source posting is not incident")
          neighbors := incident.neighbors++neighbors
          chosen := chosen.insert (member.source.val,id)
      let mut queue := queue
      let mut scheduled := scheduled
      for neighbor in neighbors do
        unless scheduled.contains neighbor do
          scheduled := scheduled.insert neighbor
          queue := queue.push neighbor
      visit remaining (cursor+1) queue scheduled chosen
  let chosen ← visit ((← reader.bound)+initial.length+edges.length*2+1) 0 initial.toArray (Std.HashSet.ofList initial) {}
  reader.selected chosen

/-- Child membership is complete over every source and every current class.
The quotient index and negative-result cache belong to one discovery pass. -/
def Reader.childLookup (reader : Reader sources) (view : RunView)
    (observe : Option (ChildObservation → IO Unit) := none) : IO (Value → IO Bool) := do
  let index := Quotient.AliasIndex.prepare view.quotient
  let known ← IO.mkRef ({} : Std.HashMap Value Bool)
  return fun work => do
    if let some found := (← known.get)[work]? then return found
    let mut found := false
    for alias in index.aliases work do
      for member in reader.members do
        let parents ← literalAllChildren sources[member.source] alias (observe.map fun use observed =>
          use {observed with requested := work})
        unless parents.isEmpty do
          found := true
          break
      if found then break
    known.modify (·.insert work found)
    return found

end Eggshell.Persistence.Store.FederatedDemand
