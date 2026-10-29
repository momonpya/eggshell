module
import all Eggshell.SynapseJournal
public meta import Lean
open Lean Eggshell Eggshell.DB Eggshell.Synapses

#print axioms Index.Opening.available_iff_no_reason

run_meta do
  let environment ← getEnv
  let mut pending := [``Index.inspect]
  let mut seen : Std.HashSet Name := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    let some declaration := environment.find? name | throwError "missing index opening boundary {name}"
    if let some body := declaration.value? then
      for dependency in body.getUsedConstants do
        if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
  for forbidden in #[``DB.PageMap.withWriter,``Index.prepare,``Sidecar.prepare,``Matcher.localUnion?] do
    if seen.contains forbidden then throwError "index inspection reaches {forbidden}"
  logInfo "Index inspection reaches no DB preparation, publication or Union"

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def requireReason (source : DB.PageMap.Snapshot) (storage : Sidecar.Storage)
    (scope : Index.Scope) (expected : Index.Unavailability) : IO Unit := do
  let result ← Index.inspect source storage scope
  check (result.reason? == some expected && result.reader?.isNone) "index rejection lost its exact reason"

public def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "new isolated output required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists) && (← Paths.dataRoot) == output / "private") "fresh private fixture root required"
  IO.FS.createDir output
  let source ← DB.PageMap.create (output / "fixture.egg") "index-readiness-fixture"
  let indexPath ← Index.directory source .database .shared
  let userPath ← Index.directory source .user .shared
  let absent ← Journal.knowledge source [] false
  check (absent.indexed.isNone && absent.indexUnavailable ==
    #[(Sidecar.Storage.database,Index.Unavailability.missingIndex),(.user,.missingIndex)])
    "start failed to record both missing indexes"
  check (!(← indexPath.pathExists) && !(← userPath.pathExists)) "readiness inspection created an index"
  requireReason source .database .usage .privateDestination
  let empty ← Index.prepare source .database .shared
  requireReason source .database .shared (.missingManifest empty.head)
  let _ ← Index.replace source .database .shared #[]
  let some ready ← Index.open? source .database .shared | throw (IO.userError "ready fixture was rejected")
  let originalMetadata := ready.manifest
  let originalProvenance := (toJson (← Provenance.stamp source)).compress.toUTF8
  let write := fun (metadata : Index.Manifest) (provenance : ByteArray) => do
    let index ← DB.PageMap.pin indexPath
    let _ ← DB.PageMap.withWriter index fun writer => do
      writer.put "manifest" (some (toJson metadata).compress.toUTF8)
      writer.put "provenance" (some provenance)
    pure ()
  let foreignProducer := String.ofList (List.replicate 64 'f')
  write {originalMetadata with implementation := foreignProducer} originalProvenance
  requireReason source .database .shared (.implementationMismatch foreignProducer)
  write {originalMetadata with scope := .usage} originalProvenance
  requireReason source .database .shared (.scopeMismatch .usage)
  write originalMetadata "different-provenance".toUTF8
  requireReason source .database .shared .provenanceMismatch
  let foreignSource := {source.head with identity := String.ofList (List.replicate 64 'a')}
  write {originalMetadata with source := foreignSource} originalProvenance
  requireReason source .database .shared (.sourceNotCovered foreignSource)
  let rejected ← Journal.knowledge source [] false
  check (rejected.indexed.isNone && rejected.indexUnavailable ==
    #[(Sidecar.Storage.database,Index.Unavailability.sourceNotCovered foreignSource),(.user,.missingIndex)])
    "start conflated a rejected index with a missing index"
  let occurrence : Occurrence := ⟨"readiness-session","readiness-turn","readiness-use"⟩
  let entry : Journal.Entry := {
    clock := ⟨String.ofList (List.replicate 64 'b'),1⟩
    payload := .start occurrence "observed-work" (Sha256.hex "original question".toUTF8) rejected}
  check (← Journal.append source entry) "new start did not persist"
  write originalMetadata originalProvenance
  let readyStart ← Journal.knowledge source [] false
  check (readyStart.indexed.isSome && readyStart.indexUnavailable.isEmpty) "ready index retained a false rejection"
  let beforeHead := (← DB.PageMap.pin indexPath).head
  let _ ← Journal.knowledge source [] false
  check ((← DB.PageMap.pin indexPath).head == beforeHead) "a readiness check rewrote its index"
  let retry : Journal.Entry := {entry with
    payload := .start occurrence "observed-work" (Sha256.hex "original question".toUTF8) readyStart}
  check (!(← Journal.append source retry))
    "identical retry replaced the first observation"
  let recorded ← Journal.prepare source
  check ((← Journal.entry recorded 0) == entry) "retry or readiness transition changed the durable rejection reason"
  let broken ← DB.PageMap.pin indexPath
  let _ ← DB.PageMap.withWriter broken fun writer => writer.put "manifest" (some "not JSON".toUTF8)
  let decodeFailed ← try
      let _ ← Index.inspect source .database .shared
      pure false
    catch _ => pure true
  check decodeFailed "corrupt metadata was disguised as an absent index"
  write originalMetadata originalProvenance
  check ((← DB.PageMap.pin source.directory).head == source.head) "inspection or diagnostics changed the source DB"
  let _ ← DB.PageMap.withWriter source fun writer => do
    writer.put "fixture-source-update" (some "new-original-publication".toUTF8)
    Persistence.Store.writeChange writer {added := [],removed := [],unionsChanged := true}
  let advanced ← DB.PageMap.pin source.directory
  requireReason advanced .database .shared (.sourceNotCovered source.head)
  check ((← Index.inspect source .database .shared).reader?.isSome)
    "a new publication invalidated the old immutable reader"
  let lagged ← Journal.knowledge advanced [] false
  check (lagged.indexed.isNone && lagged.indexUnavailable ==
    #[(Sidecar.Storage.database,Index.Unavailability.sourceNotCovered source.head),(.user,.missingIndex)])
    "publication debt was not distinguishable from no persisted index"
  let _ ← Index.replace advanced .database .shared #[]
  check ((← Index.inspect advanced .database .shared).reader?.isSome)
    "refresh did not resolve the observed source frontier gap"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let originalSource ← DB.PageMap.pin (study / "study/seed-2/work.egg")
  let originalJournal ← DB.PageMap.pin (study / "study/seed-2/data/read-cache" /
    System.FilePath.mk originalSource.head.identity / "synapses/events")
  let count ← Persistence.Store.getNat originalJournal.get "count"
  let mut starts := 0
  let mut captured := 0
  for ordinal in [:count] do
    let old ← Journal.entry originalJournal ordinal
    match old.payload with
    | .start _ _ _ known =>
      starts := starts+1
      if known.indexed.isSome then captured := captured+1
      check known.indexUnavailable.isEmpty "a historical cause was fabricated"
    | _ => pure ()
  check (count == 75 && starts == 37 && captured == 5) "original journal census changed"
  check ((← DB.PageMap.pin originalSource.directory).head == originalSource.head &&
    (← DB.PageMap.pin originalJournal.directory).head == originalJournal.head) "diagnostic read changed original data"
  let report := Json.mkObj [("rejectionReasonsChecked",toJson (7 : Nat)),
    ("missingAndRejectedDistinguished",toJson true),("inspectionCreatesNothing",toJson true),
    ("firstObservedReasonSurvivesRetry",toJson true),("readyTransitionDoesNotRewriteHistory",toJson true),
    ("corruptMetadataRemainsError",toJson true),("sourceUnchanged",toJson true),
    ("sourceAdvanceRejectsCurrentView",toJson true),("oldImmutablePinRemainsReadable",toJson true),
    ("explicitRefreshClosesFrontierGap",toJson true),
    ("historicalEntriesCanonicallyReadable",toJson count),("historicalStarts",toJson starts),
    ("historicalCapturedIndexes",toJson captured),("historicalReasonsInvented",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") report.pretty
  IO.println report.compress
