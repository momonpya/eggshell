import Eggshell.SourceOwners
import Eggshell.FederatedSearch

open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store
namespace Eggshell.Research.SourceOwnerChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def value (lane n : Nat) : Value :=
  let name := if n == 0 then "shared0" else s!"lane{lane}record{n}"
  (OutcomeEdge.make (.text ("inspect kernel evidence "++name))
    (.text (s!"original {name}\n"++String.ofList (List.replicate 800 'x')))
    [.text ("immutable dependency "++name)] (by simp) (by simp [maxOutcomeObservations])).relation

def variant (lane : Nat) (structured : Bool) : Value :=
  let work := if structured then Value.applyList .inquiry [(.semantic,.text "structured Work")]
    else Value.text "inspect kernel evidence shared0"
  (OutcomeEdge.make work (.text "same result") [.text s!"Exact distinction {lane}"]
    (by simp) (by simp [maxOutcomeObservations])).relation

def source (root : System.FilePath) (lane count : Nat) : IO System.FilePath := do
  let path := root/s!"owner-{lane}.egg"
  let snapshot ← PageMap.create path (Persistence.valueToJson (.text s!"source-owner-{lane}")).compress
  let _ ← PageMap.withWriter snapshot fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let added ← (List.range count).mapM fun n => intern.root (value lane n)
    writeChange writer {added,removed := [],unionsChanged := false}
  return path

def revise (path : System.FilePath) (lane : Nat) (added removed : List Nat) : IO Unit := do
  let snapshot ← PageMap.pin path
  let _ ← PageMap.withWriter snapshot fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let mut deleted := []
    for n in removed do
      let some id ← findNode? snapshot (value lane n) | throw (IO.userError "fixture original missing")
      removeRoot writer id
      deleted := id::deleted
    let ids ← added.mapM fun n => intern.root (value lane n)
    writeChange writer {added := ids,removed := deleted,unionsChanged := false}
  return ()

def prepare (root path : System.FilePath) : IO (SourceOwners.Captured × Json) := do
  let source ← PageMap.pin path
  let _ ← RetrievalResearch.Index.warm source .database
  let indexPath := root/(path.fileName.getD "missing"++"-index")
  if !(← indexPath.pathExists) then
    let _ ← PageMap.create indexPath "individual-source-owner-index"
  let index ← PageMap.pin indexPath
  let started ← IO.monoMsNow
  let prepared ← SourceOwners.prepare (root/"dictionary.egg") index source "project/authorized-scope"
  return (prepared.captured,Json.mkObj [("mode",toJson prepared.mode),
    ("publications",toJson prepared.publications),("changedOwners",toJson prepared.changedOwners),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started))])

def readerFor (captured : Array SourceOwners.Captured) : IO SourceOwners.Reader := do
  let some reader ← SourceOwners.open? captured "project/authorized-scope" |
    throw (IO.userError "individually prepared source combination rejected")
  return reader

