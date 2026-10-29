module
import all Eggshell.PublicationService
import all Eggshell.SynapseBuild
public meta import Lean
open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Synapses
open CanonicalSource

run_meta do
  let environment ← getEnv
  for root in #[``Index.open?, ``Cache.manifestAt?] do
    let mut pending := [root]
    let mut seen : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if seen.contains name then continue
      seen := seen.insert name
      let some declaration := environment.find? name | throwError "missing read boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for forbidden in #[``PageMap.withWriter, ``Index.prepare, ``Sidecar.prepare,
        ``Build.refresh, ``Matcher.localUnion?] do
      if seen.contains forbidden then throwError "prepared snapshot read reaches {forbidden}"
    logInfo m!"Prepared snapshot lookup has no preparation, publication or Union: {root}"

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def reject (action : IO α) : IO Bool := do
  try let _ ← action; pure false catch _ => pure true

private def publish (source : PageMap.Snapshot) (values : List Value) : IO PageMap.Snapshot := do
  let _ ← PageMap.withWriter source fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    Persistence.Store.writeChange writer {added := ids, removed := [], unionsChanged := false}
  PageMap.pin source.directory

private def observation (workspace : System.FilePath) (tag : String) (first last : Nat) : IO (List Value) := do
  let command := s!"nl -ba source.cpp | sed -n '{first},{last}p'"
  let input := Json.mkObj [("command", toJson command)]
  let captured ← SourceEvidence.capture workspace input ((← IO.monoMsNow) + 10000)
  check captured.record.valid "actual original input fingerprint was not captured"
  let observed ← IO.Process.output {cmd := "/bin/sh", args := #["-c", command], cwd := workspace.toString}
  check (observed.exitCode == 0) "actual fixture file read failed"
  let work := Value.text ("shell\n" ++ input.compress)
  let output := Value.text observed.stdout
  let occurrence := Value.applyList .occurrence [Ref.semantic output, Ref.semantic work,
    Ref.exact (.text "prepared-snapshot-session"), Ref.exact (.text "turn"), Ref.exact (.text tag)]
  let owner := OutcomeEdge.make work output [occurrence] (by simp) (by simp [maxOutcomeObservations])
  let receipt := SourceEvidence.receipt (.text "prepared-snapshot-session") (.text "turn")
    (.text tag) owner.relation captured.record
  return [owner.relation, receipt]

private def server : IO Publication.Service.Server := return ⟨
  ← Std.Mutex.new ({} : Publication.Service.State), ← Std.Mutex.new 0, ← IO.mkRef false,
  ← Std.Mutex.new #[], ← Shared.Pool.new, ← ObservedRecordView.Cache.new,
  ← Std.Mutex.new 0, ← Std.Mutex.new #[]⟩

private def requireRows (service : Publication.Service.Server) (scope : Publication.Service.ReadSource)
    (source : PageMap.Snapshot) (expected : Array StoredRow) : IO Unit := do
  let response ← Publication.Service.prepareRegistered service scope (some source.head) ((← IO.monoMsNow) + 10000)
  check (response != Json.null) "already prepared source was reported absent by service"
  let access ← IO.ofExcept (fromJson? (α := Shared.Access) response)
  check (access.source == source.head) "service substituted another source publication"
  let owners := (hashDistinct (expected.toList.flatMap fun row => row.origins.toList.map (·.binding.owner))).toArray
  let payload := Json.mkObj [("database", toJson source.head.identity), ("scope", toJson scope.scope),
    ("source", toJson source.head), ("metadata", toJson access.metadata), ("owners", toJson owners)]
  let projected ← Publication.Service.sourceRows service scope.capability payload ((← IO.monoMsNow) + 10000)
  let decoded ← IO.ofExcept (fromJson? (α := Shared.Projection) projected)
  let merged ← IO.ofExcept (Delivery.merge (decoded.rows.flatMap Prod.snd))
  check (merged == expected) "historical service source bytes or original bindings changed"

public def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh isolated fixture required")
  let root := System.FilePath.mk destination
  check (!(← root.pathExists) && (← Paths.dataRoot) == root / "private") "isolated fixture and private root required"
  IO.FS.createDir root
  IO.FS.writeFile (root / "source.cpp") ("\n".intercalate ((List.range 8).map fun n => s!"original_line_{n}();") ++ "\n")
  let empty ← PageMap.create (root / "source.egg") "prepared-snapshot-fixture"
  let first ← publish empty (← observation root "first" 1 4)
  let _ ← Build.refresh first .database
  let firstCanonical ← Cache.refresh first .database
  let some firstIndex ← Index.open? first .database .shared | throw (IO.userError "initial index missing")
  let firstFacts ← Index.allFacts firstIndex.index
  let some firstReady ← Cache.open? first .database | throw (IO.userError "initial canonical source missing")
  let firstRows := firstReady.registry.store
  check (firstRows.size == 4 && !firstFacts.isEmpty) "fixture has no real original evidence"
  let second ← publish first (← observation root "second" 5 8)
  check ((← Index.open? second .database .shared).isNone && !(← Cache.ready second))
    "unprepared new source reused an incomplete earlier index"
  let service ← server
  let scope ← Publication.Service.readSource service first.directory first.head.identity .database
  try
    requireRows service scope first firstRows
    check ((← Publication.Service.prepareRegistered service scope (some second.head) ((← IO.monoMsNow) + 10000)) == Json.null)
      "service claimed unprepared new evidence was complete"
    let updated ← Build.refresh second .database
    let _ ← Cache.refresh second .database
    let path ← Cache.directory first .database
    let some latest ← Index.open? second .database .shared | throw (IO.userError "new prepared index missing")
    let some latestMetadata ← Cache.manifest? path | throw (IO.userError "new canonical metadata missing")
    check ((← Index.atSource? first latest.index .shared).isNone &&
      (← Cache.atSource? first path latestMetadata).isNone) "latest-only control did not reproduce old rejection"
    let some retained ← Index.open? first .database .shared | throw (IO.userError "old source lost its complete index")
    check (retained.index.head == firstIndex.index.head && (← Index.allFacts retained.index) == firstFacts)
      "retained root changed the old complete fact set"
    let some historical ← Cache.open? first .database | throw (IO.userError "old source lost its canonical view")
    check (historical.metadata == firstCanonical.metadata && historical.registry.store == firstRows)
      "canonical lookup changed historical bytes or source metadata"
    let captured ← Journal.knowledge first [] false
    check (captured.source == first.head && captured.indexed.isSome)
      "tool start lost its prepared index after background publication advanced"
    let some secondReady ← Cache.open? second .database | throw (IO.userError "new canonical view missing")
    let secondRows := secondReady.registry.store
    check (secondRows.size == 8) "new publication did not include all new original lines"
    let originalHead := (← PageMap.pin first.directory).head
    let indexPath ← Index.directory first .database .shared
    let indexHead := (← PageMap.pin indexPath).head
    let recipeHead := (← PageMap.pin (path / "recipes")).head
    let manifestBytes ← IO.FS.readBinFile (path / "manifest.json")
    let began ← IO.monoMsNow
    let tasks ← (Array.range 80).mapM fun i => IO.asTask
      (requireRows service scope (if i % 2 == 0 then first else second)
        (if i % 2 == 0 then firstRows else secondRows)) .dedicated
    for task in tasks do IO.ofExcept (← IO.wait task)
    let concurrentMs := (← IO.monoMsNow) - began
    let stable ← Build.refresh first .database
    check (stable.mode == "warm" && (← PageMap.pin first.directory).head == originalHead &&
      (← PageMap.pin indexPath).head == indexHead && (← PageMap.pin (path / "recipes")).head == recipeHead &&
      (← IO.FS.readBinFile (path / "manifest.json")) == manifestBytes)
      "historical read or warm rolled back or rewrote a newer publication"
    let key := Index.retainedName first.head
    let index ← PageMap.pin indexPath
    let some saved ← index.get key | throw (IO.userError "retained index directory entry missing")
    let poison := fun (bytes : ByteArray) => do
      let current ← PageMap.pin indexPath
      let _ ← PageMap.withWriter current fun writer => writer.put key (some bytes)
      pure ()
    let foreign ← PageMap.create (root / "foreign-index") "foreign-index"
    poison (toJson ({source := first.head, index := foreign.head} : Index.Retained)).compress.toUTF8
    check (← reject (Index.open? first .database .shared)) "foreign retained root was accepted"
    poison (toJson ({source := second.head, index := firstIndex.index.head} : Index.Retained)).compress.toUTF8
    check (← reject (Index.open? first .database .shared)) "wrong exact source was accepted"
    poison saved
    check (← (Index.open? first .database .shared)).isSome "restored valid root is not readable"
    let recipeIndex ← PageMap.pin (path / "recipes")
    let some savedCanonical ← recipeIndex.get key | throw (IO.userError "retained canonical directory entry missing")
    let _ ← PageMap.withWriter recipeIndex fun writer => writer.put key
      (some (toJson {firstCanonical.metadata with source := second.head}).compress.toUTF8)
    check (← reject (Cache.open? first .database)) "wrong canonical source was accepted"
    let recipes ← PageMap.pin (path / "recipes")
    let _ ← PageMap.withWriter recipes fun writer => writer.put key (some savedCanonical)
    requireRows service scope first firstRows
    let _ ← PageMap.withWriter second fun writer => do
      writer.put "unprepared-original-publication" (some "new source".toUTF8)
      Persistence.Store.writeChange writer {added := [], removed := [], unionsChanged := true}
    let third ← PageMap.pin second.directory
    check ((← Index.open? third .database .shared).isNone && !(← Cache.ready third))
      "a later unprepared source inherited another publication's completeness"
    check (← (Journal.knowledge third [] false)).indexed.isNone
      "tool start captured a complete index for unprepared new evidence"
    requireRows service scope second secondRows
    let report := Json.mkObj [("latestOnlyControlRejectedOldSource", toJson true),
      ("oldFactsAndBytesPreserved", toJson true), ("newOriginalRows", toJson secondRows.size),
      ("unpreparedNewSourceRejected", toJson true), ("readsAndOldWarmDoNotWrite", toJson true),
      ("foreignRootAndWrongSourcesRejected", toJson true), ("concurrentNativeServiceCalls", toJson (80 : Nat)),
      ("toolStartCapturedOldPreparedIndex", toJson true),
      ("concurrentElapsedMs", toJson concurrentMs), ("preparation", toJson updated),
      ("pool", ← service.prepared.stats), ("answeringModelCalls", toJson (0 : Nat)),
      ("actualHookCalls", toJson (0 : Nat)), ("goalAchieved", toJson false)]
    IO.FS.writeFile (root / "result.json") report.pretty
    IO.println report.compress
  finally service.prepared.close
