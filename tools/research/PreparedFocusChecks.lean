import Eggshell.PublicationService
import tools.research.PreparedFocusFacts
import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Synapses Eggshell.Plugin
open Eggshell.DB
#print axioms PreparedFocusFacts.encoded_rows_exact
#print axioms PreparedFocusFacts.compiled_rows_exact
#print axioms PreparedFocusFacts.prepared_rank_exact
#print axioms PreparedFocusFacts.prepared_positions
#print axioms PreparedFocusFacts.mismatched_work_refused
#print axioms PreparedFocusFacts.Ready.rank_is_original
#print axioms PreparedFocusFacts.Ready.rank_bounded
#print axioms PreparedFocusFacts.Ready.rank_distinct
#print axioms OwnerMetadataImage.Image.focus_ready_exact
#print axioms OwnerMetadataImage.Image.foreign_focus_rejected
#print axioms OwnerMetadataImage.Image.focus_insert_other
#print axioms SharedReadViews.Source.focus_is_captured_read

theorem evidence_matches_actual_focus (owner : OutcomeEdge) :
    PreparedFocusFacts.evidence ((Matcher.atomText? owner.work).getD "")
      ((Matcher.atomText? owner.outcome).getD "") = evidenceSearchWindows owner := rfl
theorem rank_matches_actual_focus (owner : OutcomeEdge) (question : String) (semantic : List Nat) :
    (PreparedFocusFacts.prepared "owner" "work" ((Matcher.atomText? owner.work).getD "")
      ((Matcher.atomText? owner.outcome).getD "")).rank question semantic =
      focusedEvidenceWindows question (evidenceSearchWindows owner) semantic := by
  rw [PreparedFocusFacts.prepared_rank_exact,evidence_matches_actual_focus]
  rfl
#print axioms rank_matches_actual_focus

