import Eggshell.Install

open Lean Eggshell

/-- Compare logical publications after a native hook. Physical page/head hashes
may change when the hook publishes a derived memo. Every changed row is exposed;
only the existing PageMap derived-key predicate classifies a change as a memo.
This is an offline diagnostic, never a hook or an acceptance test. -/
def publicationRows (snapshot : DB.PageMap.Snapshot) :
    IO (Array (String × String)) := do
  let upper := (snapshot.head.root.map (·.last)).getD "" ++ " "
  snapshot.foldRange { lower := "", upper } (fun rows (key, value) => do
    pure (rows.push (key, match value with
      | none => "absent"
      | some bytes => Sha256.hex bytes))) #[]

def main (arguments : List String) : IO Unit := do
  let [beforePath, afterPath] := arguments |
    throw (IO.userError "PublicationAudit BEFORE_DATABASE AFTER_DATABASE")
  let before ← DB.PageMap.pin (.mk beforePath)
  let after ← DB.PageMap.pin (.mk afterPath)
  let beforeGraph ← Persistence.Store.materialize before
  let afterGraph ← Persistence.Store.materialize after
  let authoritativeEqual := beforeGraph.authority == afterGraph.authority &&
    beforeGraph.values == afterGraph.values &&
    beforeGraph.unions.map (fun edge => (edge.edge.left, edge.edge.right)) ==
      afterGraph.unions.map (fun edge => (edge.edge.left, edge.edge.right))
  let mut publications : Array Json := #[]
  if before.head.identity == after.head.identity then
    for revision in [before.head.revision + 1 : after.head.revision + 1] do
      let publication ← Persistence.Store.readPublication after revision
      publications := publications.push (Json.mkObj [
        ("revision", toJson revision), ("added", toJson publication.change.added),
        ("removed", toJson publication.change.removed),
        ("unionsChanged", toJson publication.change.unionsChanged),
        ("neutral", toJson publication.change.neutral),
        ("parent", toJson publication.parent)])
  let left ← publicationRows before
  let right ← publicationRows after
  let leftMap : Std.HashMap String String := Std.HashMap.ofList left.toList
  let rightMap : Std.HashMap String String := Std.HashMap.ofList right.toList
  let mut changed : Array Json := #[]
  let mut nonDerivedChanges := 0
  for (key, hash) in left do
    unless rightMap[key]? == some hash do
      if !DB.PageMap.derivedKey key then nonDerivedChanges := nonDerivedChanges + 1
      changed := changed.push (Json.mkObj [
        ("key", toJson key), ("beforeSha256", toJson (some hash)),
        ("afterSha256", toJson rightMap[key]?),
        ("derived", toJson (DB.PageMap.derivedKey key))])
  for (key, hash) in right do
    unless leftMap.contains key do
      if !DB.PageMap.derivedKey key then nonDerivedChanges := nonDerivedChanges + 1
      changed := changed.push (Json.mkObj [
        ("key", toJson key), ("beforeSha256", toJson (none : Option String)),
        ("afterSha256", toJson (some hash)),
        ("derived", toJson (DB.PageMap.derivedKey key))])
  IO.println (Json.mkObj [
    ("before", toJson beforePath), ("after", toJson afterPath),
    ("beforeHead", toJson before.head), ("afterHead", toJson after.head),
    ("beforeRows", toJson left.size), ("afterRows", toJson right.size),
    ("changedRows", toJson changed), ("nonDerivedChanges", toJson nonDerivedChanges),
    ("nonDerivedRowsEqual", toJson (nonDerivedChanges == 0)),
    ("authoritativeGraphEqual", toJson authoritativeEqual),
    ("beforeRoots", toJson beforeGraph.values.length),
    ("afterRoots", toJson afterGraph.values.length),
    ("beforeUnions", toJson beforeGraph.unions.length),
    ("afterUnions", toJson afterGraph.unions.length),
    ("publications", toJson publications),
    ("physicalPublicationEqual", toJson (before.head == after.head)),
    ("generationModelCalls", toJson (0 : Nat))]).compress