def audit (captured : Array SourceOwners.Captured) (stableHeads : Bool := true) : IO Json := do
  let started ← IO.monoMsNow
  let reader ← readerFor captured
  let admissionMs := (← IO.monoMsNow)-started
  let sources := reader.inputs.map (·.original)
  let before ← sources.mapM fun source => do return (← PageMap.pin source.directory).head
  let dictionaryBefore := (← PageMap.pin reader.dictionary.directory).head
  let reference ← Federated.prepare sources
  check (reader.counts == (reference.owners.size,reference.documents.length)) "factorized owner/candidate populations differ"
  let mut mapped : Std.HashMap Nat Nat := {}
  let mut originalsCount := 0
  let mut ordering := []
  let mut terms : Std.HashSet String := {}
  let mut modernTerms : Std.HashSet String := {}
  for (canonical,originals) in reference.ownerOrigins.toList do
    let mut expected := []
    let mut identity := none
    for original in originals do
      let some actual ← reader.owner? original.source.val original.id | throw (IO.userError "original absent from source membership")
      if let some previous := identity then check (previous == actual) "duplicate originals got distinct stable ids"
      identity := some actual
      expected := expected++[(original.source.val,original.id,← getNat original.snapshot.get (key "member" original.id))]
      originalsCount := originalsCount+1
      let nodeReader ← NodeReader.new original.snapshot
      let outcome ← nodeReader.outcome (← locateOutcome original.snapshot original.id)
      for term in ownerTermsFor outcome do terms := terms.insert term
      if (← original.snapshot.get (key "candidate" original.id)).isSome then
        for term in RetrievalResearch.tokens (searchText outcome) do modernTerms := modernTerms.insert term
    let some stableId := identity | throw (IO.userError "empty full reference origins")
    let actual ← reader.originals stableId
    check (actual.map (fun original => (original.source,original.node,original.ordinal)) == expected)
      "source order, original inventory or reinserted ordinal differs"
    mapped := mapped.insert stableId canonical
    let some first := actual.head? | throw (IO.userError "live canonical owner has no original")
    ordering := (reference.orders.getD canonical 0,first.source,first.ordinal)::ordering
  let ordered := ordering.mergeSort (fun a b => a.1 ≤ b.1)
  check ((ordered.zip ordered.tail).all fun (a,b) =>
    a.2.1 < b.2.1 || (a.2.1 == b.2.1 && a.2.2 < b.2.2)) "tie order differs from complete engine"
  for modern in [false,true] do
    for term in (if modern then modernTerms else terms).toList++["ABSENT_GLOBAL_TERM"] do
      let expected ← Federated.postings reference term modern
      let found ← reader.postings term modern
      let canonical ← found.mapM fun id => do
        let some actual := mapped[id]? | throw (IO.userError "foreign stable owner in posting")
        return actual
      check (Std.HashSet.ofList canonical == Std.HashSet.ofList expected.toList &&
        (← reader.frequency term modern) == expected.size) "exact deduplicated postings/frequency differ"
  if stableHeads then
    check ((← sources.mapM fun source => do return (← PageMap.pin source.directory).head) == before)
      "query modified original roots"
  check ((← PageMap.pin reader.dictionary.directory).head == dictionaryBefore) "query modified dictionary root"
  return Json.mkObj [("outcomes",toJson reader.counts.1),("candidates",toJson reader.counts.2),
    ("originals",toJson originalsCount),("admissionMs",toJson admissionMs),
    ("ownerOriginsOrderAndBothLexicalContractsEqual",toJson true),
    ("bitmapNodesRead",toJson (← reader.bitmap.reads.get)),("fullAuditMs",toJson ((← IO.monoMsNow)-started))]

def bitmap (root : System.FilePath) : IO Json := do
  let path := root/"bitmap-only.egg"
  let initial ← PageMap.create path "bitmap-kernel-native-check"
  let a := [0,255,256,4095,4096,65535,65536,1000000]
  let b := [0,2,256,4096,900000,1000001]
  let ((left,right,removed),head,_) ← PageMap.withWriter initial fun writer => do
    let mut left := none
    for id in a do left ← SourceBitmap.set writer left id true
    let mut right := none
    for id in b do right ← SourceBitmap.set writer right id true
    let mut removed := left
    for id in [0,65535,1000000] do removed ← SourceBitmap.set writer removed id false
    return (left,right,removed)
  let snapshot ← PageMap.pin path
  check (snapshot.head == head) "bitmap writer did not publish"
  let reader ← SourceBitmap.Reader.new snapshot
  let members := fun ref => match ref with
    | none => pure []
    | some ref => reader.members ref.height ref
  check ((← members left) == a && (← members right) == b) "sparse bitmap crossed block or height boundary"
  check ((← members removed) == a.filter (fun id => ![0,65535,1000000].contains id)) "bitmap retraction changed another bit"
  let joined ← reader.union left right
  let expected := (hashDistinct (a++b)).mergeSort (· < ·)
  check ((← members joined) == expected && joined.map (·.count) == some expected.length)
    "bitmap union lost or double counted a member"
  let before ← reader.reads.get
  check ((← reader.union left right) == joined && (← reader.reads.get) == before) "unchanged join did not reuse memo"
  check ((← reader.union right left) == joined) "reversed union missed symmetric memo"
  check ((← reader.union left left) == left) "equal immutable roots were reconstructed"
  check ((← PageMap.pin path).head == head) "bitmap query wrote derived state"
  return Json.mkObj [("sparseAddressLimitTested",toJson (1000001 : Nat)),
    ("cardinalityAndRetractionExact",toJson true),("unchangedAndReverseJoinsReuseMemo",toJson true)]