run_cmd do
  let environment ← getEnv
  for (name,required) in [(``CanonicalSource.Cache.projectOwner,``PreparedFocusFacts.compile),
      (``PreparedSourceView.decodeOwner,``PreparedFocusFacts.check),
      (``SharedReadViews.Source.focusWindows,``OwnerMetadataImage.Image.focusWindows),
      (``OwnerMetadataImage.Image.focusWindows,``PreparedFocusFacts.Ready.rank),
      (``OwnerMetadataImage.Image.focusWindows,``PreparedFocusFacts.Ready.matches)] do
    let some declaration := environment.find? name | throwError "missing focus declaration {name}"
    let some value := declaration.value? | throwError "opaque focus declaration {name}"
    unless value.getUsedConstants.contains required do throwError "disconnected focus preparation {name} -> {required}"
  unless environment.find? `Eggshell.Synapses.CanonicalSource.Shared.Loaded.focusWindows |>.isNone do
    throwError "per-read mutable cache acquisition remains exposed"
  let mut pending := [``SharedReadViews.Source.focusWindows,``OwnerMetadataImage.Image.focusWindows]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","Std.Atomic", "IO.","ST.Ref.","EStateM.Ref."].any (fun stem => name.toString.startsWith stem) ||
        [``SearchRank.Corpus.build,``SearchRank.windows,``PreparedFocusFacts.compile].contains name then
      throwError "prepared focus rank rebuilds source text or synchronizes {name}"
    if let some declaration := environment.find? name then
      if let some value := declaration.value? then pending := value.getUsedConstants.toList++pending
  logInfo m!"Actual publication/decoder/captured reader connected;{seen.size} read dependencies have no IO, shared synchronization or source-window rebuild;per-read acquiring API absent"

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def queries : List String := ["", "alpha café", "境界 警告", "커널 스케줄러", "source/key-17"]
def pureChecks : IO Nat := do
  let mut comparisons := 0
  for width in [0,383,384,385,511,512,513,1024] do
    let work := String.ofList (List.replicate width '界')
    for text in ["", "alpha café école\n커널 스케줄러\n警告 test_17",
        (Json.mkObj [("body",toJson (String.ofList (List.replicate 5100 'x')++"\nTAIL source/key-17"))]).compress] do
      let stored := PreparedFocusFacts.compile "owner" "work" work text
      let roundtrip ← IO.ofExcept (fromJson? (toJson stored) : Except String PreparedFocusFacts.Stored)
      let ready ← IO.ofExcept (PreparedFocusFacts.check "owner" roundtrip)
      let windows := PreparedFocusFacts.evidence work text
      check (ready.rows == windows.map SearchRank.terms) "interned rows differ after serialization"
      check (ready.matches "owner" "work" stored.originalWindows &&
        !(ready.matches "foreign" "work" stored.originalWindows) &&
        !(ready.matches "owner" "changed" stored.originalWindows) &&
        !(ready.matches "owner" "work" (stored.originalWindows++["foreign"]))) "prepared focus accepted a foreign scope"
      for question in queries do
        for semantic in [[],List.range windows.length,(List.range windows.length).reverse,[0,0,windows.length+1]] do
          check (ready.rank question semantic == focusedEvidenceWindows question windows semantic)
            "prepared focus rank changed Float/tie/position behavior"
          comparisons := comparisons+1
      let broken := {stored with windows := [[stored.dictionary.size]]}
      check (broken.decode.isNone) "invalid term ordinal accepted"
  return comparisons

def appendOne (source : PageMap.Snapshot) (workspace : System.FilePath) : IO PageMap.Snapshot := do
  let tool : ToolEvent := {
    name := "arbitrary_lookup"
    useId := "new-focus-facts"
    input := (Json.mkObj [("resource",toJson "fixture://focus/new")]).compress
    response := (Json.mkObj [("body",toJson "alpha boundary café\nTAIL source/key-17")]).compress }
  let occurrence : Occurrence := ⟨"focus-delta","turn",tool.useId⟩
  let known ← Journal.knowledge source [] false
  let domain := Sha256.hex "prepared focus delta".toUTF8
  discard <| Journal.append source ⟨⟨domain,1⟩,.start occurrence (canonicalToolWork tool)
    (Sha256.hex "focus delta query".toUTF8) known,none⟩
  discard <| Journal.append source ⟨⟨domain,2⟩,.finish occurrence tool.name
    (canonicalJson tool.input) (canonicalJson tool.response) (some source.directory.toString),none⟩
  let pending : PendingTurn := {
    sessionId := occurrence.session
    turnId := occurrence.turn
    cwd := workspace.toString
    prompt := "focus delta query"
    profile := "work"
    write := some source.directory.toString
    read := []
    semanticMatcher := none
    handoffChars := 120000
    projection := .none
    tools := [tool]
    finalMessage := none }
  let request ← NativePublication.prepare pending source.directory true
  let results ← NativePublication.runPrepared source.directory #[request]
  check (results.size == 1 && results.all (·.source.complete)) "delta publication did not ACK"
  PageMap.pin source.directory

def checks (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh prepared focus check root required"
  IO.FS.createDirAll root
  let pureCount ← pureChecks
  let originals : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/frontend-quiescence-fixture-small1/work.project/owners"
  let shared ← CanonicalSource.Shared.Pool.new
  let views ← SharedReadViews.Pool.new
  let mut owners := 0
  let mut windows := 0
  let mut compared := 0
  let mut referenceNs := 0
  let mut preparedNs := 0
  let mut sample : Option (String × String × String × PreparedFocusFacts.Ready) := none
  let mut heads := #[]
  try
    for index in [:16] do
      let source ← PageMap.pin (originals/toString index/"source.egg")
      let before ← IO.FS.readFile (source.directory/"head")
      discard <| Build.refresh source .database
      let refreshed ← CanonicalSource.Cache.refresh source .database
      let path ← CanonicalSource.Cache.directory source .database
      let reader ← Persistence.Store.NodeReader.new source
      let entries ← Build.entries source
      let directory ← entries.mapM fun entry => do
        let document ← Build.document reader entry.id
        return document.owner
      let (captured,lease) ← shared.withReady source path refreshed.metadata ((← IO.monoMsNow)+20000) fun loaded _ => do
        let deadline := (← IO.monoMsNow)+10000
        let mut bytes := 0
        for owner in directory do bytes := bytes+(← loaded.withMetadata owner deadline (fun ready => pure ready.bytes))
        let lease ← views.reserve "fixture-scoped-read" bytes deadline
        try
          let captured ← SharedReadViews.Source.capture "fixture-scoped-read" source.head loaded directory deadline
          check (captured.capturedBytes ≤ bytes) "captured focus facts exceeded the counted query reservation"
          views.attach lease "fixture-scoped-read" #[captured]
          return (captured,lease)
        catch error => views.release lease "fixture-scoped-read"; throw error
      for entry in entries do
        let document ← Build.document reader entry.id
        let expected ← SourceDelta.documents source [entry.id]
        let some expected := expected.head? | throw (IO.userError "original window directory vanished")
        let metadata ← IO.ofExcept (captured.readMetadata document.owner)
        let some ready := metadata.focus | throw (IO.userError "published candidate has no prepared focus facts")
        check (ready.matches document.owner document.work expected.windows) "focus preparation changed original owner/work/windows"
        let semantic := List.range ready.rows.length
        check ((captured.focusWindows document.owner "foreign" expected.windows "q" semantic).toOption.isNone)
          "captured focus accepted a foreign Work"
        check ((captured.focusWindows document.owner document.work (expected.windows++["foreign"]) "q" semantic).toOption.isNone)
          "captured focus accepted a foreign window domain"
        check ((captured.focusWindows "foreign" document.work expected.windows "q" semantic).toOption.isNone)
          "captured focus accepted a foreign owner"
        check ((captured.metadata.focusWindows "foreign" document.owner document.work expected.windows "q" semantic).toOption.isNone)
          "captured focus accepted a foreign snapshot identity"
        check (metadata.bytes ≥ (toJson ready.stored).compress.utf8ByteSize) "captured metadata charge omitted focus facts"
        let edge ← reader.outcome (← reader.locateOutcome entry.id)
        let texts := evidenceSearchWindows edge
        check (ready.rows == texts.map SearchRank.terms) "published focus differs from original source terms"
        for question in queries do
          for semantic in [List.range texts.length,(List.range texts.length).reverse] do
            let began ← IO.monoNanosNow
            let reference := focusedEvidenceWindows question texts semantic
            let reference ← (← IO.mkRef reference).get
            referenceNs := referenceNs+((← IO.monoNanosNow)-began)
            let began ← IO.monoNanosNow
            let ranked ← IO.ofExcept (captured.focusWindows document.owner document.work expected.windows question semantic)
            let ranked ← (← IO.mkRef ranked).get
            preparedNs := preparedNs+((← IO.monoNanosNow)-began)
            check (ranked == reference) "actual published focus changed the complete window ranking"
            compared := compared+1
        if index == 15 && sample.isNone then sample := some (lease,document.owner,document.work,ready)
        owners := owners+1
        windows := windows+ready.rows.length
      check ((← IO.FS.readFile (source.directory/"head")) == before) "preparation rewrote an original source head"
      heads := heads.push source.head.identity
      if sample.map (·.1) != some lease then views.release lease "fixture-scoped-read"
    let some (lease,owner,work,ready) := sample | throw (IO.userError "no published focus sample")
    let began ← IO.monoMsNow
    views.withView lease "fixture-scoped-read" fun view => do
      let some captured := view.sources[0]? | throw (IO.userError "captured query view disappeared")
      shared.state.atomically do
       shared.views.state.atomically do
        let tasks ← (Array.range 80).mapM fun _ => IO.asTask (do
          for question in queries do
            let semantic := List.range ready.rows.length
            let ranked ← IO.ofExcept (captured.focusWindows owner work ready.stored.originalWindows question semantic)
            check (ranked == ready.rank question semantic && ranked.all (· < ready.rows.length))
              "parallel captured read changed the complete window rank") .dedicated
        try
          for task in tasks do TaskDeadline.wait task ((← IO.monoMsNow)+2000)
        finally
          for task in tasks do IO.cancel task
          for task in tasks do discard <| IO.wait task
    let parallelMs := (← IO.monoMsNow)-began
    views.release lease "fixture-scoped-read"
    let stats ← views.stats
    check (stats.getObjValD "chargedBytes" == toJson (0 : Nat) && stats.getObjValD "active" == toJson (0 : Nat))
      "captured facts outlived their query reservations"
    IO.FS.writeFile (root/"published-checks.json") (Json.mkObj [("pureRankingComparisons",toJson pureCount),
      ("publishedOwners",toJson owners),("originalWindows",toJson windows),("publishedRankComparisons",toJson compared),
      ("referenceNs",toJson referenceNs),("preparedNs",toJson preparedNs),
      ("cacheLockHeldParallelReaders",toJson (80 : Nat)),("parallelReadMs",toJson parallelMs),
      ("originalHeadsUnchanged",toJson heads.size),("deltaNotYetChecked",toJson true)]).compress
    let copied := root/"delta.egg"
    IO.FS.createDirAll copied
    for entry in ← (originals/"0/source.egg").readDir do
      if entry.fileName == "head" || entry.fileName == "writer" || entry.fileName.endsWith ".pages" then
        IO.FS.writeBinFile (copied/entry.fileName) (← IO.FS.readBinFile entry.path)
    let before ← PageMap.pin copied
    discard <| Build.refresh before .database
    let initial ← CanonicalSource.Cache.refresh before .database
    let old ← CanonicalSource.Cache.preparedAt? before (← CanonicalSource.Cache.directory before .database) initial.metadata
    let some old := old | throw (IO.userError "old prepared root missing")
    let entries ← Build.entries before
    let some first := entries[0]? | throw (IO.userError "delta control has no original candidates")
    let doc ← Build.document (← Persistence.Store.NodeReader.new before) first.id
    let descriptor ← old.get (PreparedSourceView.ownerName doc.owner)
    let current ← appendOne before root
    discard <| Build.refresh current .database
    let delta ← CanonicalSource.Cache.refresh current .database
    check (delta.mode == "owner-delta" && delta.changedOwners == 1) "one observation caused a full focus rebuild"
    let some after ← CanonicalSource.Cache.preparedAt? current (← CanonicalSource.Cache.directory current .database) delta.metadata |
      throw (IO.userError "delta prepared root missing")
    check ((← after.get (PreparedSourceView.ownerName doc.owner)) == descriptor &&
      (← old.get (PreparedSourceView.ownerName doc.owner)) == descriptor) "delta rewrote or retired unchanged focus facts"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("pureRankingComparisons",toJson pureCount),
      ("publishedOwners",toJson owners),("originalWindows",toJson windows),("publishedRankComparisons",toJson compared),
      ("referenceNs",toJson referenceNs),("preparedNs",toJson preparedNs),
      ("originalHeadsUnchanged",toJson heads.size),("cacheLockHeldParallelReaders",toJson (80 : Nat)),
      ("parallelReadMs",toJson parallelMs),("delta",toJson delta),
      ("unchangedOwnerAndRetainedRootExact",toJson true),("hookIntegrationTested",toJson false),
      ("capturedReadIsPure",toJson true),("perReadCacheAcquisitionRemoved",toJson true),
      ("preparationAndMetadataLocksHeld",toJson true),
      ("queryReservationsReleased",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally
    views.close
    shared.close

def main (args : List String) : IO UInt32 := do
  match args with
  | ["prepared-focus-check",root] => checks (.mk root); return 0
  | other => sourceRouteEngine other
