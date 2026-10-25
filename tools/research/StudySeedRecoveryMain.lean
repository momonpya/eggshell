import tools.research.StudyAcquire
import Eggshell.SynapseLive

open Lean Eggshell Eggshell.Research Eggshell.Synapses Eggshell.Synapses.Extraction

namespace Eggshell.Research.SeedRecovery

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def save (root : System.FilePath) (name : String) (value : Json) : IO Unit := do
  check (!(← (root / name).pathExists)) "keep previous recovery evidence"
  IO.FS.writeFile (root / name) (value.pretty ++ "\n")

private def read (root : System.FilePath) (name : String) : IO Json :=
  StudyAdmission.readJson (root / name).toString

private def queued (root : System.FilePath) (session : String) : IO (Array String) := do
  let mut paths := #[]
  for lane in #["checkpoints","deferred"] do
    let path := root / "data/sessions" / session / lane
    if ← path.pathExists then
      for entry in ← path.readDir do
        if entry.fileName.endsWith ".json" then paths := paths.push entry.path.toString
  return paths.qsort (· < ·)

private def actualCommands (root : System.FilePath) (scope : StudyAccounting.Scope) :
    IO (Array (String × Bool × Bool) × Bool) := do
  let input ← IO.FS.Handle.mk (root / "rpc/exchange.jsonl") .read
  let mut commands : Std.HashMap String Bool := {}
  let mut pre : Std.HashSet String := {}
  let mut post : Std.HashSet String := {}
  let mut prompt := false
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let row ← IO.ofExcept (Json.parse line)
    if (row.getObjValAs? String "direction").toOption != some "server" then continue
    let message ← IO.ofExcept (row.getObjVal? "message")
    let method := (message.getObjValAs? String "method").toOption.getD ""
    if !#["item/started","item/completed","hook/completed"].contains method then continue
    let params ← IO.ofExcept (message.getObjVal? "params")
    if (params.getObjValAs? String "threadId").toOption != some scope.threadId ||
        (params.getObjValAs? String "turnId").toOption != some scope.turnId then continue
    if method == "hook/completed" then
      let hook ← IO.ofExcept (params.getObjVal? "run")
      check ((hook.getObjValAs? String "status").toOption == some "completed") "native hook did not complete"
      let event ← IO.ofExcept (hook.getObjValAs? String "eventName")
      let id ← IO.ofExcept (hook.getObjValAs? String "id")
      if event == "preToolUse" then pre := pre.insert id
      if event == "postToolUse" then post := post.insert id
      if event == "userPromptSubmit" then prompt := true
    else
      let item ← IO.ofExcept (params.getObjVal? "item")
      if (item.getObjValAs? String "type").toOption != some "commandExecution" then continue
      let id ← IO.ofExcept (item.getObjValAs? String "id")
      commands := commands.insert id (method == "item/completed" || commands[id]?.getD false)
  let result := commands.toArray.map fun (id,finished) =>
    (id,finished,pre.toArray.any (·.endsWith (":" ++ id)) && post.toArray.any (·.endsWith (":" ++ id)))
  return (result,prompt)

