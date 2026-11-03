import tools.research.PreparationDrainChecks

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.DB Eggshell.Persistence.Store

namespace Eggshell.Research.OriginalFeedChecks

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def event (lane : String) (n : Nat) : Journal.Entry :=
  ⟨⟨Sha256.hex "original-feed-fixture".toUTF8,n⟩,
    .finish ⟨lane,"turn",toString n⟩ "mcp__fixture__read" (toJson n).compress
      (Json.mkObj [("lane",toJson lane),("evidence",toJson n)]).compress none,none⟩

private def journal (source : PageMap.Snapshot) : IO PageMap.Snapshot := do
  let some found ← Journal.open? source | throw (IO.userError "missing fixture journal")
  return found

/-- Independent oracle: scan the mixed journal, filter references, decode bodies.
It never derives membership from the new feed or its inverse postings. -/
private def oracle (source : PageMap.Snapshot) : IO (Array (Nat × Journal.Entry)) := do
  let saved ← journal source
  let mut rows := #[]
  for ordinal in [: (← getNat saved.get "count")] do
    if (← saved.get (Journal.referenceKey ordinal)).isNone then
      rows := rows.push (ordinal,← Journal.rawEntry saved ordinal)
  return rows

private def verify (source : PageMap.Snapshot) : IO Json := do
  let saved ← journal source
  let full ← oracle source
  let feed ← Journal.originalFeed saved
  check (feed.count == full.size) "sparse original count differs from full mixed scan"
  for position in [:full.size] do
    let some (expected,value) := full[position]? | throw (IO.userError "full-scan oracle index missing")
    let ordinal ← Journal.originalOrdinal saved position
    check (ordinal == expected) "sparse original order differs from full mixed scan"
    Journal.checkOriginalEntry saved ordinal value
  return Json.mkObj [("mixedRows",toJson (← getNat saved.get "count")),
    ("originalRows",toJson full.size),("fullScanEqual",toJson true)]

private def consume (target source : PageMap.Snapshot) (limit : Nat) : IO Json := do
  let mut total := 0
  let mut rounds := 0
  let mut added := 0
  repeat
    let result ← Journal.importFeed target (Sidecar.Owner.ofSnapshot source) ((← IO.monoMsNow)+10000) limit
    check (result.examined ≤ min 256 limit && result.indirect == 0) "sparse import scanned an alias or exceeded its bound"
    total := total+result.examined
    added := added+result.added
    rounds := rounds+1
    if result.complete then break
    check (result.examined > 0) "sparse import made no progress"
  return Json.mkObj [("examined",toJson total),("added",toJson added),("rounds",toJson rounds)]

private def mutate (saved : PageMap.Snapshot) (action : PageMap.Writer → IO Unit) : IO Unit := do
  let (_,_,_) ← PageMap.withWriter saved action
  pure ()

