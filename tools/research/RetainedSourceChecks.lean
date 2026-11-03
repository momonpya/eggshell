import tools.research.OriginalFeedChecks
import Eggshell.CanonicalSourceLease

open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Synapses

namespace Eggshell.Research.RetainedSourceChecks
private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)
private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true
private def stats : IO Json := do IO.ofExcept (Json.parse (← Publication.Client.control "stats"))

private def waitFlag (flag : IO.Promise Bool) (deadline : Nat) : IO Bool := do
  repeat
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "fixture synchronization expired")
    if ← flag.isResolved then
      let some value := flag.result?.get | throw (IO.userError "fixture synchronization disappeared")
      return value
    IO.sleep 1
  throw (IO.userError "unreachable fixture wait")

theorem retention_not_memo_identity (reference : Publication.Client.SourceReference) (token : Option String) :
    ({reference with retained := token}).identity = reference.identity := rfl

private def rows (reference : Publication.Client.SourceReference) (owner : String) (deadline : Nat) : IO String := do
  let value ← Publication.Client.sourceRows reference #[owner] deadline
  let stored := value.values.flatMap (·.stored.rows)
  check (!stored.isEmpty) "retained fixture returned no original body"
  return (toJson stored).compress

private def component (source : PageMap.Snapshot) (metadata : CanonicalSource.Cache.Manifest)
    (path : System.FilePath) : IO Json := do
  let originals ← CanonicalSource.Shared.Pool.new
  let pool ← CanonicalSource.Leases.Pool.new originals
  try
    let now ← IO.monoMsNow
    let (token,loaded,_) ← pool.retain "fixture-scope" source path metadata (now+5000) (now+20000)
    let key := loaded.identity
    let borrowers := originals.state.atomically do
      return (← get).entries[key]?.map (·.borrowers) |>.getD 0
    check ((← borrowers) == 1) "retained view did not borrow the charged original cache entry"
    check (← rejected (pool.withHeld token "foreign" source.head metadata (now+10000) (fun _ _ => pure ())))
      "foreign scope accessed a retained root"
    check (← rejected (pool.withHeld token "fixture-scope" {source.head with revision := source.head.revision+1}
      metadata (now+10000) (fun _ _ => pure ()))) "changed source head accessed a retained root"
    check (← rejected (pool.withHeld token "fixture-scope" source.head {metadata with payload := Sha256.hex "foreign".toUTF8}
      (now+10000) (fun _ _ => pure ()))) "changed metadata accessed a retained root"
    -- Synthetic idle cache entries exercise real LRU eviction, not DB ingestion.
    for n in [:140] do
      let pressure := s!"fixture-idle-{n}"
      match ← originals.admit pressure (512*1024) with
      | .start entry =>
        originals.finish pressure entry 0 (.ok {loaded with identity := pressure})
        originals.release pressure entry.serial
      | _ => throw (IO.userError "idle cache pressure did not obtain a distinct entry")
    check ((← borrowers) == 1) "cache eviction lost the retained original charge"
    check ((← originals.stats).getObjValD "evictions" != toJson (0 : Nat)) "fixture did not exercise cache eviction"
    let entered ← IO.Promise.new
    let finish ← IO.Promise.new
    let reader ← IO.asTask (pool.withHeld token "fixture-scope" source.head metadata (now+15000) fun current _ => do
      check (current.identity == key) "retained reader changed original identity"
      entered.resolve true
      let _ ← waitFlag finish (now+15000)
      return true) .dedicated
    try
      let _ ← waitFlag entered (now+10000)
      pool.release token "fixture-scope"
      pool.release token "fixture-scope"
      let during ← pool.stats
      check (during.getObjValD "readers" == toJson (1 : Nat) && (← borrowers) == 1)
        "release decharged a still-running reader"
      check (← rejected (pool.withHeld token "fixture-scope" source.head metadata (now+15000) (fun _ _ => pure ())))
        "released handle admitted a new reader"
    finally finish.resolve true
    check (← IO.ofExcept (← IO.wait reader)) "retained reader did not finish"
    check ((← borrowers) == 0 && (← pool.stats).getObjValD "active" == toJson (0 : Nat))
      "last reader did not release the original cache borrow"
    -- Two handles share one original charge and release independently.
    let start ← IO.monoMsNow
    let (a,_,_) ← pool.retain "fixture-scope" source path metadata (start+1000) (start+2000)
    let (b,_,_) ← pool.retain "fixture-scope" source path metadata (start+1000) (start+2000)
    pool.release a "fixture-scope"
    pool.release a "fixture-scope"
    check ((← borrowers) == 1) "duplicate release consumed another handle's borrow"
    pool.release b "fixture-scope"
    let start ← IO.monoMsNow
    let (liveExpiry,_,_) ← pool.retain "fixture-scope" source path metadata (start+200) (start+300)
    let active ← IO.Promise.new
    let stopped ← IO.Promise.new
    let reading ← IO.asTask (pool.withHeld liveExpiry "fixture-scope" source.head metadata (start+3000) fun _ _ => do
      active.resolve true
      waitFlag stopped (start+3000)) .dedicated
    try
      let _ ← waitFlag active (start+1000)
      IO.sleep 350
      pool.reap
      check ((← borrowers) == 1 && (← pool.stats).getObjValD "active" == toJson (1 : Nat))
        "expiry decharged a still-running reader"
      check (← rejected (pool.withHeld liveExpiry "fixture-scope" source.head metadata (start+3000) (fun _ _ => pure ())))
        "expired handle admitted an additional reader"
    finally stopped.resolve true
    check (← IO.ofExcept (← IO.wait reading)) "expired original reader did not finish"
    check ((← borrowers) == 0) "expired last reader retained its original borrow"
    let start ← IO.monoMsNow
    let (expired,_,_) ← pool.retain "fixture-scope" source path metadata (start+100) (start+200)
    IO.sleep 250
    pool.reap
    check ((← borrowers) == 0 && (← pool.stats).getObjValD "active" == toJson (0 : Nat))
      "abandoned expired handle retained its original charge"
    check (← rejected (pool.withHeld expired "fixture-scope" source.head metadata (start+1000) (fun _ _ => pure ())))
      "expired handle admitted a reader"
    pool.close
    check (← rejected (pool.retain "fixture-scope" source path metadata ((← IO.monoMsNow)+1000) ((← IO.monoMsNow)+2000)))
      "closed pool admitted retention"
    check ((← borrowers) == 0) "closed-pool rejection leaked a cache borrow"
    return Json.mkObj [("lruPressureEntries",toJson (140 : Nat)),("retainedEntryNotEvicted",toJson true),
      ("releaseDuringReadAccounted",toJson true),("expiryDuringReadAccounted",toJson true),("duplicateReleaseIsolated",toJson true),
      ("expiryReaped",toJson true),("foreignRootAndScopeRejected",toJson true),("closedAdmissionRejected",toJson true),
      ("final",← pool.stats),("cache",← originals.stats)]
  finally
    pool.close
    originals.close