/-- This is a new recovery record, never a replacement for a failed acquisition.
Only a completed real generation with a cleanup-only failure can enter it. -/
private def generation (root : System.FilePath) : IO (StudyAcquire.Plan × StudyAccounting.Scope) := do
  let plan ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (← read root "plan.json"))
  check (plan.kind == "seed" && plan.output == root.toString) "original seed plan required"
  let failure ← read root "failure.json"
  for name in #["runError","captureError","checkpointError"] do
    check ((failure.getObjVal? name).toOption == some .null) "seed failed before final cleanup"
  check ((failure.getObjValAs? Bool "completed").toOption == some false &&
    (failure.getObjValAs? String "cleanupError").toOption ==
      some "owned daemon did not exit before the cleanup deadline") "cleanup-only seed failure required"
  let guard ← StudyAdmission.readJson plan.guardRecord
  check ((guard.getObjValAs? String "state").toOption == some "finished" &&
    (guard.getObjValAs? (Array Nat) "ownedPids").toOption == some #[])
    "original acquisition still owns processes"
  for artifact in #[plan.runtime,plan.runner,plan.cliWrapper,plan.nativeCli,plan.accountConfiguration,plan.prompt] ++
      plan.harness ++ plan.pluginFiles do StudyAdmission.verifyArtifact artifact
  StudyAdmission.verifyPluginRuntime plan.runtime plan.pluginRoot
  let usage ← read root "usage.json"
  let scope ← IO.ofExcept (usage.getObjValAs? StudyAccounting.Scope "scope")
  let (commands,prompt) ← actualCommands root scope
  check (commands.all (fun (_,finished,hooks) => finished && hooks)) "an actual tool or its hooks did not complete"
  let captured ← StudyAccounting.replay scope (root / "rpc/exchange.jsonl")
  check (StudyAccounting.acquisitionReport scope captured .seed prompt == usage &&
    (usage.getObjValAs? Bool "protocolPassed").toOption == some true)
    "real generation or inclusive cost does not match the saved transcript"
  let initial ← DB.PageMap.pin (root / "input.egg")
  check ((← Build.entries initial).isEmpty) "seed did not start from an empty DB"
  check ((← queued root scope.threadId).isEmpty) "durable source work remains; do not replace it with reconstructed events"
  let commit ← IO.Process.output {cmd := "git",args := #["rev-parse","HEAD"],cwd := some (.mk plan.workspace)}
  let status ← IO.Process.output {cmd := "git",args := #["status","--porcelain"],cwd := some (.mk plan.workspace)}
  check (commit.exitCode == 0 && commit.stdout.trimAscii.toString == plan.sourceCommit &&
    status.exitCode == 0 && status.stdout.trimAscii.isEmpty) "the immutable study source changed"
  return (plan,scope)

private def audit (root : System.FilePath) (scope : StudyAccounting.Scope)
    (traceRoot : System.FilePath := root) : IO Json := do
  let source ← DB.PageMap.pin (root / "work.egg")
  let before ← StudyRuntime.files source.directory
  let origins ← Provenance.records source
  let reader ← Persistence.Store.NodeReader.new source
  for origin in origins do let _ ← Provenance.checkedDocument reader origin.origin; pure ()
  let mut documents := #[]
  for entry in ← Build.entries source do
    let document ← Build.document reader entry.id
    if document.native then documents := documents.push document
  let journal ← Journal.open? source
  let events ← journal.mapM (Journal.turnEntries · ⟨scope.threadId,scope.turnId⟩)
  let events := events.getD #[]
  let starts := events.filter fun event => match event.payload with | .start .. => true | _ => false
  let finishes := events.filter fun event => match event.payload with | .finish .. => true | _ => false
  let (commands,_) ← actualCommands traceRoot scope
  let mut rows := #[]
  for (id,finished,hooks) in commands do
    let occurrence : Occurrence := ⟨scope.threadId,scope.turnId,id⟩
    let pres := starts.filter (·.payload.occurrence == occurrence)
    let posts := finishes.filter (·.payload.occurrence == occurrence)
    let saved := origins.filter (·.origin.occurrence == occurrence)
    let raw := documents.filter (·.occurrences.contains occurrence)
    rows := rows.push (Json.mkObj [("id",toJson id),("actualCommandFinished",toJson finished),
      ("hooksCompleted",toJson hooks),("nativePre",toJson pres.size),("nativePost",toJson posts.size),
      ("rawOriginalOwners",toJson raw.size),
      ("portableOrigins",toJson saved.size)])
  let missing := rows.filter fun row =>
    #["nativePre","nativePost","portableOrigins"].any fun field =>
      (row.getObjValAs? Nat field).toOption == some 0
  let missingRaw := rows.filter fun row =>
    #["nativePre","nativePost","rawOriginalOwners"].any fun field =>
      (row.getObjValAs? Nat field).toOption == some 0
  let provenance ← Provenance.derive source
  check ((← StudyRuntime.files source.directory) == before) "read-only recovery audit changed source facts"
  return Json.mkObj [("rpcCommands",toJson commands.size),("nativeStarts",toJson starts.size),
    ("nativeFinishes",toJson finishes.size),("portableOrigins",toJson origins.size),
    ("ignoredOrigins",toJson provenance.ignored),("missingCalls",toJson missing.size),
    ("missingRawCalls",toJson missingRaw.size),("rawOriginalDocuments",toJson documents.size),
    ("commandAudit",toJson rows),("sourceFiles",toJson before),
    ("reconstructedConsumption",toJson (provenance.graph.snapshot.filter fun fact =>
      match fact with | .consumed _ => true | _ => false).size),
    ("handoffBodiesRead",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("syntheticHookEvents",toJson (0 : Nat)),("directRelationInsertions",toJson (0 : Nat))]

private def environment (plan : StudyAcquire.Plan) (scope : StudyAccounting.Scope) :=
  let root := System.FilePath.mk plan.output
  let changes := #[("EGGSHELL_DATA_ROOT",some (root / "data").toString),
    ("EGGSHELL_CONFIG",some (root / "config.toml").toString),("EGGSHELL_PROFILE",some "work"),
    ("PLUGIN_ROOT",some plan.pluginRoot),("CODEX_THREAD_ID",some scope.threadId),("CODEX_TURN_ID",none)]
  plan.environment.filter (fun row => !changes.any (·.1 == row.1)) ++ changes

def run (acquisition output : String) (finish : Bool) : IO Unit := do
  let root := System.FilePath.mk acquisition
  let target := System.FilePath.mk output
  check (root.isAbsolute && target.isAbsolute && !(← target.pathExists)) "new absolute recovery output required"
  let (plan,scope) ← generation root
  IO.FS.createDir target
  let before ← audit root scope
  save target "source-before.json" before
  check ((before.getObjValAs? Nat "missingRawCalls").toOption == some 0)
    "completed hooks are missing original events or saved observations"
  if !finish then
    save target "result.json" (Json.mkObj [("generationVerified",toJson true),
      ("sourceAudit",before),("runtime",toJson plan.runtime),("acquisition",toJson acquisition),
      ("originalAcquisitionFailed",toJson true),("productionAdoption",toJson false)])
    return
  let pinned ← DB.PageMap.pin (root / "work.egg")
  let warm ← StudyCommand.run plan.runtime.path #["egg","warm","work"] (environment plan scope)
    plan.workspace "" (target / "warm") 240000
  check (warm.exitCode == 0) "frozen runtime warm failed"
  let warmed ← IO.ofExcept (Json.parse warm.stdout >>= (·.getObjValAs? (Array Json) "databases"))
  check (warmed.size == 1) "wrong warm database set"
  let coverage ← IO.ofExcept (warmed[0]!.getObjVal? "after")
  check ((coverage.getObjValAs? Nat "missing").toOption == some 0 &&
    (coverage.getObjValAs? Nat "invalid").toOption == some 0) "recovered seed still has cold or invalid vectors"
  let doctor ← StudyCommand.run plan.runtime.path #["egg","doctor"] (environment plan scope)
    plan.workspace "" (target / "doctor") 60000
  check (doctor.exitCode == 0) "frozen runtime doctor failed"
  let current ← DB.PageMap.pin (root / "work.egg")
  check (← Index.sameSources current pinned.head (current.head.revision-pinned.head.revision+1))
    "warming changed original source facts"
  check ((← queued root scope.threadId).isEmpty) "warm left durable source work"
  let after ← audit root scope
  save target "source-after.json" after
  check ((after.getObjValAs? Nat "missingCalls").toOption == some 0) "warm lost native source events"
  let files ← StudyRuntime.checkpoint (root / "work.egg") (target / "ready.egg")
  StudyAdmission.verifyArtifact plan.runtime
  save target "result.json" (Json.mkObj [("generationVerified",toJson true),
    ("sourceAudit",after),("runtime",toJson plan.runtime),("acquisition",toJson acquisition),
    ("originalAcquisitionFailed",toJson true),("coverage",coverage),
    ("publication",toJson (target / "ready.egg").toString),("sourceFiles",toJson files),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)])

/-- Model-free comparison inputs may replay a failed seed's actual source and
events. This diagnosis cannot admit an answering trial or repair its events. -/
def auditCopy (copy acquisition output : String) : IO Unit := do
  let root := System.FilePath.mk copy
  let original := System.FilePath.mk acquisition
  let usage ← read original "usage.json"
  let scope ← IO.ofExcept (usage.getObjValAs? StudyAccounting.Scope "scope")
  let before ← DB.PageMap.pin (original / "output.egg")
  let current ← DB.PageMap.pin (root / "work.egg")
  check (← Index.sameSources current before.head (current.head.revision-before.head.revision+1))
    "comparison changed original source facts"
  let report ← audit root scope original
  let report := report.setObjVal! "sourceFactsUnchanged" (toJson true)
    |>.setObjVal! "generationAllowed" (toJson false)
    |>.setObjVal! "diagnosticOnly" (toJson true)
    |>.setObjVal! "transcriptSha256" (toJson (← ArtifactHash.hex (original / "rpc/exchange.jsonl")))
  check (!(← (System.FilePath.mk output).pathExists)) "keep the previous copy audit"
  IO.FS.writeFile output (report.pretty ++ "\n")
  check ((report.getObjValAs? Nat "missingRawCalls").toOption == some 0 &&
    (report.getObjValAs? Nat "missingCalls").toOption == some 0) "comparison left unindexed native observations"

end Eggshell.Research.SeedRecovery

def main (args : List String) : IO UInt32 := do
  try
    match args with
    | ["audit-copy",copy,acquisition,output] =>
        Eggshell.Research.SeedRecovery.auditCopy copy acquisition output
        return 0
    | [mode,acquisition,output] =>
        unless #["inspect","finish"].contains mode do throw (IO.userError "expected inspect or finish")
        Eggshell.Research.SeedRecovery.run acquisition output (mode == "finish")
        return 0
    | _ => throw (IO.userError "StudySeedRecoveryMain inspect|finish ACQUISITION NEW-REPORT")
  catch error => IO.eprintln error.toString; return 1
