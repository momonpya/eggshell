import Main
import tools.research.TaskDeadlineChecks
import tools.research.FrontInputAudit
import tools.research.DirectNumericalChecks
import tools.research.SingleSearchChecks
import tools.research.FrontSessionChecks
import tools.research.LiteralRankChecks
import tools.research.StartupChecks
import tools.research.PreparedLexicalChecks
import tools.research.InputFrameChecks
import tools.research.SourcePinBatchChecks
import tools.research.OwnerBindingChecks

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.FrontTrafficChecks

def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def save (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path (value.pretty++"\n")

def headValue (label : String) := "observed-head-"++label++"-7b319c"
def tailValue (label : String) := "observed-tail-"++label++"-d82a04"
def uri (label : String) := "mcp://support/"++label

def response (label : String) (size : Nat) : IO Json := do
  let wrap (filler : String) := Json.mkObj [("uri",toJson (uri label)),
    ("head",toJson (headValue label)),("payload",toJson filler),("tail",toJson (tailValue label))]
  let overhead := (wrap "").compress.utf8ByteSize
  check (overhead < size) "payload envelope is larger than the requested output"
  let chunks := (List.range (size/24+1)).map fun i => s!"{label} block={i} register={i*1031+19} status={i%17} observation "
  let filler := ((String.join chunks).take (size-overhead)).toString
  let result := wrap filler
  check (result.compress.utf8ByteSize == size) "output is not the predeclared byte size"
  return result

def baseInput (root : System.FilePath) (session event : String) : Json :=
  Json.mkObj [("session_id",toJson session),("turn_id",toJson "turn"),("cwd",toJson root.toString),
    ("hook_event_name",toJson event),("_eggshell_config",toJson (root/"eggshell.toml").toString)]

def hook (root : System.FilePath) (session label event : String) (input : Json) : IO Json := do
  let started ← IO.monoMsNow
  let receipt ← Receipt.fresh
  let reply ← Daemon.hookRequest input (started+30000) receipt
  let output ← IO.ofExcept (reply.getObjValAs? String "output")
  let path := root/(session++"-"++label++"-"++event++".json")
  IO.FS.writeFile path (output++"\n")
  check ((← IO.FS.readFile path) == output++"\n") "native receiver did not retain the actual output"
  let validJson := (Daemon.decodeHookReply (some (Json.mkObj [("output",toJson output)]))).isComplete
  let parsed ← IO.ofExcept (Json.parse output)
  let body := ((parsed.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
  let complete := validJson && body != pendingSearch.text
  let ack := reply.getObjValD "ack"
  let mut acknowledged := false
  let mut acknowledgmentError : Option String := none
  if ack != Json.null then
    try
      let endpoint ← Daemon.readyEndpoint session
      acknowledged := (← Daemon.exchange endpoint "ack" ack) == "true"
    catch error => acknowledgmentError := some error.toString
  let elapsed := (← IO.monoMsNow)-started
  let result := Json.mkObj [("session",toJson session),("event",toJson event),("elapsedMs",toJson elapsed),
    ("receipt",toJson receipt),("complete",toJson complete),("validHookJson",toJson validJson),
    ("ackRequested",toJson (ack != Json.null)),("acknowledged",toJson acknowledged),
    ("ackError",toJson acknowledgmentError),
    ("body",toJson body),("outputSha256",toJson (Sha256.hex output.toUTF8)),
    ("decision",(parsed.getObjValD "hookSpecificOutput").getObjValD "permissionDecision")]
  save (root/(session++"-"++label++"-"++event++"-measurement.json")) result
  check (complete && elapsed < 30000) s!"ordinary hook failed or exceeded its deadline: {session}/{event}"
  check (ack == Json.null || acknowledged || body.isEmpty) "ordinary delivery-body ACK was refused"
  check (result.getObjValD "decision" != toJson "deny") "external MCP advisory denied a real tool"
  return result

def query (root : System.FilePath) (session prompt label : String) : IO Json :=
  hook root session label "UserPromptSubmit"
    ((baseInput root session "UserPromptSubmit").setObjVal! "prompt" (toJson prompt))

def tool (root : System.FilePath) (session label : String) (size : Nat) : IO (Array Json) := do
  let request := (baseInput root session "PreToolUse")
    |>.setObjVal! "tool_name" (toJson "mcp__fixture__inspect")
    |>.setObjVal! "tool_use_id" (toJson label)
    |>.setObjVal! "tool_input" (Json.mkObj [("uri",toJson (uri label)),("case",toJson label)])
  let pre ← hook root session label "PreToolUse" request
  let output ← response label size
  let post ← hook root session label "PostToolUse"
    (request.setObjVal! "hook_event_name" (toJson "PostToolUse") |>.setObjVal! "tool_response" output)
  return #[pre,post]

def finish (root : System.FilePath) (session label message : String) : IO Json :=
  hook root session label "Stop" ((baseInput root session "Stop").setObjVal! "last_assistant_message" (toJson message))

def queuesEmpty (sessions : Array String) : IO Bool := do
  for session in sessions do
    let files ← sessionFiles session
    for name in ["deferred","checkpoints"] do
      let directory := files.directory/name
      if ← directory.pathExists then
        if (← directory.readDir).any (·.fileName.endsWith ".json") then return false
  return true

def waitReady (root : System.FilePath) (project : ProjectStore.Project) (sessions : Array String)
    (label : String) : IO ProjectStore.View := do
  let started ← IO.monoMsNow
  let mut samples := #[]
  repeat
    let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
    let empty ← queuesEmpty sessions
    let mut prepared := 0
    for source in view.sources do
      if let some reference ← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract then
        if reference.population == 0 || reference.numeric.isSome then
          prepared := prepared+1
    let owners ← OwnerViews.load? view.sources
    let ownerReferenceReady := owners.isSome
    let state ← IO.ofExcept (Json.parse (← Publication.Client.control "stats"))
    samples := samples.push (Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-started)),
      ("queuesEmpty",toJson empty),("preparedSources",toJson prepared),
      ("ownerReferenceReady",toJson ownerReferenceReady),
      ("sourceHeads",toJson (view.sources.map (·.head))),
      ("preparation",state.getObjValD "preparation"),("operations",state.getObjValD "operations")])
    save (root/(label++"-drain.json")) (toJson samples)
    if empty && prepared == view.sources.size && ownerReferenceReady then return view
    check ((← IO.monoMsNow) < started+180000) "original publication/background preparation did not drain"
    IO.sleep 500
  throw (IO.userError "unreachable background wait")

