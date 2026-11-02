import Eggshell.SynapticTransport
import Eggshell.UsageCache
import Eggshell.SynapseBuild
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.Synapses

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def routed (source : DB.PageMap.Snapshot) (shared : Index.Reader) (usage : Option Index.Reader)
    (answers : Array (String × Nat)) : IO Routed.Result := do
  Routed.collect {source,shared := some shared,usage} answers (Sha256.hex "empty-routing".toUTF8)
    ((← IO.monoMsNow)+30000) #[]

def main (args : List String) : IO Unit := do
  let [original,directory] := args | throw (IO.userError "FIXED-SOURCE NEW-PRIVATE-ROOT")
  let root := System.FilePath.mk directory
  check (!(← root.pathExists)) "preserve prior routing checks"
  IO.FS.createDirAll root
  let empty ← Persistence.ensureSnapshot (root / "empty-source.egg")
  let _ ← Index.publishDelta empty .user .shared none {added := #[],removed := #[]}
  let some shared ← Index.open? empty .user .shared | throw (IO.userError "empty shared index did not publish")
  let some sharedRoute ← Routing.Store.open? shared | throw (IO.userError "initialized empty shared routing is unprepared")
  let usage ← UsageCache.ensure empty
  let some usageRoute ← Routing.Store.open? usage | throw (IO.userError "initialized empty private routing is unprepared")
  check (sharedRoute.manifest.counts.facts == 0 && usageRoute.manifest.counts.facts == 0 &&
    usageRoute.manifest.counts.nodes == 0 && usageRoute.manifest.counts.targets == 0)
    "fresh empty routing has phantom facts or handles"
  let result ← routed empty shared (some usage) #[]
  check (result.complete && result.failure.isNone && result.hints.isEmpty) "certified empty scope did not finish empty"
  let (_,head,_) ← DB.PageMap.withWriter usage.index fun writer => writer.put "route:counts" none
  let broken : Index.Reader := ⟨{usage.index with head},usage.manifest⟩
  check (← Routing.Store.open? broken <&> (·.isNone)) "missing counters were accepted as a complete empty scope"
  let result ← routed empty shared (some broken) #[]
  check (!result.complete && result.failure.isSome && result.admitted.isEmpty)
    "unprepared private metadata acquired a false empty result"
  let rejected ← try
    let _ ← DB.PageMap.withWriter broken.index fun writer => Routing.Store.finish writer 1
    pure false
    catch _ => pure true
  check (rejected && (← DB.PageMap.pin broken.index.directory).head == broken.index.head)
    "mismatched expected count committed routing readiness"
  let aborted ← try
    let _ ← DB.PageMap.withWriter broken.index fun writer => do
      Routing.Store.finish writer 0
      (throw (IO.userError "abort after staging empty readiness") : IO Unit)
    pure false
    catch _ => pure true
  check (aborted && (← DB.PageMap.pin broken.index.directory).head == broken.index.head)
    "aborted zero-count staging leaked a visible publication"
  let (_,head,_) ← DB.PageMap.withWriter broken.index fun writer => Routing.Store.finish writer 0
  let repaired : Index.Reader := ⟨{broken.index with head},broken.manifest⟩
  check (← Routing.Store.open? repaired <&> (·.isSome)) "explicit empty staging could not restore its missing extent"
  let source ← DB.PageMap.pin (.mk original)
  let _ ← Build.refresh source .user
  let some shared ← Index.open? source .user .shared | throw (IO.userError "real source routing did not prepare")
  let facts ← Index.allFacts shared.index
  let answers : Array (String × Nat) := (facts.filterMap fun fact => match fact with
    | .supports support => some (support.claim.answer,0)
    | _ => none) |>.foldl (fun found row => if found.contains row then found else found.push row) #[]
  check (!answers.isEmpty) "real source has no citation roots for the shared graph"
  let usage ← UsageCache.ensure source
  let baseline ← routed source shared none answers
  let combined ← routed source shared (some usage) answers
  check (baseline.complete && combined.complete && !baseline.hints.isEmpty &&
    (baseline.hints.map Routing.Store.Hint.json) == (combined.hints.map Routing.Store.Hint.json))
    "an empty private overlay suppressed or changed real shared synaptic hints"
  let foreign ← routed source shared (some repaired) answers
  check (!foreign.complete && foreign.failure.isSome) "an empty foreign project crossed its scope"
  let _ ← Index.publishDelta source .user .shared (some source.head) {added := #[],removed := facts}
  let some retired ← Index.open? source .user .shared | throw (IO.userError "fully retired index did not publish")
  let some retiredRoute ← Routing.Store.open? retired | throw (IO.userError "zero live facts lost routing readiness")
  let result ← routed source retired (some usage) answers
  check (retiredRoute.manifest.counts.facts == 0 && retiredRoute.manifest.counts.arcs == 0 &&
    retiredRoute.manifest.counts.nodes > 0 && result.complete && result.hints.isEmpty)
    "retiring all facts reset allocated handles or retained live hints"
  let old ← routed source shared none answers
  check (old.complete && (old.hints.map Routing.Store.Hint.json) == (baseline.hints.map Routing.Store.Hint.json))
    "retirement changed a previously pinned routing snapshot"
  let report := Json.mkObj [("freshSharedAndPrivateEmptyReady",toJson true),
    ("missingCountRejected",toJson true),("mismatchedCountRejected",toJson rejected),
    ("abortDidNotPublish",toJson aborted),("explicitEmptyRestored",toJson true),
    ("realSourceFacts",toJson facts.size),("sharedCitationRoots",toJson answers.size),
    ("sharedHintsWithNoPrivateOverlay",toJson baseline.hints.size),
    ("sharedHintsWithEmptyPrivateOverlay",toJson combined.hints.size),
    ("orderedHintsEqual",toJson true),("foreignScopeRejected",toJson true),
    ("allFactsRetiredReady",toJson true),("oldPinUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress
