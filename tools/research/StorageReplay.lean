import tools.research.StudyRuntime
import tools.research.StudyAdmission
import tools.research.StudyPrepare
import Eggshell.NativePublication

open Lean Eggshell Eggshell.Research Eggshell.Plugin

private def save (path : System.FilePath) (value : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError "preserve previous storage evidence")
  IO.FS.writeFile path (value.compress ++ "\n")

/-- A storage implementation change conservatively invalidates the producer
stamp. Re-run the current matcher over the archived input domain and verify
every source fingerprint; never merely retag an old capture. -/
private def recapture (pending : PendingTurn) (directory : System.FilePath) : IO PendingTurn := do
  let mut tools := []
  let mut checks := #[]
  for tool in pending.tools do
    let some original := tool.correspondence |
      tools := tools ++ [tool]
      continue
    if original.implementation == ContentCapture.implementation then
      tools := tools ++ [tool]
      continue
    let fresh ← match tool.contentInputs.orElse (fun _ => tool.source) with
      | some archived => do
        let deadline := (← IO.monoMsNow)+10000
        ContentCapture.finish (.mk pending.cwd) archived (canonicalJson tool.response) deadline
      | none =>
          if !original.complete && original.inputs.isEmpty && original.aliases.isEmpty &&
              original.failure == some "input-not-captured" then
            pure ({
              implementation := ContentCapture.implementation
              inputs := #[]
              complete := false
              aliases := #[]
              failure := some "input-not-captured"} : ContentCapture.Captured)
          else throw (IO.userError "original capture domain is absent; do not retag its producer")
    unless toJson {fresh with implementation := original.implementation} == toJson original do
      throw (IO.userError "current correspondence differs from the recorded source ranges")
    let updated := {tool with correspondence := some fresh}
    unless toJson updated.native == toJson tool.native &&
        compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) updated ==
        compileOperationOutcomes (.text pending.sessionId) (.text pending.turnId) tool do
      throw (IO.userError "metadata recapture changed the original operation")
    tools := tools ++ [updated]
    checks := checks.push (Json.mkObj [("useId",toJson tool.useId),
      ("oldImplementation",toJson original.implementation),("currentImplementation",toJson fresh.implementation),
      ("logicalCaptureExact",toJson true),("nativeOperationExact",toJson true),
      ("aliases",toJson fresh.aliases.size),("complete",toJson fresh.complete)])
  save (directory / "correspondence-validation.json") (toJson checks)
  return {pending with tools}

