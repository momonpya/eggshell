import Main
import Eggshell.ContractAudit
import tools.research.ReplayReadiness
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction
open Eggshell.Persistence.Store
namespace Eggshell.Research.ReplayReadinessChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def readTool (name : String) : ToolEvent := {
  name := "mcp__catalog__invoke",useId := name,input := "{\"key\":\"one\"}",
  response := "{\"id\":\"ID_ALPHA\",\"tail\":\"TAIL_BETA\"}" }
def useTool : ToolEvent := {
  name := "mcp__catalog__use",useId := "use",input := "{\"selected\":\"ID_ALPHA\"}",response := "\"done\"" }
def publish (source : DB.PageMap.Snapshot) (session : String) (tool : ToolEvent) : IO DB.PageMap.Snapshot := do
  let relation := (compileOperationOutcomes (.text session) (.text "turn") tool).2
  discard <| DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let id ← intern.root relation
    writeChange writer {added := [id],removed := [],unionsChanged := false,affected := [id]}
  DB.PageMap.pin source.directory
def facts (source : DB.PageMap.Snapshot) : IO Json := do
  let some shared ← Index.open? source .user .shared | throw (IO.userError "missing shared source facts")
  let some usage ← UsageCache.open? source | throw (IO.userError "missing private use facts")
  return toJson ((← Index.allFacts shared.index),(← Index.allFacts usage.index))
def controls (fixed : Bool) (root : System.FilePath) : IO Json := do
  check (!(← root.pathExists)) "fresh replay readiness root required"
  IO.FS.createDirAll root
  check ((← Paths.dataRoot).normalize == (root/"private").normalize) "isolated private preparation root required"
  let source ← DB.PageMap.create (root/"source.egg") "readiness-memory"
  let source ← publish source "seed" (readTool "seed")
  discard <| Build.refresh source .database
  let archive ← DB.PageMap.create (root/"archive.egg") "readiness-private-work"
  let known ← Journal.knowledge source [] false (some archive.directory.toString)
  let mut archive := archive
  let tools := #[readTool "read",useTool]
  let domain := Sha256.hex "readiness-clock".toUTF8
  for (tool,ordinal) in tools.zipIdx do
    archive ← publish archive "live" tool
    let occurrence : Occurrence := ⟨"live","turn",tool.useId⟩
    discard <| Journal.append source ⟨⟨domain,10+2*ordinal⟩,
      .start occurrence (canonicalToolWork tool) (Sha256.hex "query".toUTF8) known,none⟩
    discard <| Journal.append source ⟨⟨domain,11+2*ordinal⟩,
      .finish occurrence tool.name tool.input tool.response (some archive.directory.toString),none⟩
  let replay ← Journal.refresh source .user ((← IO.monoMsNow)+30000)
  check replay.complete "initial two-DB replay did not finish"
  let some journal ← Journal.open? source | throw (IO.userError "private replay missing")
  let some checkpoint ← Journal.checkpoint? journal ("checkpoint:"++Journal.lane .user) |
    throw (IO.userError "initial replay checkpoint missing")
  check (checkpoint.external && (← Journal.checkpointCurrent source .user)) "fixture lacks a complete external dependency"
  let base := Journal.workBase .user
  check (← ReplayReadiness.sourcesCurrent journal base source) "complete unchanged source cursors were not settled"
  let required ← Journal.required source .user
  check (required == !fixed) "actual external readiness does not match the expected parent/candidate policy"
  let before ← facts source
  let journalBefore := journal.head
  let started ← IO.monoMsNow
  let mut repeats := #[]
  for _ in [0:8] do
    let result ← Journal.refresh source .user ((← IO.monoMsNow)+30000)
    check (result.complete && result.turns == 0 && (← facts source) == before) "unchanged replay altered facts or repeated a turn"
    repeats := repeats.push (toJson result)
  let elapsed := (← IO.monoMsNow)-started
  let some journal ← Journal.open? source | throw (IO.userError "replayed journal disappeared")
  check ((← facts source) == before) "readiness changed the original shared/use facts"
  let cursorKey := ReplayWork.sourceKey base archive.directory.normalize.toString
  let some cursorBytes ← journal.get cursorKey | throw (IO.userError "missing actual external source cursor")
  let cursor ← Index.decode (α := ReplayWork.SourceCursor) cursorBytes
  check (ReplayReadiness.settled cursor (some archive.head)) "captured external head differs from the original DB"
  discard <| DB.PageMap.withWriter journal fun writer =>
    writer.put cursorKey (some (toJson {cursor with block := 1}).compress.toUTF8)
  let some partialJournal ← Journal.open? source | throw (IO.userError "partial journal missing")
  check (!(← ReplayReadiness.sourcesCurrent partialJournal base source) && (← Journal.required source .user))
    "incomplete dependency scan was accepted as prepared"
  discard <| DB.PageMap.withWriter partialJournal fun writer => writer.put cursorKey (some cursorBytes)
  let updated ← publish archive "later" (readTool "new-observation")
  check (updated.head != archive.head && (← Journal.required source .user)) "external source change did not invalidate readiness"
  let moved := root/"retained-archive.egg"
  IO.FS.rename archive.directory moved
  check (← Journal.required source .user) "missing external DB was accepted"
  let replacement ← DB.PageMap.create archive.directory "replacement-private-work"
  check (replacement.head.identity != archive.head.identity && (← Journal.required source .user))
    "different DB at the same path was accepted"
  return Json.mkObj [("fixed",toJson fixed),("externalCheckpoint",toJson checkpoint.external),
    ("initiallyRequired",toJson required),("unchangedRepeats",toJson repeats),
    ("repeatElapsedMs",toJson elapsed),("originalFactsExact",toJson true),
    ("journalHeadUnchangedByRepeatedReplay",toJson (journal.head == journalBefore)),
    ("partialChangedMissingReplacementRejected",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]
def main (args : List String) : IO UInt32 := do
  match args with
  | ["readiness-check",mode,root,destination] =>
    check (["parent","fixed"].contains mode) "explicit readiness policy required"
    let result ← controls (mode == "fixed") (.mk root)
    IO.FS.writeFile (.mk destination) result.compress
    IO.println result.compress
    return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain"
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | ["retention-probe",mode] =>
    discard <| IO.ofExcept (Eggshell.Research.RetentionProbe.mode? mode)
    let some endpoint ← Publication.Client.endpoint? | throw (IO.userError "no diagnostic service endpoint")
    IO.println (← Daemon.exchange endpoint "retention-probe" (Json.mkObj [("mode",toJson mode)]) (budget := 5000))
    return 0
  | other =>
    if other == ["codex-publication-daemon"] && (← IO.getEnv "EGGSHELL_RESEARCH_RETENTION") == some "1" then
      Eggshell.Research.HeapObservation.initializeObserver
    sourceRouteEngine other
end Eggshell.Research.ReplayReadinessChecks
def main := Eggshell.Research.ReplayReadinessChecks.main
