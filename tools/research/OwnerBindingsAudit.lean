import Eggshell.SynapticBindings
import tools.research.SourceBindingReference
import tools.research.OwnerBindingLayout
open Lean Eggshell Eggshell.Synapses

#print axioms Eggshell.Research.OwnerBindingLayout.project_restore
#print axioms Eggshell.Research.OwnerBindingLayout.restrictions_commute

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := try let _ ← action; pure false catch _ => pure true

/-- The candidate publication contains no legacy point projection. This
independent test adds that projection only to the test index for the old scan. -/
private def oracle (reader : Index.Reader) (facts : Array Fact) : IO Index.Reader := do
  let previous : Array (String × Option ByteArray) ← reader.index.foldRange ⟨"binding:","binding;"⟩
    (fun rows row => pure (rows.push row)) #[]
  let _ ← DB.PageMap.withWriter reader.index fun writer => do
    for (key,_) in previous do writer.put key none
    for fact in facts do
      if let some read := Index.bindingCandidate? fact then
        let stored : Index.StoredBinding := ⟨Index.contentKey fact,read⟩
        let key := "binding:" ++ Index.contentKey read.source ++ ":" ++ stored.fact
        writer.put key (some (toJson stored).compress.toUTF8)
  return {reader with index := ← DB.PageMap.pin reader.index.directory}

private def compare (reader : Index.Reader) (wanted : Array Range) (owners : Array String) : IO Unit := do
  let allowed := Std.HashSet.ofArray owners
  let deadline := (← IO.monoMsNow)+30000
  let old ← Research.SourceBindingReference.resolve reader wanted allowed deadline
  let actual ← IndexedBindings.resolve reader wanted allowed deadline
  check (old.complete && actual.complete && old.requests == actual.requests &&
    old.unresolved == actual.unresolved && old.rows.size == actual.rows.size &&
    old.rows.toArray.all (fun (source,rows) => actual.rows[source]? == some rows))
    "owner inventory changed complete ranges, original Read order, admission or empties"