/-- The ordinary native source compiler and metadata stage, with read-only
inspection of the pending rows before the original writer flush. No model,
encoder, selector, numerical warm or synthetic usage labels are invoked. -/
def main (args : List String) : IO Unit := do
  let (planPath,checkpoint,output,service) ← match args with
    | [planPath,checkpoint,output] => pure (planPath,checkpoint,output,none)
    | ["service",runtime,planPath,checkpoint,output] => pure (planPath,checkpoint,output,some runtime)
    | _ => throw (IO.userError "[service RUNTIME] PLAN CHECKPOINT NEW-OUTPUT")
  let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson planPath))
  let directory := System.FilePath.mk output
  unless directory.isAbsolute && !(← directory.pathExists) do throw (IO.userError "new absolute replay output required")
  let pending ← IO.ofExcept (fromJson? (α := PendingTurn) (← StudyAdmission.readJson checkpoint))
  unless pending.write == some plan.database && pending.finalMessage.isNone do
    throw (IO.userError "replay only a real observation checkpoint at its original target")
  unless (← IO.getEnv "EGGSHELL_DATA_ROOT") == some plan.dataRoot do
    throw (IO.userError "private source timing must come from its recorded scope")
  StudyAdmission.verifyArtifact plan.runtime
  let database := System.FilePath.mk plan.database
  let before ← DB.PageMap.pin database
  IO.FS.createDirAll directory
  let inputFiles ← StudyRuntime.checkpoint database (directory / "before.egg")
  save (directory / "input.json") (Json.mkObj [("checkpoint",toJson (← StudyPrepare.artifact (.mk checkpoint))),
    ("head",toJson before.head),("files",toJson inputFiles),
    ("answeringModelCalls",toJson (0 : Nat)),("checkpointModified",toJson false)])
  let pending ← recapture pending directory
  let request ← NativePublication.prepare pending database true
  let started ← IO.monoMsNow
  let mut error : Option String := none
  let mut receipt : Json := .null
  try
    let published ← match service with
      | some runtime => do
        let installation := (System.FilePath.mk runtime).parent.get!.parent.get!
        let environment := plan.environment.filter (·.1 != "EGGSHELL_PREFIX") ++
          #[("EGGSHELL_PREFIX",some installation.toString)]
        let publisher ← StudyRuntime.startPublisher (.mk runtime) (.mk plan.dataRoot) environment
        try
          let result ← Publication.Client.run pending database true
          pure result.source
        finally StudyRuntime.stopManaged publisher (directory / "publisher-shutdown.json")
      | none => do
        let committed ← Persistence.appendPrepared database
          (fun graph => do
            let (compiled,promotion) ← NativePublication.compilePrepared graph database request
            let some transaction := (Transaction.begin graph).stageValues? compiled.stagedValues.eraseDups |
              throw "publication group contains an invalid Value"
            return (transaction,promotion))
          (fun intern _ => do
            let changed ← NativePublication.stage request.items intern
            let rows := (← intern.writer.pending.get).toList
            let mut oversized := #[]
            let mut largest := ("",0,0)
            for row in rows do
              let bytes := (DB.PageMap.encode (.leaf [row])).size
              if largest.2.2 < bytes then largest := (row.1,(row.2.map ByteArray.size).getD 0,bytes)
              if bytes > 8192 then
                oversized := oversized.push (Json.mkObj [("key",toJson row.1),
                  ("valueBytes",toJson (row.2.map ByteArray.size |>.getD 0)),("encodedSingletonBytes",toJson bytes)])
            save (directory / "staged-rows.json") (Json.mkObj [
              ("rows",toJson rows.length),("oversized",toJson oversized),("largest",toJson largest),
              ("physicalPageCapBytes",toJson (65536 : Nat)),("normalLeafCapBytes",toJson (8192 : Nat))])
            return changed)
        pure (NativePublication.receipt request.items committed.head)
    receipt := toJson published
    let source ← DB.PageMap.pin database
    let reader ← Persistence.Store.NodeReader.new source
    let mut readback := #[]
    for item in request.items do
      let owner := (compileOperationOutcomes (.text item.occurrence.session)
        (.text item.occurrence.turn) item.tool).2
      let some id ← Persistence.Store.findNode? source owner |
        throw (IO.userError "published original owner could not be found")
      let document ← Synapses.Build.document reader id
      let some edge := OutcomeEdge.fromValue? owner | throw (IO.userError "invalid original owner")
      unless document.source == Persistence.Store.text? edge.outcome do
        throw (IO.userError "published original bytes differ from the actual input")
      let raw := document.source.getD ""
      let prepared ← IO.ofExcept (Synapses.ObservedRecords.prepare raw)
      let expected ← IO.ofExcept (Synapses.ObservedRecords.catalog source.head.identity document prepared.records)
      let some actual ← Synapses.ObservedRecords.load? source id document |
        throw (IO.userError "published original record directory is absent")
      unless actual.located.map (fun row => (row.read,row.text)) ==
          expected.located.map (fun row => (row.read,row.text)) &&
          actual.quotations.map (fun row => (row.read,row.text)) ==
          expected.quotations.map (fun row => (row.read,row.text)) do
        throw (IO.userError "original record payloads or their coordinates changed")
      let mut aliases := 0
      if let some expected := item.tool.correspondence then
        let some actual ← ContentMetadata.load? source id document |
          throw (IO.userError "published content correspondence is absent")
        unless toJson actual == toJson expected do
          throw (IO.userError "published content aliases differ from the native capture")
        aliases := actual.aliases.size
      readback := readback.push (Json.mkObj [("owner",toJson id),
        ("originalBytesExact",toJson true),("recordCount",toJson prepared.records.size),
        ("recordReadbackExact",toJson true),("contentAliases",toJson aliases)])
    save (directory / "readback.json") (toJson readback)
  catch failed => error := some failed.toString
  let after ← DB.PageMap.pin database
  let result := Json.mkObj [("error",toJson error),("receipt",receipt),
    ("before",toJson before.head),("after",toJson after.head),
    ("publishedHeadUnchanged",toJson (before.head == after.head)),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("answeringModelCalls",toJson (0 : Nat)),
    ("standardCompilerAndStage",toJson true),("publicationServiceUsed",toJson service.isSome),
    ("modelOrQueryRulesAdded",toJson false)]
  save (directory / "result.json") result
  IO.println result.compress
