module
public import Eggshell.SynapticBindings
@[expose] public section

namespace Eggshell.Synapses.BindingPageScan
open Lean DB

structure Target where
  source : Range
  range : PageMap.KeyRange
  exact : range = ⟨"binding:" ++ Index.contentKey source ++ ":","binding:" ++ Index.contentKey source ++ ";"⟩

def target (source : Range) : Target :=
  let base := "binding:" ++ Index.contentKey source
  ⟨source,⟨base ++ ":",base ++ ";"⟩,rfl⟩

def directory (wanted : Array Range) : Except String (Array Target) := do
  let targets := ((hashDistinct wanted.toList).toArray.map target).qsort fun a b => a.range.lower < b.range.lower
  for index in [:targets.size] do
    let some current := targets[index]? | throw "binding directory lost a target"
    unless current.source.valid do throw "invalid original binding target"
    if let some prior := targets[index-1]? then
      if index > 0 && current.range.lower < prior.range.upper then
        throw "binding targets have an ambiguous content address"
  return targets

def relevant (targets : Array Target) (ref : PageMap.Ref) : Array Target :=
  targets.filter fun target => target.range.overlaps ref

/-- The same checked child fences as a point/range scan. Batching only shares
their traversal; it cannot drop a target that contains an original row. -/
theorem relevant_retains (targets : Array Target) (target : Target) (ref : PageMap.Ref)
    (rows : List PageMap.Row) (admitted : target ∈ targets) (row : PageMap.Row)
    (member : row ∈ rows) (matched : target.range.contains row.1 = true)
    (bounded : ∀ row ∈ rows, ref.first ≤ row.1 ∧ row.1 ≤ ref.last) :
    target ∈ relevant targets ref := by
  apply Array.mem_filter.mpr
  refine ⟨admitted,?_⟩
  by_cases overlap : target.range.overlaps ref = true
  · exact overlap
  · have outside : target.range.overlaps ref = false := Bool.eq_false_iff.mpr overlap
    have selected : row ∈ target.range.select rows := List.mem_filter.mpr ⟨member,matched⟩
    rw [target.range.prune_exact ref rows bounded outside] at selected
    contradiction

structure Bucket where
  /-- Prepending avoids repeatedly copying an increasing array shared by a map. -/
  rows : List Index.StoredBinding := []
  inspected : Nat := 0
  bytes : Nat := 0

structure Scan where
  buckets : Std.HashMap Range Bucket := {}
  bytes : Nat := 0
  pages : Nat := 0
  leaves : Nat := 0
  complete : Bool := true

/-- One visit per intersecting physical subtree, not one root-to-leaf walk
per target. Source postings are already compiled by publication. -/
def scanAt (snapshot : PageMap.Snapshot) (ref : PageMap.Ref) (targets : Array Target)
    (deadline byteLimit : Nat) (initial : Scan) : IO Scan := do
  if !initial.complete then return initial
  if (← IO.monoMsNow) ≥ deadline then return {initial with complete := false}
  -- Authenticate the root/page before using its fences to certify absence.
  let loaded ← snapshot.load ref
  let targets := relevant targets ref
  let mut result := {initial with pages := initial.pages+1}
  if targets.isEmpty then return result
  match loaded.page with
  | .leaf rows =>
    result := {result with leaves := result.leaves+1}
    for row in rows do
      let some target := targets.find? (fun target => target.range.contains row.1) | continue
      let some bytes := row.2 | continue
      let prior := result.buckets[target.source]?.getD {}
      if prior.inspected ≥ 32768 || result.bytes+bytes.size > byteLimit || (← IO.monoMsNow) ≥ deadline then
        return {result with complete := false}
      let stored ← Index.decodeBinding bytes
      unless row.1 == target.range.lower ++ stored.fact && stored.read.source == target.source && stored.read.valid do
        throw (IO.userError "batch binding differs from its pinned original source")
      let next := {prior with rows := stored :: prior.rows,inspected := prior.inspected+1,bytes := prior.bytes+bytes.size}
      result := {result with buckets := result.buckets.insert target.source next,bytes := result.bytes+bytes.size}
    return result
  | .branch children =>
    for child in children do
      let active := relevant targets child
      if active.isEmpty then continue
      if _smaller : child.height < ref.height then
        result ← scanAt snapshot child active deadline byteLimit result
      else throw (IO.userError "binding batch directory height did not decrease")
      if !result.complete then return result
    return result
termination_by ref.height

structure Report where
  resolved : IndexedBindings.Resolved
  pages : Nat
  leaves : Nat

def resolveReport (reader : Index.Reader) (wanted : Array Range) (allowed : Std.HashSet String)
    (deadline : Nat) : IO Report := do
  let wanted := (hashDistinct wanted.toList).toArray
  if !wanted.isEmpty && (← IO.monoMsNow) ≥ deadline then
    return ⟨{complete := false},0,0⟩
  let targets ← IO.ofExcept (directory wanted)
  let scanned ← if wanted.isEmpty then pure ({} : Scan) else
    match reader.index.head.root with
    | none => pure ({} : Scan)
    | some root => scanAt reader.index root targets deadline (32*1024*1024) {}
  let completed := scanned.complete && (wanted.isEmpty || (← IO.monoMsNow) < deadline)
  let mut result : IndexedBindings.Resolved := {complete := completed,bytes := scanned.bytes}
  for source in wanted do
    let bucket := scanned.buckets[source]?.getD {}
    let mut seen : Std.HashSet Read := {}
    let mut rows := #[]
    for stored in bucket.rows.reverse do
      let some original := IndexedBindings.checkRead? reader.manifest.source.identity allowed source stored.read | continue
      if seen.contains original.read then continue
      seen := seen.insert original.read
      rows := rows.push original.read
    result := {result with
      rows := result.rows.insert source rows,requests := result.requests+1,
      inspected := result.inspected+bucket.inspected,
      unresolved := result.unresolved+(if rows.isEmpty then 1 else 0)}
  return ⟨result,scanned.pages,scanned.leaves⟩

def resolve (reader : Index.Reader) (wanted : Array Range) (allowed : Std.HashSet String)
    (deadline : Nat) : IO IndexedBindings.Resolved :=
  (·.resolved) <$> resolveReport reader wanted allowed deadline

end Eggshell.Synapses.BindingPageScan