def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute fixture required"
  FileSystem.privateDirectory root
  let a ← PageMap.create (root/"a.egg") "original-a"
  let b ← PageMap.create (root/"b.egg") "original-b"
  let c ← PageMap.create (root/"c.egg") "original-c"
  let _ ← Journal.prepare c
  for round in [:8] do
    for offset in [:16] do check (← Journal.append a (event "a" (round*16+offset))) "raw append rejected"
    let _ ← consume b a 17
    for offset in [:3] do check (← Journal.append b (event "b" (round*3+offset))) "interleaved raw append rejected"
  let aAudit ← verify a
  let bAudit ← verify b
  let full ← oracle b
  let before ← journal b
  for (_,value) in full do check (!(← Journal.append b value)) "identical retry created another original"
  check ((← journal b).head == before.head) "identical retry changed journal head"
  let imported ← consume c b 7
  check (imported.getObjValD "examined" == toJson (24 : Nat)) "sparse importer did not examine every original exactly once"
  let cSaved ← journal c
  check ((← getNat cSaved.get "count") == 24 && (← Journal.originalFeed cSaved).count == 0)
    "reference import advanced original-only count or lost evidence"
  for position in [:full.size] do
    let some (_,value) := full[position]? | throw (IO.userError "full-scan original absent")
    check ((← Journal.entry cSaved position) == value) "reference projection changed original body"
  let aliasesOnly ← consume a c 7
  check (aliasesOnly.getObjValD "examined" == toJson (0 : Nat) &&
      !(← Journal.feedRequired a (Sidecar.Owner.ofSnapshot c))) "an alias-only producer created downstream work"
  -- An alias-only upstream append must not create debt for downstream readers.
  check (← Journal.append a (event "a" 999)) "later upstream original rejected"
  let unchanged := (← Journal.originalFeed (← journal b))
  let _ ← consume b a 7
  check ((← journal b).head != before.head && (← Journal.originalFeed (← journal b)) == unchanged)
    "alias import advanced the original-only frontier"
  check (!(← Journal.feedRequired c (Sidecar.Owner.ofSnapshot b))) "alias-only change recreated downstream debt"
  let idle ← Journal.importFeed c (Sidecar.Owner.ofSnapshot b) ((← IO.monoMsNow)+10000) 7
  check (idle.complete && idle.examined == 0) "unchanged original frontier was rescanned"
  -- A failing transaction must publish neither the raw event nor its posting.
  let preAbort ← journal b
  check (← rejected (PageMap.withWriter preAbort fun writer => do
    let _ ← Journal.stageEntry preAbort writer (event "aborted" 0) .original
    throw (IO.userError "controlled transaction abort") : IO (Unit × PageMap.Head × Nat)))
    "fixture transaction unexpectedly committed"
  check ((← journal b).head == preAbort.head) "aborted append published a feed or body"
  for n in [:4] do check (← Journal.append b (event "later-b" n)) "later native event rejected"
  let pending ← journal b
  let cBefore := (← journal c).head
  let expired ← Journal.importFeed c (Sidecar.Owner.ofSnapshot b) (← IO.monoMsNow) 7
  let zero ← Journal.importFeed c (Sidecar.Owner.ofSnapshot b) ((← IO.monoMsNow)+10000) 0
  check (expired.examined == 0 && zero.examined == 0 && (← journal c).head == cBefore)
    "expired or zero-budget import changed the cursor"
  -- Corrupt only current metadata. A retained pin and its original bytes survive.
  let postKey := Journal.originalKey 24
  let some rawPosting ← pending.get postKey | throw (IO.userError "new original posting absent")
  mutate pending (fun writer => writer.put postKey none)
  check (← rejected (Journal.importFeed c (Sidecar.Owner.ofSnapshot b) ((← IO.monoMsNow)+10000) 7))
    "original posting hole was accepted"
  mutate (← journal b) (fun writer => writer.put postKey (some rawPosting))
  mutate (← journal b) (fun writer => putNat writer postKey 0)
  check (← rejected (Journal.importFeed c (Sidecar.Owner.ofSnapshot b) ((← IO.monoMsNow)+10000) 7))
    "an original posting naming an alias was accepted"
  mutate (← journal b) (fun writer => writer.put postKey (some rawPosting))
  let latest ← journal b
  let ordinal ← Journal.originalOrdinal latest 24
  let inverse := Journal.originalPositionKey ordinal
  let some inverseBytes ← latest.get inverse | throw (IO.userError "inverse missing")
  mutate latest (fun writer => putNat writer inverse 0)
  check (← rejected (Journal.importFeed c (Sidecar.Owner.ofSnapshot b) ((← IO.monoMsNow)+10000) 7))
    "wrong original inverse was accepted"
  mutate (← journal b) (fun writer => writer.put inverse (some inverseBytes))
  check ((← Journal.originalOrdinal pending 24) == ordinal) "metadata corruption changed retained old pin"
  let cursorKey := Journal.importKey (Sidecar.Owner.ofSnapshot b)
  let target ← journal c
  let some cursorBytes ← target.get cursorKey | throw (IO.userError "no retained cursor")
  let cursor ← Index.decode (α := Journal.ImportCursor) cursorBytes
  mutate target (fun writer => writer.put cursorKey (some (toJson {cursor with next := cursor.basis.count+1}).compress.toUTF8))
  check (← rejected (Journal.feedRequired c (Sidecar.Owner.ofSnapshot b))) "cursor beyond original basis was accepted"
  mutate (← journal c) (fun writer => writer.put cursorKey (some (toJson {cursor with journal := {cursor.journal with identity := Sha256.hex "foreign".toUTF8}}).compress.toUTF8))
  check (← rejected (Journal.importFeed c (Sidecar.Owner.ofSnapshot b) ((← IO.monoMsNow)+10000) 7))
    "foreign original prefix was accepted"
  mutate (← journal c) (fun writer => writer.put cursorKey (some (toJson {cursor with journal := {cursor.journal with revision := cursor.journal.revision+1000}}).compress.toUTF8))
  check (← rejected (Journal.importFeed c (Sidecar.Owner.ofSnapshot b) ((← IO.monoMsNow)+10000) 7))
    "unretained original prefix was accepted"
  mutate (← journal c) (fun writer => writer.put cursorKey (some (toJson {cursor with basis := {cursor.basis with chain := Sha256.hex "changed-basis".toUTF8}}).compress.toUTF8))
  check (← rejected (Journal.feedRequired c (Sidecar.Owner.ofSnapshot b))) "changed retained original basis was accepted"
  mutate (← journal c) (fun writer => writer.put cursorKey (some cursorBytes))
  let progress ← Journal.importFeed c (Sidecar.Owner.ofSnapshot b) ((← IO.monoMsNow)+10000) 2
  check (progress.examined == 2 && !progress.complete) "partial import failed to preserve remaining debt"
  let resumed ← IO.Process.output {cmd := (← IO.appPath).toString,args := #["resume-original-feed",root.toString]}
  check (resumed.exitCode == 0) ("fresh-process cursor recovery failed: "++resumed.stderr)
  let restart ← IO.ofExcept (Json.parse resumed.stdout)
  let unsupported ← PageMap.create (root/"unsupported.egg") "unsupported-journal"
  mutate (← Journal.prepare unsupported) (fun writer => putNat writer "count" 1)
  check (← rejected (Journal.originalFeed (← journal unsupported)))
    "nonempty journal without original feed was silently treated as empty"
  let result := Json.mkObj [("allPassed",toJson true),("a",aAudit),("b",bAudit),
    ("firstImport",imported),("restart",restart),("aliasOnlyDebt",toJson false),
    ("duplicateAndAbortPreserveHead",toJson true),("holesAndWrongInverseRejected",toJson true),
    ("foreignAndOutOfRangeCursorRejected",toJson true),("expiredAndZeroBudgetUnchanged",toJson true),
    ("unretainedPrefixAndChangedBasisRejected",toJson true),
    ("aliasPostingAndUnsupportedJournalRejected",toJson true),
    ("retainedPinUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("notCapacityOrTokenEvidence",toJson true)]
  IO.FS.writeFile (root/"report.json") (result.pretty++"\n")
  IO.println result.compress

def resumeRun (root : System.FilePath) : IO Unit := do
  let b ← PageMap.pin (root/"b.egg")
  let c ← PageMap.pin (root/"c.egg")
  let imported ← consume c b 2
  check (imported.getObjValD "examined" == toJson (2 : Nat)) "resumed cursor skipped or repeated originals"
  check (!(← Journal.feedRequired c (Sidecar.Owner.ofSnapshot b))) "resumed importer retained completed debt"
  let full ← oracle b
  let saved ← journal c
  check ((← getNat saved.get "count") == full.size) "restarted import count differs from full scan"
  for position in [:full.size] do
    let some (_,value) := full[position]? | throw (IO.userError "restarted oracle original absent")
    check ((← Journal.entry saved position) == value) "restarted import body differs from full scan"
  IO.println (Json.mkObj [("import",imported),("source",← verify b),
    ("bodyAndOrderMatchFullScan",toJson true)]).compress

end Eggshell.Research.OriginalFeedChecks

#print axioms Eggshell.OriginalEventIndex.append_matches_full_scan
#print axioms Eggshell.OriginalEventIndex.alias_preserves_originals
#print axioms Eggshell.OriginalEventIndex.next_matches_full_scan

def main (args : List String) : IO UInt32 := do
  match args with
  | ["original-feed",root] => Eggshell.Research.OriginalFeedChecks.run (.mk root); return 0
  | ["resume-original-feed",root] => Eggshell.Research.OriginalFeedChecks.resumeRun (.mk root); return 0
  | other => preparationDrainMain other