def run (root : System.FilePath) (sourceCount : Nat) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists) && [2,16,80].contains sourceCount) "fresh controlled fixture required"
  FileSystem.privateDirectory root
  let bitmapReport ← bitmap root
  let _ ← PageMap.create (root/"dictionary.egg") "shared-authorized-source-owner-dictionary"
  let emptyPath ← source root 1000 0
  let (empty,_) ← prepare root emptyPath
  check ((← readerFor #[empty]).counts == (0,0)) "actually empty prepared source rejected"
  let coldPath ← source root 1001 1
  let coldIndex ← PageMap.create (root/"cold-index.egg") "individual-source-owner-index"
  let mut coldRejected := false
  try
    let _ ← SourceOwners.prepare (root/"dictionary.egg") coldIndex (← PageMap.pin coldPath) "project/authorized-scope"
  catch _ => coldRejected := true
  check coldRejected "missing individual preparation became a successful empty domain"
  let a ← source root 0 2
  let b ← source root 1 2
  let (a0,a0Report) ← prepare root a
  let (b0,b0Report) ← prepare root b
  let forkPath := root/"forked-a.egg"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",a.toString,forkPath.toString]}
  check (copied.exitCode == 0) "controlled fork copy failed"
  let initial ← audit #[a0,b0]
  revise a 0 [2] []
  let (a1,a1Report) ← prepare root a
  revise b 1 [2] []
  let (b1,b1Report) ← prepare root b
  revise forkPath 0 [99] []
  let forkSource ← PageMap.pin forkPath
  let _ ← RetrievalResearch.Index.warm forkSource .database
  let forkIndex ← PageMap.create (root/"fork-index.egg") "individual-source-owner-index"
  let mut forkRejected := false
  try
    let _ ← SourceOwners.prepare (root/"dictionary.egg") forkIndex forkSource "project/authorized-scope"
  catch error =>
    forkRejected := error.toString.endsWith "original owner alias diverged; a fork requires a distinct source incarnation"
  check forkRejected "forked original with the same local number reused unrelated identity"
  let foreignDictionary := root/"foreign-dictionary.egg"
  let _ ← PageMap.create foreignDictionary "shared-authorized-source-owner-dictionary"
  let foreignIndex ← PageMap.create (root/"foreign-index.egg") "individual-source-owner-index"
  let foreign ← SourceOwners.prepare foreignDictionary foreignIndex (← PageMap.pin b) "project/authorized-scope"
  check ((← SourceOwners.open? #[a0,foreign.captured] "project/authorized-scope").isNone)
    "foreign dictionary ids combined despite incompatible namespace"
  let mut cuts := #[]
  for captured in [#[a0,b0],#[a1,b0],#[a1,b1],#[a0,b1]] do cuts := cuts.push (← audit captured)
  let mixed ← readerFor #[a0,b1]
  let some bSource := mixed.inputs[1]? | throw (IO.userError "mixed B absent")
  let some newB ← findNode? bSource.original (value 1 2) | throw (IO.userError "new B original absent")
  check ((← mixed.owner? 1 newB).isSome) "mixed cut lost new B"
  let oldA := (← SourceOwners.restore a0.state.source)
  let some newA ← findNode? (← PageMap.pin a) (value 0 2) | throw (IO.userError "new A original absent")
  check ((← mixed.owner? 0 newA).isNone) "new dictionary added a future member to old A"
  check ((← SourceOwners.open? #[a0,b1] "foreign/scope").isNone) "foreign namespace admitted"
  let forged := {a0 with state := {a0.state with source := a1.state.source}}
  check ((← SourceOwners.open? #[forged,b1] "project/authorized-scope").isNone) "forged individual readiness admitted"
  let physicalBefore := (← PageMap.pin (.mk a1.index.directory)).head
  let reused ← SourceOwners.prepare (root/"dictionary.egg") (← PageMap.pin (.mk a1.index.directory)) oldA "project/authorized-scope"
  check (reused.captured.index.head == a0.index.head && reused.captured.state.source.head == a0.state.source.head &&
    reused.changedOwners == 0 && reused.publications == 0 && reused.mode == "unchanged")
    "completed historical source was not reused exactly"
  check ((← PageMap.pin (.mk a1.index.directory)).head == physicalBefore)
    "historical preparation rolled back the current physical workspace"
  let (unchanged,unchangedReport) ← prepare root a
  check (unchanged.index.head == a1.index.head) "unchanged source was republished"
  let mut paths := #[a,b]
  let mut captured := #[a1,b1]
  for lane in [2:sourceCount] do
    let path ← source root lane 2
    let (ready,_) ← prepare root path
    paths := paths.push path
    captured := captured.push ready
  let complete ← audit captured
  let reordered ← audit captured.reverse
  -- Parallel original append owners, with reads pinned to the older cut.
  -- Dictionary/index preparation is deliberately measured separately below.
  let parallelStarted ← IO.monoMsNow
  let tasks ← paths.zipIdx |>.mapM fun (path,lane) => IO.asTask (do
    let beginMs ← IO.monoMsNow
    revise path lane [3] []
    let endMs ← IO.monoMsNow
    return (beginMs,endMs,(← PageMap.pin path).head)) .dedicated
  let retainedWhileAppending ← audit #[a0,b1] false
  let mut intervals := #[]
  for task in tasks do
    match ← IO.wait task with
    | .error error => throw error
    | .ok receipt => intervals := intervals.push receipt
  let parallelMs := (← IO.monoMsNow)-parallelStarted
  let peakOverlap := intervals.foldl (fun peak row => max peak
    (intervals.filter (fun other => other.1 ≤ row.1 && row.1 < other.2.1)).size) 0
  let mut deltaReports := #[]
  for lane in [:paths.size] do
    let some path := paths[lane]? | throw (IO.userError "parallel source missing")
    let some receipt := intervals[lane]? | throw (IO.userError "parallel receipt missing")
    check ((← PageMap.pin path).head == receipt.2.2) "acknowledged original head lost"
    let (updated,delta) ← prepare root path
    check (delta.getObjValD "mode" == toJson "publication-delta" &&
      delta.getObjValD "changedOwners" == toJson (1 : Nat)) "one append rebuilt another source or all owners"
    captured := captured.set! lane updated
    deltaReports := deltaReports.push delta
  let afterParallel ← audit captured
  let current ← readerFor captured
  let some sharedNode ← findNode? oldA (value 0 0) | throw (IO.userError "shared original absent")
  let some sharedId ← current.owner? 0 sharedNode | throw (IO.userError "shared identity absent")
  for lane in [:sourceCount] do
    let some path := paths[lane]? | throw (IO.userError "source path absent")
    revise path lane [] [0]
    let (updated,_) ← prepare root path
    captured := captured.set! lane updated
    if lane == 0 then
      let reader ← readerFor captured
      check ((← reader.frequency "shared0") == 1) "removing first source destroyed another source's posting"
  let lastRemoved ← audit captured
  check ((← (← readerFor captured).frequency "shared0") == 0) "final source copy left live posting"
  revise b 1 [0] []
  let (reinserted,reinsertReport) ← prepare root b
  captured := captured.set! 1 reinserted
  let inserted ← readerFor captured
  let some original ← findNode? (← PageMap.pin b) (value 1 0) | throw (IO.userError "reinserted original absent")
  check ((← inserted.owner? 1 original) == some sharedId) "reinsertion changed structural identity"
  let originals ← inserted.originals sharedId
  check (originals.length == 1 && originals.head?.map (·.ordinal) ==
    some (← getNat (← PageMap.pin b).get (key "member" original))) "reinsertion retained stale ordinals"
  for lane in [:2] do
    let some path := paths[lane]? | throw (IO.userError "variant path absent")
    let source ← PageMap.pin path
    let _ ← PageMap.withWriter source fun writer => do
      let intern : Intern := ⟨writer,← IO.mkRef {}⟩
      let added ← [variant lane false,variant lane true].mapM intern.root
      writeChange writer {added,removed := [],unionsChanged := false}
    let (updated,_) ← prepare root path
    captured := captured.set! lane updated
  let variants ← audit captured
  let retained ← audit #[a0,b1]
  IO.FS.writeFile (root/"captured.json") ((toJson (#[a0,b1],captured)).pretty++"\n")
  let report := Json.mkObj [("sources",toJson sourceCount),("bitmap",bitmapReport),
    ("initial",initial),("individualPreparations",toJson #[a0Report,b0Report,a1Report,b1Report]),
    ("allFourIndependentCuts",toJson cuts),("newSources",complete),("reorderedSources",reordered),
    ("emptySourceAcceptedAndMissingPreparationRejected",toJson true),
    ("foreignDictionaryRejected",toJson true),("lastCopyRemoved",lastRemoved),
    ("historicalRootReusedWithoutPhysicalRollback",toJson true),
    ("divergentOriginalIncarnationRejected",toJson true),
    ("parallelOriginals",Json.mkObj [("count",toJson sourceCount),("elapsedMs",toJson parallelMs),
      ("peakAppendIntervalOverlap",toJson peakOverlap),("retainedWhileAppending",retainedWhileAppending),
      ("allAcknowledgedHeadsRetained",toJson true),("afterPreparation",afterParallel),
      ("individualDeltas",toJson deltaReports)]),
    ("reinserted",reinsertReport),("structuredAndExactVariants",variants),("retainedMixedCut",retained),
    ("unchanged",unchangedReport),("wholeTupleReadyRequired",toJson false),
    ("parallelCapacityTested",toJson false),("normalHookIntegrated",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

def reopen (root : System.FilePath) : IO Unit := do
  let (mixed,latest) ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured.json")) >>=
    fromJson? (α := Array SourceOwners.Captured × Array SourceOwners.Captured))
  let report := Json.mkObj [("freshProcessMixedCut",← audit mixed),("freshProcessLatest",← audit latest)]
  IO.FS.writeFile (root/"reopen.json") (report.pretty++"\n")
  IO.println report.compress

end Eggshell.Research.SourceOwnerChecks

#print axioms Eggshell.SourceBitmap.unite_member
#print axioms Eggshell.SourceBitmap.unite_idempotent
#print axioms Eggshell.SourceBitmap.unite_associative

def main (args : List String) : IO UInt32 := do
  match args with
  | ["source-owners",root,count] =>
    let some count := count.toNat? | throw (IO.userError "count required")
    Eggshell.Research.SourceOwnerChecks.run (.mk root) count
    pure 0
  | ["reopen-source-owners",root] =>
    Eggshell.Research.SourceOwnerChecks.reopen (.mk root)
    pure 0
  | _ => throw (IO.userError "source-owners or reopen-source-owners required")