private def fileSource (root : System.FilePath) : IO (PageMap.Snapshot × String) := do
  let workspace := root/"retained-file"
  check (!(← workspace.pathExists)) "fresh file-retention fixture required"
  FileSystem.privateDirectory workspace
  IO.FS.writeFile (workspace/"fixture.c") "int alpha = 1;\nint beta = 2;\nint gamma = 3;\n"
  let input := Json.mkObj [("command",toJson "nl -ba fixture.c | sed -n '1,3p'")]
  let capture ← SourceEvidence.capture workspace input ((← IO.monoMsNow)+10000)
  let output := (Json.mkObj [("output",toJson "1\tint alpha = 1;\n2\tint beta = 2;\n3\tint gamma = 3;\n")]).compress
  let correspondence ← ContentCapture.finish workspace capture output ((← IO.monoMsNow)+10000)
  check (correspondence.complete && !correspondence.aliases.isEmpty) "fixture has no verified file correspondence"
  let tool : ToolEvent := {
    name := "arbitrary_read",useId := "file",input := input.compress,response := output,
    source := some capture,correspondence := some correspondence}
  let path := workspace/"source.egg"
  let source ← Persistence.ensureSnapshot path
  let known ← Synapses.Journal.knowledge source [] false
  let occurrence : Synapses.Occurrence := ⟨"retained-file","turn",tool.useId⟩
  let domain := Sha256.hex "retained native file".toUTF8
  let _ ← Synapses.Journal.append source ⟨⟨domain,1⟩,.start occurrence (canonicalToolWork tool) domain known,none⟩
  let _ ← Synapses.Journal.append source ⟨⟨domain,2⟩,.finish occurrence tool.name tool.input tool.response
    (some path.toString),none⟩
  let pending : PendingTurn := {
    sessionId := "retained-file",turnId := "turn",cwd := workspace.toString,prompt := "inspect native file",
    profile := "work",write := some path.toString,read := [],semanticMatcher := none,handoffChars := 120000,projection := .none,
    tools := [tool],closed := true}
  let published ← NativePublication.run pending path true
  check published.source.complete "fixture source was not durably published"
  let source ← PageMap.pin path
  let _ ← Synapses.Build.refresh source .database
  let _ ← CanonicalSource.Cache.refresh source .database
  let owner := Persistence.selectionKey (compileOperationOutcomes (.text "retained-file") (.text "turn") tool).2
  return (source,owner)