private def opened (source : DB.PageMap.Snapshot) : IO Index.Reader := do
  let some reader ← Index.open? source .database .shared | throw (IO.userError "fixture index unavailable")
  return reader

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "fresh owned audit directory required")
  let root : System.FilePath := .mk output
  check (!(← root.pathExists)) "preserve owner inventory audit"
  IO.FS.createDirAll root
  let source ← DB.PageMap.create (root / "source.egg") "owner-binding-inventory-audit"
  let database := source.head.identity
  let file : Synapses.File := ⟨"source/file.cc",String.ofList (List.replicate 64 'a'),200⟩
  let changed := {file with fingerprint := String.ofList (List.replicate 64 'b')}
  let range : Range := ⟨.file file,4,5⟩
  let absent : Range := ⟨.file file,19,20⟩
  let parent : Read := ⟨⟨"session-a","turn","call-a"⟩,⟨.file file,1,10⟩,
    ⟨database,"owner-a","work",0,200⟩,#[]⟩
  let support : Support := ⟨parent,range,⟨database,"answer",0,20⟩,
    {parent.binding with first := 30,limit := 45},range,.citation⟩
  let exactRead : Read := ⟨parent.occurrence,range,support.binding,#[]⟩
  let other := {exactRead with
    occurrence := ⟨"session-b","turn","call-b"⟩
    binding := {exactRead.binding with owner := "owner-b"}}
  let original : Original := ⟨"mcp-work",String.ofList (List.replicate 64 'c'),200⟩
  let generic : Read := ⟨⟨"mcp-session","turn","call"⟩,Range.original original 5 15,
    ⟨database,"owner::日本語/quoted","mcp-work",5,15⟩,#[]⟩
  let facts := #[Fact.read parent,.supports support,.read exactRead,.read other,.read generic,
    .read {exactRead with quotations := #[String.ofList (List.replicate 64 'd')]}]
  for fact in facts do
    if let some read := Index.bindingCandidate? fact then
      let encoded := Research.OwnerBindingLayout.project (Index.contentKey fact) read
      let decoded ← IO.ofExcept (fromJson? (α := Research.OwnerBindingLayout.Row) (toJson encoded))
      check (decoded == encoded && decoded.restore database read.binding.owner == read) "lossless owner wire changed a Read"
  let _ ← Index.replace source .database .shared facts
  let clean ← opened source
  let legacyCount ← clean.index.foldRange ⟨"binding:","binding;"⟩ (fun count _ => pure (count+1)) (0 : Nat)
  check (legacyCount == 0) "production candidate wrote legacy point bindings"
  let reader ← oracle clean facts
  let wanted := #[range,absent,range,parent.source,generic.source,⟨.file changed,4,5⟩]
  let ownerCases := #[#["owner-a","owner-b","owner::日本語/quoted"],#[],#["owner-a"],
    #["owner-b"],#["owner::日本語/quoted"],#["not-admitted"]]
  for owners in ownerCases do
    compare reader wanted owners
    compare reader #[] owners
  let expired ← IndexedBindings.resolve reader wanted (Std.HashSet.ofArray #["owner-a"]) 0
  check (!expired.complete && expired.requests == 0) "expired owner inventory claimed completion"
  let before ← IndexedBindings.resolve reader wanted (Std.HashSet.ofArray ownerCases[0]!) ((← IO.monoMsNow)+30000)
  let added := {exactRead with source := absent}
  let changedFacts := facts.push (.read added)
  let _ ← Index.replace source .database .shared changedFacts
  let updated ← oracle (← opened source) changedFacts
  for owners in ownerCases do compare updated wanted owners
  let addition ← IndexedBindings.resolve updated #[absent] (Std.HashSet.ofArray #["owner-a"])
    ((← IO.monoMsNow)+30000)
  check ((addition.rows[absent]?.getD #[]).size == 1) "new publication did not add its owner binding"
  let kept := changedFacts.filter fun fact => fact != .read other && fact != .read added
  let _ ← Index.replace source .database .shared kept
  let removed ← oracle (← opened source) kept
  for owners in ownerCases do compare removed wanted owners
  let now ← IndexedBindings.resolve removed wanted (Std.HashSet.ofArray ownerCases[0]!) ((← IO.monoMsNow)+30000)
  check ((now.rows[range]?.getD #[]).all (fun read => read.binding.owner != "owner-b") &&
    (now.rows[absent]?.getD #[]).isEmpty) "removed origin survived its publication"
  let pinned ← IndexedBindings.resolve reader wanted (Std.HashSet.ofArray ownerCases[0]!) ((← IO.monoMsNow)+30000)
  check (pinned.rows.toArray.all (fun (key,value) => before.rows[key]? == some value)) "new publication changed old pin"
  let pages ← DB.PageMap.PagePool.new
  let shared := {reader with index := ← reader.index.sharePages pages "owner-binding-audit"}
  let jobs ← (Array.range 80).mapM fun i => IO.asTask (do
    compare shared wanted ownerCases[i%ownerCases.size]!) .dedicated
  for job in jobs do let _ ← IO.ofExcept (job.get.mapError IO.Error.toString); pure ()
  let wrong := Research.OwnerBindingLayout.project (Index.contentKey (Fact.read other)) other
  let _ ← DB.PageMap.withWriter removed.index fun writer =>
    writer.put (Research.OwnerBindingLayout.postingPrefix "owner-a" true ++ wrong.fact) (some (toJson wrong).compress.toUTF8)
  let malformed := {removed with index := ← DB.PageMap.pin removed.index.directory}
  check (← rejected (IndexedBindings.resolve malformed #[range] (Std.HashSet.ofArray #["owner-a"])
    ((← IO.monoMsNow)+30000))) "foreign owner under a hashed posting was accepted"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("sameCompleteOrderedReads",toJson true),
    ("emptyDuplicateMixedAndChangedFingerprint",toJson true),("genericOriginalIncluded",toJson true),
    ("ownerAdmissionEachRequest",toJson true),("publicationAddDeleteAndOldPin",toJson true),
    ("fullOwnerCheckedAfterHash",toJson true),("concurrentRequests",toJson (80 : Nat)),
    ("operationalByteCountersMayDiffer",toJson true),("fixtureOnly",toJson true),
    ("legacyProjectionOnlyInOracleFixture",toJson true),("actualHook",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println "Owner inventories equal original complete Read sequences across scopes, subjects, changes and 80 requests"