def auditOriginals (root : System.FilePath) (view : ProjectStore.View) (labels : Array String)
    (size : Nat) (phase : String) : IO Unit := do
  let mut found := #[]
  for source in view.sources do
    let records ← Synapses.Provenance.records source
    let reader ← Persistence.Store.NodeReader.new source
    for record in records do
      let label := record.origin.occurrence.useId
      if !labels.contains label then continue
      check (!(found.contains label)) "one original occurrence was duplicated across physical owners"
      let document ← Synapses.Provenance.checkedDocument reader record.origin
      let count := if label.startsWith "seed-" then 512 else size
      let output ← response label count
      let event : ToolEvent := {
        name := "mcp__fixture__inspect",useId := label
        input := (Json.mkObj [("uri",toJson (uri label)),("case",toJson label)]).compress
        response := output.compress}
      check (document.source == some (canonicalJson event.response) &&
        document.workText == some (canonicalToolWork event)) s!"original Post input/output missing or changed: {label}"
      found := found.push label
  check (found.size == labels.size && labels.all found.contains) "a completed Post exists only in private ingress"
  save (root/(phase++"-originals.json")) (Json.mkObj [("found",toJson found),
    ("owners",toJson view.sources.size),("allExactInputOutput",toJson true)])

def containsEvidence (row : Json) (labels : Array String) : Bool :=
  let body := (row.getObjValAs? String "body").toOption.getD ""
  labels.all fun label => body.contains ("\""++headValue label++"\"") &&
    body.contains ("\""++tailValue label++"\"")