def run (root : System.FilePath) : IO Unit := do
  let (source,owner) ← fileSource root
  let now ← IO.monoMsNow
  let storage := Sidecar.Storage.database
  let prepared ← Recommend.prepare source (some (now+10000)) (some (now+25000))
  let some reference := prepared.canonical | throw (IO.userError "canonical retention was not prepared")
  check reference.retained.isSome "ordinary recommendation preparation did not retain its original root"
  let path ← CanonicalSource.Cache.directory source storage
  let some recipes ← CanonicalSource.Cache.preparedAt? source path reference.metadata |
    throw (IO.userError "fixture recipe root is not retained")
  let some stored ← CanonicalSource.Recipe.read? recipes owner | throw (IO.userError "fixture original recipe missing")
  check (!stored.rows.isEmpty) "verified file fixture has no published rows"
  let expected := (toJson stored.rows).compress
  let body ← rows reference owner (now+20000)
  check (body == expected) "service rows differ from the published original recipe"
  let before ← stats
  -- Only this ended fixture's current head is hidden, and always restored.
  let originalHead := source.directory/"head"
  let hiddenHead := source.directory/"head.fixture-held"
  IO.FS.rename originalHead hiddenHead
  try
    check ((← rows reference owner (now+20000)) == body) "retained RPC reopened a mutable original head"
    check (← rejected (rows {reference with retained := none} owner (now+20000)))
      "fixture did not distinguish retention from stateless reconstruction"
  finally IO.FS.rename hiddenHead originalHead
  let expiration ← IO.monoMsNow
  let some abandoned ← Publication.Client.retainSource source storage (expiration+100) (expiration+250) |
    throw (IO.userError "short-lived retention was not admitted")
  IO.sleep 300
  check (((← stats).getObjValD "retainedSources").getObjValD "active" == toJson (1 : Nat))
    "service did not reap an abandoned handle"
  check (← rejected (rows abandoned owner (now+20000))) "expired native retention fell back to reopening a source"
  let requests ← (List.range 80).toArray.mapM fun _ => IO.asTask (do
    let some retained ← Publication.Client.retainSource source storage ((← IO.monoMsNow)+5000) (now+25000) |
      throw (IO.userError "concurrent retention returned no prepared source")
    try check ((← rows retained owner (now+22000)) == body) "concurrent retained body changed"
    finally retained.release (now+24000)) .dedicated
  for request in requests do IO.ofExcept (← IO.wait request)
  let after ← stats
  let beforeLoads := (before.getObjValD "preparedSources").getObjValD "loads"
  let afterLoads := (after.getObjValD "preparedSources").getObjValD "loads"
  check (beforeLoads == afterLoads) "same immutable source was rebuilt for concurrent clients"
  prepared.release (now+24000)
  let released ← stats
  check ((released.getObjValD "retainedSources").getObjValD "active" == toJson (0 : Nat))
    "ordinary query release left retained handles"
  let path ← CanonicalSource.Cache.directory source storage
  let localChecks ← component source reference.metadata path
  let result := Json.mkObj [("allPassed",toJson true),("sameBodyWhileMutableHeadUnavailable",toJson true),
    ("statelessReconstructionRejected",toJson true),("concurrentClients",toJson (80 : Nat)),
    ("abandonedServiceHandleReaped",toJson true),
    ("originalRows",toJson body),("originalBodySha256",toJson (Sha256.hex body.toUTF8)),("cacheLoadsBefore",before.getObjValD "preparedSources" |>.getObjValD "loads"),
    ("cacheLoadsAfter",after.getObjValD "preparedSources" |>.getObjValD "loads"),
    ("retainedAfterRelease",released.getObjValD "retainedSources"),("component",localChecks),
    ("answeringModelCalls",toJson (0 : Nat)),("eightyPeopleEightHours",toJson false),("productionAdoption",toJson false)]
  IO.FS.writeFile (root/"retained-audit.json") (result.pretty++"\n")
  IO.println result.compress

end Eggshell.Research.RetainedSourceChecks

#print axioms Eggshell.Synapses.CanonicalSource.Leases.Held.same_source
#print axioms Eggshell.Synapses.CanonicalSource.Leases.State.within_capacity
#print axioms Eggshell.Research.RetainedSourceChecks.retention_not_memo_identity

def main (args : List String) : IO UInt32 := do
  match args with
  | ["retained-source",root] =>
    try
      Eggshell.Research.RetainedSourceChecks.run (.mk root)
      return 0
    finally
      if let some endpoint ← Publication.Client.endpoint? then
        let _ ← Publication.Client.control "shutdown"
        if ← Numerical.alive endpoint.pid then throw (IO.userError "retained test service did not exit")
  | other => originalFeedMain other
