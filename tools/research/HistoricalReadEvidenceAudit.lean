module
import all Eggshell.SynapseJournal
public meta import Lean
open Lean Eggshell Eggshell.Synapses

#print axioms StoredReadEvidence.Witness.original_member
#print axioms StoredReadEvidence.Witness.same_source
#print axioms StoredReadEvidence.Witness.same_binding
#print axioms StoredReadEvidence.Witness.same_occurrence

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Journal.indexAt?,#[``Journal.originalAt?,``Index.sameSources,``Provenance.stamp],
        #[``Index.implementation,``DB.PageMap.withWriter]),
      (``Journal.storedReadsAt?,#[``StoredReadEvidence.Prepared.check?,``Journal.originalAt?],
        #[``DB.PageMap.withWriter,``Journal.append,``SourceEvidence.capture]),
      (``Journal.replay,#[``Journal.storedReadsAt?],#[``DB.PageMap.withWriter,``Journal.append]),
      (``Journal.nativeFeedback,#[``Journal.storedReadsAt?],#[``DB.PageMap.withWriter,``Journal.append])] do
    let mut pending := [root]
    let mut seen : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if seen.contains name then continue
      seen := seen.insert name
      let some declaration := environment.find? name | throwError "missing historical boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless seen.contains name do throwError "{root} bypasses {name}"
    for name in forbidden do
      if seen.contains name then throwError "{root} reaches forbidden {name}"
    logInfo m!"Audited historical read boundary {root}"

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

public def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "new report required")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve previous historical-read evidence"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  check ((← Paths.dataRoot) == study / "study/seed-2/data") "audit needs original private metadata"
  let source ← DB.PageMap.pin (study / "study/seed-2/work.egg")
  let frozen ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  check (source.head == frozen.head) "source changed from the frozen publication"
  let some journal ← Journal.open? source | throw (IO.userError "raw journal missing")
  let latest ← DB.PageMap.pin (← Index.directory source .database .shared)
  let latestFacts ← Index.allFacts latest
  let wrong := String.ofList (List.replicate 64 'f')
  let mut accepted := 0
  let mut rejected := 0
  let mut pins := 0
  let mut futureRejected := 0
  for ordinal in List.range (← Persistence.Store.getNat journal.get "count") do
    let entry ← Journal.entry journal ordinal
    let .start _ _ _ known := entry.payload | continue
    let some saved := known.indexed | continue
    let some indexed ← Journal.indexAt? source known | throw (IO.userError "retained historical index was rejected")
    check (saved.producer != Index.implementation) "fixture no longer exercises a historical producer"
    pins := pins+1
    let some original ← Journal.originalAt? source known.source | throw (IO.userError "pre-read publication missing")
    let prepared ← StoredReadEvidence.prepare original indexed.index
    check (← Journal.indexAt? source {known with indexed := some {saved with producer := wrong}}).isNone
      "foreign producer matched the saved manifest"
    check (← Journal.indexAt? source {known with indexed := some {saved with head := {saved.head with identity := wrong}}}).isNone
      "foreign index identity was accepted"
    check (← Journal.indexAt? source {known with source := {known.source with identity := wrong}}).isNone
      "foreign source identity was accepted"
    check (!(Journal.completeKnowledge {known with uncertain := true} true)) "unconfirmed knowledge became complete"
    let mut tested := 0
    for fact in ← Index.allFacts indexed.index do
      let .read candidate := fact | continue
      if tested ≥ 8 then break
      let some _witness ← prepared.check? candidate | continue
      tested := tested+1
      accepted := accepted+1
      let changed : Subject := match candidate.source.subject with
        | .file file => .file {file with fingerprint := wrong}
        | .original value => .original {value with content := wrong}
      let mutations : Array Read := #[
        {candidate with binding := {candidate.binding with first := candidate.binding.first+1}},
        {candidate with binding := {candidate.binding with database := wrong}},
        {candidate with binding := {candidate.binding with owner := "v0"}},
        {candidate with binding := {candidate.binding with work := "v0"}},
        {candidate with occurrence := {candidate.occurrence with useId := candidate.occurrence.useId ++ "-not-saved"}},
        {candidate with source := {candidate.source with subject := changed}}]
      for mutation in mutations do
        check (StoredReadEvidence.core mutation != StoredReadEvidence.core candidate) "mutation did not alter original identity"
        check (← prepared.check? mutation).isNone "changed original binding or identity was accepted"
        rejected := rejected+1
      check (← prepared.check? {candidate with quotations := #[wrong]}).isSome
        "irrelevant quote-digest changes revoked the original read"
    for fact in latestFacts do
      let .read candidate := fact | continue
      if (← Build.ownerId? original candidate.binding.owner).isSome then continue
      check (← prepared.check? candidate).isNone "later publication supplied a pre-read original"
      futureRejected := futureRejected+1
      break
  check (pins == 5 && accepted > 0 && futureRejected > 0) "historical/negative fixture was vacuous"
  check ((← DB.PageMap.pin source.directory).head == source.head &&
    (← DB.PageMap.pin journal.directory).head == journal.head &&
    (← DB.PageMap.pin latest.directory).head == latest.head) "read-only evidence audit changed a publication"
  let report := Json.mkObj [
    ("historicalPinsAccepted",toJson pins),("originalReadsVerified",toJson accepted),
    ("changedReadsRejected",toJson rejected),("futureOwnersRejected",toJson futureRejected),
    ("forgedManifestIdentityRejected",toJson true),("uncertaintyGatePreserved",toJson true),
    ("sourceJournalAndIndexUnchanged",toJson true),("modelCalls",toJson (0 : Nat)),
    ("actualHookCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  IO.println report.compress