def auditRetained (root : System.FilePath) : IO Unit := do
  let project ← ProjectStore.openProject (root/"work.project")
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let mut found : Array String := #[]
  for source in view.sources do
    let records ← Synapses.Provenance.records source
    let reader ← Persistence.Store.NodeReader.new source
    for record in records do
      let label := record.origin.occurrence.useId
      check (label.startsWith "seed-" || label.startsWith "case-") "retained fixture contains unrelated observations"
      check (!found.contains label) "retained original occurrence is duplicated"
      let document ← Synapses.Provenance.checkedDocument reader record.origin
      let output ← response label (if label.startsWith "seed-" then 512 else 5000)
      let event : ToolEvent := {
        name := "mcp__fixture__inspect",useId := label
        input := (Json.mkObj [("uri",toJson (uri label)),("case",toJson label)]).compress
        response := output.compress }
      check (document.source == some (canonicalJson event.response) &&
        document.workText == some (canonicalToolWork event)) "retained original input/output is corrupt"
      found := found.push label
  check (found.contains "seed-alpha" && found.contains "seed-tail") "the frozen seed originals disappeared"
  let mut posts : Array String := #[]
  let mut pending : Array String := #[]
  for i in [:80] do
    if ← (root/s!"writer-{i}-case-{i}-PostToolUse.json").pathExists then posts := posts.push s!"case-{i}"
    unless ← queuesEmpty #[s!"writer-{i}"] do pending := pending.push s!"writer-{i}"
  for source in view.sources do
    check ((← DB.PageMap.pin source.directory).head == source.head) "read-only diagnosis changed an original head"
  save (root/"retained-original-audit.json") (Json.mkObj [("saved",toJson found),("posted",toJson posts),
    ("postedNotPublished",toJson (posts.filter (!found.contains ·))),("queuedSessions",toJson pending),
    ("allSavedInputOutputExact",toJson true),("seedOriginalsExact",toJson true),
    ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat))])

def parallel (root : System.FilePath) (label : String) (count : Nat) (action : Nat → IO Json) : IO (Array Json) := do
  let tasks ← (List.range count).toArray.mapM fun i => IO.asTask (action i) .dedicated
  let mut rows := #[]
  let mut errors := #[]
  for i in [:tasks.size] do
    match ← IO.wait tasks[i]! with
    | .ok row => rows := rows.push row
    | .error error => errors := errors.push (Json.mkObj [("client",toJson i),("error",toJson error.toString)])
  save (root/(label++"-results.json")) (Json.mkObj [("rows",toJson rows),("errors",toJson errors)])
  check errors.isEmpty s!"{label}: {errors.size} ordinary clients failed"
  return rows

def sampleBusy (root : System.FilePath) : IO Unit := do
  let started ← IO.monoMsNow
  for offset in [6000,16000,26000] do
    while (← IO.monoMsNow) < started+offset do
      if ← IO.checkCanceled then return
      IO.sleep 100
    if ← IO.checkCanceled then return
    let endpoint ← Daemon.loadEndpoint "seed-chat"
    let output ← IO.Process.output {
      cmd := "/usr/bin/sample"
      args := #[toString endpoint.pid,"1","1","-file",(root/s!"frontend-{offset}.sample.txt").toString]}
    save (root/s!"frontend-{offset}.sample.json") (Json.mkObj [("pid",toJson endpoint.pid),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("exitCode",toJson output.exitCode.toNat)])

def run (root : System.FilePath) (count size : Nat) (profile : Bool := false) : IO Unit := do
  check ([1,80].contains count && [5000,50000].contains size) "undeclared client or payload size"
  let some _ ← MiniLM.command (← Paths.installRoot) | throw (IO.userError "actual local MiniLM required")
  let project ← ProjectStore.create (root/"work.project") 16
  IO.FS.writeFile (root/"eggshell.toml")
    "default = \"work\"\n[eggs]\nwork = \"work.project\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n"
  try
    let _ ← query root "seed-chat" "Record the support seed alpha and tail observations." "seed"
    let _ ← tool root "seed-chat" "seed-alpha" 512
    let _ ← tool root "seed-chat" "seed-tail" 512
    let _ ← finish root "seed-chat" "seed" s!"References [{uri "seed-alpha"}]({uri "seed-alpha"}) and [{uri "seed-tail"}]({uri "seed-tail"})."
    let seeded ← waitReady root project #["seed-chat"] "seed"
    auditOriginals root seeded #["seed-alpha","seed-tail"] size "seed"
    save (root/"frozen-seed.json") (Json.mkObj [("labels",toJson #["seed-alpha","seed-tail"]),
      ("fields",toJson #["head","tail"]),("sourceHeads",toJson (seeded.sources.map (·.head)))])
    let sampler ← if profile then some <$> IO.asTask (sampleBusy root) .dedicated else pure none
    let writers ← try parallel root "writers" count fun i => do
      let session := s!"writer-{i}"
      let label := s!"case-{i}"
      let prompt ← query root session "Return the recorded support seed alpha and tail facts." "initial"
      check (containsEvidence prompt #["seed-alpha","seed-tail"]) "initial hook omitted a frozen seed original field"
      let tools ← tool root session label size
      let stopped ← finish root session label s!"Reference [{uri label}]({uri label})."
      return Json.mkObj [("client",toJson i),("prompt",prompt),("tools",toJson tools),("stop",stopped)]
      finally
        if let some sampler := sampler then
          IO.cancel sampler
          discard <| IO.wait sampler
    let sessions := #["seed-chat"]++(List.range count).toArray.map (fun i => s!"writer-{i}")
    let current ← waitReady root project sessions "writers"
    let labels := #["seed-alpha","seed-tail"]++(List.range count).toArray.map (fun i => s!"case-{i}")
    auditOriginals root current labels size "writers"
    let target := s!"case-{count-1}"
    save (root/"frozen-readback.json") (Json.mkObj [("labels",toJson #[target]),
      ("fields",toJson #["head","tail"]),("sourceHeads",toJson (current.sources.map (·.head)))])
    let readers ← parallel root "readers" count fun i => do
      let row ← query root s!"reader-{i}" s!"Return the recorded head and tail facts for support {target}." "readback"
      check (containsEvidence row #[target]) "fresh chat omitted a newly published original field"
      return row
    for source in current.sources do
      check ((← DB.PageMap.pin source.directory).head == source.head) "readback queries changed original project heads"
    save (root/"report.json") (Json.mkObj [("allPassed",toJson true),("clients",toJson count),
      ("outputBytes",toJson size),("ordinaryWriterLoops",toJson writers.size),("freshReaders",toJson readers.size),
      ("originals",toJson labels.size),("originalOwners",toJson project.manifest.owners.size),
      ("administrativeWarmCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    try Daemon.shutdown finally
      Worker.shutdown
      let _ ← Publication.Client.control "shutdown"
      pure ()

def inputDiagnostic (root : System.FilePath) (count : Nat) : IO Unit := do
  check (count == 8) "diagnostic cohort is fixed at eight readers"
  let project ← ProjectStore.create (root/"work.project") 16
  IO.FS.writeFile (root/"eggshell.toml")
    "default = \"work\"\n[eggs]\nwork = \"work.project\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n"
  try
    let _ ← query root "seed-chat" "Record the support seed alpha and tail observations." "seed"
    let _ ← tool root "seed-chat" "seed-alpha" 512
    let _ ← tool root "seed-chat" "seed-tail" 512
    let _ ← finish root "seed-chat" "seed" s!"References [{uri "seed-alpha"}]({uri "seed-alpha"}) and [{uri "seed-tail"}]({uri "seed-tail"})."
    let view ← waitReady root project #["seed-chat"] "seed"
    auditOriginals root view #["seed-alpha","seed-tail"] 512 "seed"
    let owners ← OwnerViews.load? view.sources
    save (root/"frozen-inputs.json") (Json.mkObj [("sourceHeads",toJson (view.sources.map (·.head))),
      ("ownerReferenceReady",toJson owners.isSome),("fields",toJson #["head","tail"]),
      ("labels",toJson #["seed-alpha","seed-tail"])])
    let rows ← parallel root "input-readers" count fun i => do
      let row ← query root s!"input-reader-{i}" "Return the recorded support seed alpha and tail facts." "initial"
      check (containsEvidence row #["seed-alpha","seed-tail"]) "diagnostic reader omitted a frozen field"
      return row
    for source in view.sources do
      check ((← DB.PageMap.pin source.directory).head == source.head) "read-only diagnostic changed original heads"
    save (root/"input-report.json") (Json.mkObj [("allPassed",toJson true),("readers",toJson rows.size),
      ("sourceHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
      ("serviceStats",← IO.ofExcept (Json.parse (← Publication.Client.control "stats")))])
  finally
    try Daemon.shutdown finally
      Worker.shutdown
      let _ ← Publication.Client.control "shutdown"
      pure ()

def retainedReadback (source root : System.FilePath) : IO Unit := do
  let project ← ProjectStore.openProject (source/"work.project")
  let view ← ProjectStore.pin project ((← IO.monoMsNow)+30000)
  let frozen ← IO.ofExcept (Json.parse (← IO.FS.readFile (source/"frozen-readback.json")))
  check (toJson (view.sources.map (·.head)) == frozen.getObjValD "sourceHeads") "retained readback changed the frozen cut"
  let config := root/"eggshell.toml"
  IO.FS.writeFile config ("default = \"work\"\n[eggs]\nwork = \""++(source/"work.project").toString++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  try
    let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",(← IO.appPath).toString]}
    check (identity.exitCode == 0) "cannot freeze readback runtime"
    IO.FS.writeFile (root/"runtime.sha256") identity.stdout
    let began ← IO.monoMsNow
    let warmed ← IO.Process.output {
      cmd := (← IO.appPath).toString
      args := #["egg","warm",(source/"work.project").toString]
      env := #[("EGGSHELL_CONFIG",some config.toString)] }
    IO.FS.writeFile (root/"warm-stdout.json") warmed.stdout
    IO.FS.writeFile (root/"warm-stderr.txt") warmed.stderr
    save (root/"warm-result.json") (Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-began)),
      ("exitCode",toJson warmed.exitCode.toNat)])
    check (warmed.exitCode == 0) "retained numeric preparation failed"
    for original in view.sources do
      check ((← DB.PageMap.pin original.directory).head == original.head) "warm changed frozen original heads"
      let some ready ← PreparedInputs.load? original MiniLM.model SearchProvider.encoderContract |
        throw (IO.userError "retained source input is not prepared")
      check (ready.population == 0 || ready.numeric.isSome) "retained numeric source is cold"
    check ((← OwnerViews.load? view.sources).isSome) "retained owner inputs are incomplete"
    let labels := #["seed-alpha","seed-tail"]++(List.range 80).toArray.map (fun i => s!"case-{i}")
    auditOriginals root view labels 5000 "before"
    save (root/"frozen-readback.json") frozen
    let rows ← parallel root "readers" 80 fun i => do
      let row ← query root s!"retained-reader-{i}" "Return the recorded head and tail facts for support case-79." "readback"
      check (containsEvidence row #["case-79"]) "retained reader omitted a frozen original field"
      return row
    for original in view.sources do
      check ((← DB.PageMap.pin original.directory).head == original.head) "readback changed frozen original heads"
    save (root/"report.json") (Json.mkObj [("allPassed",toJson true),("clients",toJson rows.size),
      ("administrativeWarmCalls",toJson (1 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
      ("originalHeadsUnchanged",toJson true),("adopted",toJson false)])
  finally
    try Daemon.shutdown finally
      Worker.shutdown
      let _ ← Publication.Client.control "shutdown"
      pure ()

end Eggshell.Research.FrontTrafficChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["owner-binding-synthetic",root] =>
      Eggshell.Research.OwnerBindingChecks.auditCaptured (.mk root)
      return 0
  | ["owner-binding-audit",source,root] =>
      Eggshell.Research.OwnerBindingChecks.run (.mk source) (.mk root)
      return 0
  | ["source-pin-batch",source,root] =>
      Eggshell.Research.SourcePinBatchChecks.run (.mk source) (.mk root)
      return 0
  | ["input-frame-audit",source,root] =>
      Eggshell.Research.InputFrameChecks.run (.mk source) (.mk root)
      return 0
  | ["prepared-lexical-audit",source,root] =>
      Eggshell.Research.PreparedLexicalChecks.run (.mk source) (.mk root)
      return 0
  | ["shared-startup",root] =>
      Eggshell.Research.StartupChecks.run (.mk root)
      return 0
  | ["shared-startup-client",session,deadline] =>
      let some deadline := deadline.toNat? | throw (IO.userError "startup client needs an absolute deadline")
      IO.println (← Eggshell.Research.StartupChecks.client session deadline).compress
      return 0
  | ["literal-readback",source,root] => do
      let root : System.FilePath := .mk root
      Eggshell.Research.FrontTrafficChecks.check (!(← root.pathExists)) "preserve earlier readback trial"
      IO.FS.createDirAll root
      Numerical.withDefaultKeeper (do
        Eggshell.Research.FrontTrafficChecks.retainedReadback (.mk source) root
        pure 0) 1000
  | ["literal-rank-audit",source,root] =>
      Eggshell.Research.LiteralRankChecks.audit (.mk source) (.mk root)
      return 0
  | ["front-session-policy",root] =>
      Eggshell.Research.FrontSessionChecks.policy (.mk root)
      return 0
  | ["single-search-blocking"] => Eggshell.Research.SingleSearchChecks.blocking
  | ["single-search-policy",root] =>
      Eggshell.Research.SingleSearchChecks.policy (.mk root)
      return 0
  | ["direct-numerical-components",root,parent,_] =>
      Eggshell.Research.DirectNumericalChecks.components (.mk root) parent
      return 0
  | ["direct-numerical-replay",root,parent,retained] =>
      Eggshell.Research.DirectNumericalChecks.replay (.mk root) parent (.mk retained)
      return 0
  | ["front-traffic-audit",root] => do
      Eggshell.Research.FrontTrafficChecks.auditRetained (.mk root)
      return 0
  | ["front-input-audit",root] => do
      Eggshell.Research.FrontInputAudit.run [root]
      return 0
  | ["front-input-retry",root] => do
      Eggshell.Research.FrontInputAudit.run [root,"retry"]
      return 0
  | ["front-input-recovery-checks",root] => do
      Eggshell.Research.FrontInputAudit.recoveryChecks (.mk root)
      return 0
  | ["front-input-key-checks",root] => do
      Eggshell.Research.FrontInputAudit.serviceKeyChecks (.mk root)
      return 0
  | ["front-deadline-checks",root] => do
      Eggshell.Research.TaskDeadlineChecks.run (.mk root)
      return 0
  | ["front-input-diagnostic",root,count] => do
      let some count := count.toNat? | throw (IO.userError "reader count required")
      let root := System.FilePath.mk root
      unless !(← root.pathExists) do throw (IO.userError "preserve earlier diagnostic evidence")
      IO.FS.createDir root
      Numerical.withDefaultKeeper (do
        Eggshell.Research.FrontTrafficChecks.inputDiagnostic root count
        pure 0) 1000
  | [mode,root,count,size] => do
      unless ["front-traffic","front-traffic-profile"].contains mode do return ← sourceRouteEngine args
      let some clients := count.toNat? | throw (IO.userError "client count required")
      let some bytes := size.toNat? | throw (IO.userError "byte count required")
      let root := System.FilePath.mk root
      unless !(← root.pathExists) do throw (IO.userError "preserve the earlier native trial")
      IO.FS.createDir root
      Numerical.withDefaultKeeper (do
        Eggshell.Research.FrontTrafficChecks.run root clients bytes (mode == "front-traffic-profile")
        pure 0) 1000
  | other => sourceRouteEngine other
