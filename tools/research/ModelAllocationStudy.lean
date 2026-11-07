import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace Eggshell.Research.ModelAllocationStudy

def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def assets := base/"prefix/share/eggshell/minilm"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot identify allocation input"
  return (result.stdout.splitOn " ").headD ""
def drained : IO Unit := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (!result.stdout.contains "controller/StudyMain guard ") "resource guard is still active"

/-- Same request boundaries in both arms: no batching across clients, text
rewriting, tokenizer changes, model changes or altered normalization. -/
def payload (index : Nat) : Json := Json.mkObj [("texts",toJson (#[
  s!"Independent request {index}: a cached observation retains its source identity.",
  s!"要求{index}: " ++ String.join (List.replicate 8 "非同期の要求ごとに独立した入出力を持ち原文の末尾まで確認する。"),
  s!"요청{index}: " ++ String.join (List.replicate 6 "모든 입력과 원문을 확인하고 독립적으로 처리합니다. "),
  "case_" ++ toString index ++ "() { if (ready && owner) return source[offset]; else return pending; }" ] : Array String))]
def inputs : Array Json := (Array.range 16).map payload |>.push (Json.mkObj [("texts",toJson
  ((Array.range 32).map fun index => s!"window_{index}: " ++ String.join (List.replicate 24
    "if (source[offset] && snapshot == captured) { return original_evidence; }\n")))])
def normalized (reply : Json) : Json :=
  Json.mkObj [("vectors",reply.getObjValD "vectors"),("coverage",reply.getObjValD "coverage")]

abbrev Kernel := IO.Process.Child {stdin := .piped,stdout := .piped,stderr := .inherit}
def exchange (child : Kernel) (input : Json) : IO Json := do
  child.stdin.putStrLn input.compress
  child.stdin.flush
  let reading ← IO.asTask child.stdout.getLine .dedicated
  try
    let deadline := (← IO.monoMsNow)+30000
    repeat
      if ← IO.hasFinished reading then
        let line ← IO.ofExcept (← IO.wait reading)
        check (!line.isEmpty) "encoder ended without a reply"
        let reply ← IO.ofExcept (Json.parse line)
        if let .ok error := reply.getObjValAs? String "error" then throw (IO.userError error)
        return reply
      check ((← IO.monoMsNow) < deadline) "allocation probe request timed out"
      IO.sleep 5
    throw (IO.userError "unreachable allocation probe")
  finally
    unless ← IO.hasFinished reading do child.kill
    discard <| IO.wait reading
def rss (pid : Nat) : IO Nat := do
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","rss="]}
  check (result.exitCode == 0) "encoder disappeared before memory measurement"
  let some bytes := result.stdout.trimAscii.toString.toNat? | throw (IO.userError "invalid RSS observation")
  return bytes

def one (root : System.FilePath) (kernel mode : String) (pair : Nat)
    (prepacking : Bool := false) : IO (Array Json × Json) := do
  let folder := root/s!"pair-{pair}-{mode}"
  IO.FS.createDirAll folder
  let source := folder/"kernel.txt"
  IO.FS.writeFile source kernel
  let child ← IO.Process.spawn {
    cmd := (assets/"fastembed-0.8.0/bin/python").toString
    args := #["-c",kernel,"sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
      (assets/"models").toString,"4",(folder/"model.guard").toString,"shared"],
    stdin := .piped,stdout := .piped,stderr := .inherit}
  try
    let mut replies := #[]
    let mut observations := #[]
    for index in [:inputs.size] do
      let started ← IO.monoMsNow
      let reply ← exchange child inputs[index]!
      if prepacking then
        check (reply.getObjValD "prepackingDisabled" == toJson true)
          "ONNX did not confirm that prepacking was disabled"
      let elapsed := (← IO.monoMsNow)-started
      let value := normalized reply
      let request := inputs[index]!
      let texts ← IO.ofExcept (request.getObjValAs? (Array String) "texts")
      let coverage ← IO.ofExcept ((reply.getObjValD "coverage").getArr?)
      let vectors ← IO.ofExcept ((reply.getObjValD "vectors").getArr?)
      check (coverage.size == texts.size && vectors.size == texts.size) "allocation response lost an input"
      for group in vectors do
        let group ← IO.ofExcept group.getArr?
        check (!group.isEmpty) "allocation response has an empty vector group"
        for row in group do check ((← IO.ofExcept row.getArr?).size == 384) "embedding width changed"
      let result := folder/s!"reply-{index}.json"
      write result value
      replies := replies.push value
      observations := observations.push (Json.mkObj [("request",toJson index),("elapsedMs",toJson elapsed),
        ("rssAfterReplyKiB",toJson (← rss child.pid.toNat)),("timing",reply.getObjValD "timing"),
        ("normalizedReplySha256",toJson (← hash result))])
    IO.sleep 100
    let summary := Json.mkObj [("mode",toJson mode),("pair",toJson pair),("pid",toJson child.pid.toNat),
      ("kernelSha256",toJson (← hash source)),("rssAfterIdleKiB",toJson (← rss child.pid.toNat)),
      ("observations",toJson observations),("allOriginalRequestBoundariesPreserved",toJson true)]
    write (folder/"report.json") summary
    return (replies,summary)
  finally
    if (← child.tryWait).isNone then
      child.kill
      discard <| child.wait

def prepackingKernel (kernel : String) : IO String := do
  let before := "            from fastembed import TextEmbedding\n"
  check ((kernel.splitOn before).length == 2) "prepacking must modify exactly one numerical loader"
  -- The probe changes the existing numerical boundary only. No scheduler,
  -- inference, tokenizer, pooling or normalization implementation is added.
  let after := before ++
    "            import onnxruntime as ort\n" ++
    "            original_options = ort.SessionOptions\n" ++
    "            observed_options = []\n" ++
    "            def options_without_prepacking():\n" ++
    "                options = original_options()\n" ++
    "                options.add_session_config_entry(\"session.disable_prepacking\", \"1\")\n" ++
    "                observed_options.append(options.get_session_config_entry(\"session.disable_prepacking\"))\n" ++
    "                return options\n" ++
    "            ort.SessionOptions = options_without_prepacking\n"
  let initialized := "            planner = Planner(encoder.model.tokenizer)\n"
  check ((kernel.splitOn initialized).length == 2) "prepacking needs one initialized-model check"
  let confirmed := initialized ++
    "            if observed_options != [\"1\"]:\n" ++
    "                raise ValueError(\"prepacking option was not applied exactly once\")\n"
  let boundary := "def reply(result, requested):\n"
  check ((kernel.splitOn boundary).length == 2) "prepacking needs one numerical reply boundary"
  return (kernel.replace before after |>.replace initialized confirmed).replace boundary
    (boundary ++ "    result[\"prepackingDisabled\"] = encoder is not None\n")

def runTrials (root : System.FilePath) (prepacking : Bool := false) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier allocation experiment"
  IO.FS.createDirAll root
  let original := base/(if prepacking then "keyed-discovery-source/runtime/embedding.py" else "elastic-encoder-source/runtime/embedding.py")
  let kernel ← IO.FS.readFile original
  let before := "threads=int(sys.argv[3]), local_files_only=True)"
  let after := "threads=int(sys.argv[3]), local_files_only=True, enable_cpu_mem_arena=False)"
  check ((kernel.splitOn before).length == 2) "allocation option must change exactly one initializer"
  let candidate ← if prepacking then prepackingKernel kernel else pure (kernel.replace before after)
  let changed := if prepacking then "unpacked" else "released"
  write (root/"definition.json") (Json.mkObj [("originalKernelSha256",toJson (← hash original)),
    ("onlySessionPrepackingChanged",toJson prepacking),("pairs",toJson (3 : Nat)),
    ("requestsPerArm",toJson inputs.size),("armOrder",toJson #["AB","BA","AB"])])
  write (root/"inputs.json") (toJson inputs)
  let mut pairs := #[]
  for pair in [:3] do
    let arms := if pair % 2 == 0 then [("default",kernel),(changed,candidate)]
      else [(changed,candidate),("default",kernel)]
    let mut reference : Array Json := #[]
    let mut observations := #[]
    for (mode,source) in arms do
      let (replies,report) ← one root source mode pair (prepacking && mode == changed)
      if reference.isEmpty then reference := replies
      else
        if replies != reference then
          write (root/"mismatch.json") (Json.mkObj [("pair",toJson pair),("arm",toJson mode),
            ("differentRequests",toJson ((Array.range replies.size).filter fun index =>
              replies[index]? != reference[index]?)),("allPassed",toJson false)])
          throw (IO.userError "allocation policy changed vectors or coverage")
      observations := observations.push report
    pairs := pairs.push (Json.mkObj [("pair",toJson pair),("bothArmsExact",toJson true),("arms",toJson observations)])
    write (root/"progress.json") (toJson pairs)
  write (root/"report.json") (Json.mkObj [("allPassed",toJson true),("pairs",toJson pairs),
    ("originalKernelSha256",toJson (← hash original)),("onlyInitializerArgumentChanged",toJson (!prepacking)),
    ("onlySessionPrepackingChanged",toJson prepacking),
    ("normalizedRepliesCompared",toJson (3*2*inputs.size)),("fullHookOrEightyUsers",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def run (root : System.FilePath) (prepacking : Bool := false) : IO Unit := do
  check (!(← root.pathExists)) "preserve earlier allocation experiment"
  try runTrials root prepacking
  catch error =>
    write (root/"failure.json") (Json.mkObj [("error",toJson error.toString),
      ("prepacking",toJson prepacking),("adopted",toJson false)])
    throw error

def setup (tag : String) (prepacking : Bool := false) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh allocation guard required"
  write settings (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M512","--run",
    (workspace/"tools/research/ModelAllocationStudy.lean").toString,
    (if prepacking then "run-prepacking" else "run"),(base/(tag++"-result")).toString]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def collect (tag : String) (prepacking : Bool := false) : IO Unit := do
  drained
  check (tag == (if prepacking then "model-prepacking1" else "model-allocation1")) "unknown fixed allocation experiment"
  let root := base/(tag++"-result")
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "allocation experiment has not terminated successfully"
  let report ← read (root/"report.json")
  check (report.getObjValD "allPassed" == toJson true &&
    report.getObjValD "normalizedRepliesCompared" == toJson (102 : Nat)) "retain all fixed pairs"
  check (report.getObjValD "originalKernelSha256" == toJson (← hash (base/(if prepacking then
    "keyed-discovery-source/runtime/embedding.py" else "elastic-encoder-source/runtime/embedding.py"))))
    "original numerical input changed"
  check ((← read (root/"inputs.json")) == toJson inputs) "allocation request boundary changed"
  let pairs ← IO.ofExcept ((report.getObjValD "pairs").getArr?)
  let mut retainedMemoryImproved := true
  for pair in pairs do
    let arms ← IO.ofExcept ((pair.getObjValD "arms").getArr?)
    let some standard := arms.find? (fun arm => arm.getObjValD "mode" == toJson "default") |
      throw (IO.userError "missing allocation reference")
    let some released := arms.find? (fun arm => arm.getObjValD "mode" == toJson (if prepacking then "unpacked" else "released")) |
      throw (IO.userError "missing allocation treatment")
    let before ← IO.ofExcept (standard.getObjValAs? Nat "rssAfterIdleKiB")
    let after ← IO.ofExcept (released.getObjValAs? Nat "rssAfterIdleKiB")
    retainedMemoryImproved := retainedMemoryImproved && after < before
  let destination := workspace/"docs/candidates"/(if prepacking then "model-prepacking" else "model-allocation")
  IO.FS.createDirAll destination
  let stderr := base/(tag++".stderr")
  let captured ← stderr.pathExists
  write (destination/"controls.json") (Json.mkObj [("guard",guard),("experiment",report),
    ("retainedMemoryImprovedAllPairs",toJson retainedMemoryImproved),("adopted",toJson false),
    ("fullHookOrEightyUsers",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("stderrCapturedToFile",toJson captured),
    ("controllerSha256AtCollection",toJson (← hash (workspace/"tools/research/ModelAllocationStudy.lean")))])
  write (destination/"inputs.json") (toJson inputs)
  if captured then IO.FS.writeFile (destination/"stderr.txt") (← IO.FS.readFile stderr)
def cleanup (prepacking : Bool := false) : IO Unit := do
  drained
  let destination := workspace/"docs/candidates"/(if prepacking then "model-prepacking" else "model-allocation")
  let evidence ← read (destination/"controls.json")
  let guard := evidence.getObjValD "guard"
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    (evidence.getObjValD "experiment").getObjValD "allPassed" == toJson true) "preserve completed result first"
  let root := base/((if prepacking then "model-prepacking1" else "model-allocation1")++"-result")
  let mut removed := #[]
  for pair in [:3] do
    for mode in ["default",(if prepacking then "unpacked" else "released")] do
      let folder := root/s!"pair-{pair}-{mode}"
      let report ← read (folder/"report.json")
      let source := folder/"kernel.txt"
      check (toJson (← hash source) == report.getObjValD "kernelSha256") "probe kernel changed"
      for row in (report.getObjValD "observations").getArr?.toOption.getD #[] do
        let index ← IO.ofExcept (row.getObjValAs? Nat "request")
        check (index < inputs.size) "allocation cleanup escaped fixed inputs"
        let reply := folder/s!"reply-{index}.json"
        check (toJson (← hash reply) == row.getObjValD "normalizedReplySha256") "probe reply changed"
        removed := removed.push reply
      removed := removed.push source
  write (destination/"cleanup.json") (Json.mkObj [("files",toJson (removed.map (·.toString))),
    ("completed",toJson false),("archived",toJson false)])
  for file in removed do IO.FS.removeFile file
  write (destination/"cleanup.json") (Json.mkObj [("files",toJson (removed.map (·.toString))),
    ("completed",toJson true),("archived",toJson false)])

/-- The existing numerical generator is suspended only at its ONNX call.
The batching, feeds, tokenizer, pooling and normalization bytes are retained.
ORT owns asynchronous execution; this adds no Python worker pool or scheduler. -/
def sharedKernel (kernel : String) (profile : Bool := true) : IO String := do
  let boundary := "\nfor line in sys.stdin:\n"
  check ((kernel.splitOn boundary).length == 2) "one numerical protocol boundary required"
  let loader := "            from fastembed import TextEmbedding\n"
  check ((kernel.splitOn loader).length == 2) "one numerical session loader required"
  let profiling := loader ++
    "            import onnxruntime as ort\n" ++
    "            original_options = ort.SessionOptions\n" ++
    "            def profiled_options():\n" ++
    "                options = original_options()\n" ++
    "                options.enable_profiling = True\n" ++
    "                options.profile_file_prefix = sys.argv[6]\n" ++
    "                return options\n" ++
    "            ort.SessionOptions = profiled_options\n"
  let original := ((kernel.splitOn "def encode_groups(")[1]!.splitOn "\n\ndef contract(")[0]!
  let call := "        output = numerical.model.run(numerical.ONNX_OUTPUT_NAMES, feeds)[0]\n"
  check ((original.splitOn call).length == 2) "one synchronous ONNX call required"
  let generator := "def encode_async(" ++ original.replace call
    "        output = (yield (numerical.ONNX_OUTPUT_NAMES, feeds))[0]\n"
  return ((kernel.splitOn boundary)[0]!.replace loader (if profile then profiling else loader)) ++ "\n\n" ++ generator ++ r#"

import os
import onnxruntime as ort

active_requests = {}

def emit_async(value):
    # BufferedWriter serializes each whole frame; no inference spans this IO.
    frame = (json.dumps(value, allow_nan=False, separators=(",", ":")) + "\n").encode()
    sys.stdout.buffer.write(frame)
    sys.stdout.buffer.flush()

def finish_async(state, value):
    active_requests.pop(state["id"], None)
    value.update(id=state["id"], pid=os.getpid(), nativeCalls=state["calls"],
                 submittedNs=state["submitted"], finishedNs=time.perf_counter_ns())
    emit_async(value)

def advance_async(state, output=None, first=False):
    try:
        names, feeds = next(state["generator"]) if first else state["generator"].send(output)
        state["calls"] += 1
        encoder.model.model.run_async(names, feeds, completed_async, state, state["options"])
    except StopIteration as done:
        groups, coverage = done.value
        finish_async(state, dict(vectors=[[row.tolist() for row in group] for group in groups], coverage=coverage))
    except Exception as error:
        finish_async(state, dict(error=str(error)))

def completed_async(outputs, state, error):
    if error:
        finish_async(state, dict(error=error))
    else:
        advance_async(state, outputs)

for line in sys.stdin:
    request = json.loads(line)
    operation = request["operation"]
    if operation == "ready":
        model()
        emit_async(dict(ready=True, pid=os.getpid(), sessions=1))
    elif operation == "start":
        identity = request["id"]
        if identity in active_requests:
            raise ValueError("duplicate active numerical request")
        options = ort.RunOptions()
        state = dict(id=identity, options=options, submitted=time.perf_counter_ns(), calls=0,
                     generator=encode_async(encoder, request["texts"], planner))
        active_requests[identity] = state
        advance_async(state, first=True)
    elif operation == "cancel":
        state = active_requests.get(request["id"])
        if state is not None:
            state["options"].terminate = True
        emit_async(dict(operation="cancel", id=request["id"], found=state is not None))
    elif operation == "profile":
        if active_requests:
            raise ValueError("profile requested before numerical completion")
        emit_async(dict(profile=encoder.model.model.end_profiling(), sessions=1, pid=os.getpid()))
    else:
        raise ValueError("unknown numerical probe operation")
"#

def receive (child : Kernel) (allowError : Bool := false) : IO Json := do
  let task ← IO.asTask child.stdout.getLine .dedicated
  try
    let deadline := (← IO.monoMsNow)+30000
    repeat
      if ← IO.hasFinished task then
        let line ← IO.ofExcept (← IO.wait task)
        check (!line.isEmpty) "shared model closed before its response"
        let value ← IO.ofExcept (Json.parse line)
        if !allowError then
          if let .ok error := value.getObjValAs? String "error" then throw (IO.userError error)
        return value
      check ((← IO.monoMsNow) < deadline) "shared numerical response expired"
      IO.sleep 5
    throw (IO.userError "unreachable shared numerical response")
  finally
    unless ← IO.hasFinished task do child.kill
    discard <| IO.wait task

def sharedWave (child : Kernel) (expected : Array Json) (root : System.FilePath) (wave : Nat) : IO Json := do
  let mut next := 0
  let mut pending : Array Nat := #[]
  let mut rows := #[]
  let started ← IO.monoMsNow
  while rows.size < inputs.size do
    while next < inputs.size && pending.size < 2 do
      let identity := wave*inputs.size+next
      child.stdin.putStrLn (Json.mkObj [("operation",toJson "start"),("id",toJson identity),
        ("texts",inputs[next]!.getObjValD "texts")]).compress
      child.stdin.flush
      pending := pending.push identity
      next := next+1
    let reply ← receive child
    let identity ← IO.ofExcept (reply.getObjValAs? Nat "id")
    check (pending.contains identity && wave*inputs.size ≤ identity && identity < (wave+1)*inputs.size)
      "shared numerical response belongs to another request"
    pending := pending.filter (· != identity)
    let index := identity-wave*inputs.size
    check (normalized reply == expected[index]!) "shared session changed exact vectors or coverage"
    let path := root/s!"shared-wave-{wave}-reply-{index}.json"
    write path (normalized reply)
    rows := rows.push (Json.mkObj [("request",toJson index),("identity",toJson identity),
      ("pid",reply.getObjValD "pid"),("nativeCalls",reply.getObjValD "nativeCalls"),
      ("submittedNs",reply.getObjValD "submittedNs"),("finishedNs",reply.getObjValD "finishedNs"),
      ("normalizedReplySha256",toJson (← hash path)),("exactVectorsAndCoverage",toJson true)])
  check (pending.isEmpty) "shared wave left a live request"
  let value := Json.mkObj [("wave",toJson wave),("rows",toJson rows),
    ("wallMs",toJson ((← IO.monoMsNow)-started)),("rssAfterReplyKiB",toJson (← rss child.pid.toNat))]
  write (root/s!"shared-wave-{wave}.json") value
  return value

def sharedSession (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "preserve previous shared-model probe"
  IO.FS.createDirAll root
  let original := base/"keyed-discovery-source/runtime/embedding.py"
  let kernel ← IO.FS.readFile original
  let candidate ← sharedKernel kernel
  IO.FS.writeFile (root/"shared-kernel.txt") candidate
  write (root/"inputs.json") (toJson inputs)
  let spawn := fun (body : String) (name : String) => IO.Process.spawn {
    cmd := (assets/"fastembed-0.8.0/bin/python").toString,
    args := #["-c",body,"sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
      (assets/"models").toString,"4",(root/(name++".guard")).toString,"shared",(root/"ort-profile").toString],
    stdin := .piped,stdout := .piped,stderr := .inherit}
  let stop := fun (child : Kernel) => do
    if (← child.tryWait).isNone then child.kill; discard <| child.wait
  let prior := base/"shared-model1-result"
  let reuse := root == base/"shared-model2-result"
  let (expected,reference) ← if reuse then do
      let stopped ← read (base/"shared-model1.guard.json")
      check (stopped.getObjValD "state" == toJson "finished" &&
        stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous numerical owner has not stopped"
      check ((← read (prior/"inputs.json")) == toJson inputs) "saved reference inputs changed"
      let previous ← IO.FS.readFile (prior/"shared-kernel.txt")
      check (previous.replace "        options.run_tag = str(identity)\n" "" == candidate)
        "saved reference came from another numerical implementation"
      let reference ← read (prior/"reference.json")
      let rows ← IO.ofExcept (reference.getObjValAs? (Array Json) "observations")
      check (rows.size == inputs.size) "saved reference is incomplete"
      let replies ← (Array.range inputs.size).mapM fun index => do
        let path := prior/s!"reference-reply-{index}.json"
        check (rows[index]!.getObjValD "request" == toJson index &&
          rows[index]!.getObjValD "normalizedReplySha256" == toJson (← hash path)) "saved reference changed"
        read path
      pure (replies,reference)
    else do
      let first ← spawn kernel "reference-0"
      let second ← spawn kernel "reference-1"
      try
        let mut replies := #[]
        let mut observations := #[]
        for index in [:inputs.size] do
          let child := if index%2 == 0 then first else second
          let reply ← exchange child inputs[index]!
          let path := root/s!"reference-reply-{index}.json"
          write path (normalized reply)
          replies := replies.push (normalized reply)
          observations := observations.push (Json.mkObj [("request",toJson index),
            ("normalizedReplySha256",toJson (← hash path)),("timing",reply.getObjValD "timing")])
        let value := Json.mkObj [("pids",toJson #[first.pid.toNat,second.pid.toNat]),
          ("rssTogetherKiB",toJson ((← rss first.pid.toNat)+(← rss second.pid.toNat))),
          ("observations",toJson observations)]
        write (root/"reference.json") value
        pure (replies,value)
      finally stop first; stop second
  let child ← spawn candidate "shared"
  try
    let ready ← exchange child (Json.mkObj [("operation",toJson "ready")])
    check (ready.getObjValD "sessions" == toJson (1 : Nat) && ready.getObjValD "pid" == toJson child.pid.toNat)
      "shared probe did not load exactly one session in its owned process"
    let a ← sharedWave child expected root 0
    let b ← sharedWave child expected root 1
    let profile ← exchange child (Json.mkObj [("operation",toJson "profile")])
    let file ← IO.ofExcept (profile.getObjValAs? String "profile")
    check (file.startsWith (root/"ort-profile").toString && file.endsWith ".json") "ORT profile escaped its owned root"
    let events ← IO.ofExcept ((← read (.mk file)).getArr?)
    let runs := events.filter fun event => event.getObjValD "name" == toJson "model_run"
    let intervals ← runs.mapM fun event => do
      let start ← IO.ofExcept (event.getObjValAs? Nat "ts")
      let duration ← IO.ofExcept (event.getObjValAs? Nat "dur")
      return (start,start+duration)
    let mut overlaps := 0
    for left in [:intervals.size] do
      for right in [left+1:intervals.size] do
        if intervals[left]!.1 < intervals[right]!.2 && intervals[right]!.1 < intervals[left]!.2 then
          overlaps := overlaps+1
    let result := Json.mkObj [("allRepliesExact",toJson true),("reference",reference),
      ("waves",toJson #[a,b]),("runtimePid",toJson child.pid.toNat),("modelSessions",toJson (1 : Nat)),
      ("nativeRuns",toJson runs.size),("nativeOverlappingRunPairs",toJson overlaps),
      ("profilePath",toJson file),("profileSha256",toJson (← hash (.mk file))),
      ("originalKernelSha256",toJson (← hash original)),("sharedKernelSha256",toJson (← hash (root/"shared-kernel.txt"))),
      ("normalizedReplies",toJson (inputs.size*3)),("sourceModelTokenizerPoolingUntouched",toJson true),
      ("referenceRoot",toJson (if reuse then prior else root).toString),("referenceReused",toJson reuse),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
    write (root/"report.json") result
    check (overlaps > 0) "ORT native inference intervals never overlapped"
  finally stop child

def setupShared (tag : String) : IO Unit := do
  drained
  check (["shared-model1","shared-model2","shared-model-cancel1"].contains tag) "fixed shared-model probe required"
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "preserve earlier shared-model guard"
  write settings (Json.mkObj [("command",toJson #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (workspace/"tools/research/ModelAllocationStudy.lean").toString,
    (if tag == "shared-model-cancel1" then "run-shared-cancel" else "run-shared"),(base/(tag++"-result")).toString]),
    ("cwd",toJson workspace.toString),("record",toJson (base/(tag++".guard.json")).toString),
    ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def cancelShared (root : System.FilePath) : IO Unit := do
  check (root == base/"shared-model-cancel1-result" && !(← root.pathExists)) "fresh fixed cancellation probe required"
  let guard ← read (base/"shared-model2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "successful shared numerical probe required"
  let previous ← read (base/"shared-model2-result/report.json")
  let original := base/"keyed-discovery-source/runtime/embedding.py"
  check (previous.getObjValD "originalKernelSha256" == toJson (← hash original)) "shared source changed before cancellation"
  let kernel ← sharedKernel (← IO.FS.readFile original)
  IO.FS.createDirAll root
  IO.FS.writeFile (root/"shared-kernel.txt") kernel
  check (previous.getObjValD "sharedKernelSha256" == toJson (← hash (root/"shared-kernel.txt")))
    "cancellation probe differs from successful numerical kernel"
  let reference := base/"shared-model1-result/reference-reply-0.json"
  let rows ← IO.ofExcept ((previous.getObjValD "reference").getObjValAs? (Array Json) "observations")
  check (rows[0]!.getObjValD "normalizedReplySha256" == toJson (← hash reference)) "cancellation reference changed"
  let expected ← read reference
  let child ← IO.Process.spawn {
    cmd := (assets/"fastembed-0.8.0/bin/python").toString,
    args := #["-c",kernel,"sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2",
      (assets/"models").toString,"4",(root/"model.guard").toString,"shared",(root/"ort-profile").toString],
    stdin := .piped,stdout := .piped,stderr := .inherit}
  try
    let ready ← exchange child (Json.mkObj [("operation",toJson "ready")])
    check (ready.getObjValD "pid" == toJson child.pid.toNat) "foreign shared cancellation model"
    for (identity,index) in [(100,inputs.size-1),(101,0)] do
      child.stdin.putStrLn (Json.mkObj [("operation",toJson "start"),("id",toJson identity),
        ("texts",inputs[index]!.getObjValD "texts")]).compress
      child.stdin.flush
    child.stdin.putStrLn (Json.mkObj [("operation",toJson "cancel"),("id",toJson (100 : Nat))]).compress
    child.stdin.flush
    let mut observed := #[]
    let mut acknowledged := false
    let mut cancelled := false
    let mut survivor := false
    for _ in [:3] do
      let reply ← receive child true
      let identity ← IO.ofExcept (reply.getObjValAs? Nat "id")
      if reply.getObjValD "operation" == toJson "cancel" then
        check (identity == 100 && reply.getObjValD "found" == toJson true && !acknowledged)
          "cancellation missed or repeated its active numerical request"
        acknowledged := true
      else if identity == 100 then
        let error ← IO.ofExcept (reply.getObjValAs? String "error")
        check (error.contains "terminate" && !cancelled) "cancelled numerical run did not terminate independently"
        cancelled := true
      else if identity == 101 then
        check (normalized reply == expected && !survivor) "cancellation damaged the other numerical request"
        survivor := true
      else throw (IO.userError "foreign numerical cancellation response")
      observed := observed.push (Json.mkObj [("identity",toJson identity),
        ("operation",reply.getObjValD "operation"),("error",reply.getObjValD "error"),
        ("found",reply.getObjValD "found"),("pid",reply.getObjValD "pid")])
    check (acknowledged && cancelled && survivor) "incomplete shared cancellation receipt"
    let after ← exchange child (Json.mkObj [("operation",toJson "start"),("id",toJson (102 : Nat)),
      ("texts",inputs[0]!.getObjValD "texts")])
    check (after.getObjValD "id" == toJson (102 : Nat) && normalized after == expected &&
      after.getObjValD "pid" == toJson child.pid.toNat) "shared model did not survive individual cancellation"
    let profile ← exchange child (Json.mkObj [("operation",toJson "profile")])
    let file ← IO.ofExcept (profile.getObjValAs? String "profile")
    check (file.startsWith (root/"ort-profile").toString && file.endsWith ".json") "cancellation profile escaped owned scope"
    write (root/"report.json") (Json.mkObj [("allPassed",toJson true),("observed",toJson observed),
      ("sameProcessSurvived",toJson true),("survivorAndFollowingResponseExact",toJson true),
      ("modelSessions",toJson (1 : Nat)),("pid",toJson child.pid.toNat),
      ("rssAfterReplyKiB",toJson (← rss child.pid.toNat)),("profilePath",toJson file),
      ("profileSha256",toJson (← hash (.mk file))),("kernelSha256",toJson (← hash (root/"shared-kernel.txt"))),
      ("referenceReplySha256",toJson (← hash reference)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    if (← child.tryWait).isNone then child.kill; discard <| child.wait

def collectShared : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/shared-model"
  IO.FS.createDirAll destination
  let first ← read (base/"shared-model1.guard.json")
  let fixed ← read (base/"shared-model2.guard.json")
  let cancelled ← read (base/"shared-model-cancel1.guard.json")
  for guard in [first,fixed,cancelled] do
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "shared probe owner is not terminal"
  check (first.getObjValD "exitCode" != toJson (0 : Nat) && fixed.getObjValD "exitCode" == toJson (0 : Nat) &&
    cancelled.getObjValD "exitCode" == toJson (0 : Nat)) "preserve both the initial failure and corrected component results"
  let root := base/"shared-model2-result"
  let result ← read (root/"report.json")
  let cancellation ← read (base/"shared-model-cancel1-result/report.json")
  check (result.getObjValD "originalKernelSha256" == toJson (← hash (base/"keyed-discovery-source/runtime/embedding.py")) &&
    result.getObjValD "sharedKernelSha256" == toJson (← hash (root/"shared-kernel.txt")) &&
    cancellation.getObjValD "kernelSha256" == result.getObjValD "sharedKernelSha256") "shared numerical source changed"
  check (result.getObjValD "allRepliesExact" == toJson true &&
    result.getObjValD "normalizedReplies" == toJson (inputs.size*3) &&
    cancellation.getObjValD "allPassed" == toJson true) "shared vector and cancellation gate required"
  let profile ← IO.ofExcept (result.getObjValAs? String "profilePath")
  check (profile.startsWith (root/"ort-profile").toString &&
    result.getObjValD "profileSha256" == toJson (← hash (.mk profile))) "shared native profile changed"
  let events ← IO.ofExcept ((← read (.mk profile)).getArr?)
  let runs := events.filter fun event => event.getObjValD "name" == toJson "model_run"
  let intervals ← runs.mapM fun event => do
    let start ← IO.ofExcept (event.getObjValAs? Nat "ts")
    let duration ← IO.ofExcept (event.getObjValAs? Nat "dur")
    return (start,start+duration)
  let mut overlaps := 0
  for left in [:intervals.size] do
    for right in [left+1:intervals.size] do
      if intervals[left]!.1 < intervals[right]!.2 && intervals[right]!.1 < intervals[left]!.2 then
        overlaps := overlaps+1
  check (overlaps > 0 && result.getObjValD "nativeRuns" == toJson intervals.size &&
    result.getObjValD "nativeOverlappingRunPairs" == toJson overlaps) "shared native overlap is not reproducible"
  let original ← IO.FS.readFile (base/"shared-model1-result/shared-kernel.txt")
  check (original.replace "        options.run_tag = str(identity)\n" "" == (← IO.FS.readFile (root/"shared-kernel.txt")))
    "initial failure changed more than its optional log attribute"
  write (destination/"controls.json") (Json.mkObj [("experiment",result),("cancellation",cancellation),
    ("initialGuard",first),("guard",fixed),("cancellationGuard",cancelled),
    ("nativeRunIntervalsUs",toJson intervals),("fullHooksOrEightyUsers",toJson false),
    ("initialInvalidLogAttributeRemoved",toJson true),("controllerSha256AtCollection",toJson (← hash
      (workspace/"tools/research/ModelAllocationStudy.lean"))),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  write (destination/"inputs.json") (toJson inputs)
  for name in ["shared-model1","shared-model2","shared-model-cancel1"] do
    IO.FS.writeFile (destination/(name++"-stderr.txt")) (← IO.FS.readFile (base/(name++".stderr")))

def cleanupShared : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/shared-model"
  let evidence ← read (destination/"controls.json")
  for name in ["initialGuard","guard","cancellationGuard"] do
    let guard := evidence.getObjValD name
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "shared cleanup owner is still active"
  let report := evidence.getObjValD "experiment"
  let first := base/"shared-model1-result"
  let second := base/"shared-model2-result"
  let cancellation := base/"shared-model-cancel1-result"
  let mut paths : Array System.FilePath := #[]
  for row in ((report.getObjValD "reference").getObjValD "observations").getArr?.toOption.getD #[] do
    let index ← IO.ofExcept (row.getObjValAs? Nat "request")
    check (index < inputs.size) "shared cleanup reference escaped fixed request domain"
    let path := first/s!"reference-reply-{index}.json"
    check (row.getObjValD "normalizedReplySha256" == toJson (← hash path)) "shared cleanup reference changed"
    paths := paths.push path
  for wave in (report.getObjValD "waves").getArr?.toOption.getD #[] do
    let ordinal ← IO.ofExcept (wave.getObjValAs? Nat "wave")
    check (ordinal < 2) "shared cleanup wave escaped fixed experiment"
    for row in (wave.getObjValD "rows").getArr?.toOption.getD #[] do
      let index ← IO.ofExcept (row.getObjValAs? Nat "request")
      check (index < inputs.size) "shared cleanup response escaped fixed request domain"
      let path := second/s!"shared-wave-{ordinal}-reply-{index}.json"
      check (row.getObjValD "normalizedReplySha256" == toJson (← hash path)) "shared cleanup response changed"
      paths := paths.push path
  for (root,digest) in [(second,report.getObjValD "sharedKernelSha256"),
    (cancellation,(evidence.getObjValD "cancellation").getObjValD "kernelSha256")] do
    let path := root/"shared-kernel.txt"
    check (digest == toJson (← hash path)) "shared cleanup kernel changed"
    paths := paths.push path
  paths := paths.push (first/"shared-kernel.txt")
  for (root,summary) in [(second,report),(cancellation,evidence.getObjValD "cancellation")] do
    let name ← IO.ofExcept (summary.getObjValAs? String "profilePath")
    check (name.startsWith (root/"ort-profile").toString && name.endsWith ".json" &&
      summary.getObjValD "profileSha256" == toJson (← hash (.mk name))) "shared cleanup profile changed"
    paths := paths.push (.mk name)
  let mut records := #[]
  for path in paths do records := records.push (Json.mkObj [("path",toJson path.toString),
    ("bytes",toJson (← path.metadata).byteSize.toNat),("sha256",toJson (← hash path))])
  let record := Json.mkObj [("removed",toJson records),("archived",toJson false),
    ("originalsAndProjectCacheRetained",toJson true),("completed",toJson false)]
  write (destination/"cleanup.json") record
  for path in paths do IO.FS.removeFile path
  write (destination/"cleanup.json") (record.setObjVal! "completed" (toJson true))

def writeSharedKernel (destination : System.FilePath) : IO Unit := do
  drained
  check (destination == base/"shared-transport-source/runtime/shared_embedding.py" ||
    destination == base/"shared-model-source/runtime/shared_embedding.py") "shared numerical kernel escaped its isolated source"
  check (!(← destination.pathExists)) "preserve existing isolated numerical source"
  let result := (← read (workspace/"docs/candidates/shared-model/controls.json")).getObjValD "experiment"
  let original := base/"keyed-discovery-source/runtime/embedding.py"
  check (result.getObjValD "originalKernelSha256" == toJson (← hash original)) "checked numerical source changed"
  let kernel ← IO.FS.readFile original
  let checked := base/"shared-kernel-source-check.txt"
  check (!(← checked.pathExists)) "preserve earlier source check"
  try
    IO.FS.writeFile checked (← sharedKernel kernel)
    check (result.getObjValD "sharedKernelSha256" == toJson (← hash checked)) "checked asynchronous numerical implementation changed"
  finally if ← checked.pathExists then IO.FS.removeFile checked
  IO.FS.createDirAll destination.parent.get!
  IO.FS.writeFile destination (← sharedKernel kernel false)

def prepareTransport : IO Unit := do
  drained
  let source := base/"shared-transport-source"
  check (!(← source.pathExists)) "fresh isolated shared transport source required"
  let command ← IO.Process.output {cmd := (compiler/"bin/lean").toString,args := #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"keyed-discovery-build").toString,source.toString,(base/"shared-transport-build").toString,
    "tools.research.SharedEncoderMain",(base/"shared-transport-settings.json").toString],cwd := some workspace}
  check (command.exitCode == 0) (command.stdout++command.stderr)
  for name in ["SharedEncoder","SharedEncoderControls"] do
    IO.FS.writeFile (source/"tools/research"/(name++".lean"))
      (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))
  writeSharedKernel (source/"runtime/shared_embedding.py")

def refreshTransport (tag : String := "shared-transport-build1") : IO Unit := do
  drained
  check (tag.startsWith "shared-transport-build") "known shared transport build required"
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "state" == toJson "finished" &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "transport build has not drained"
  let destination := workspace/"docs/candidates/shared-model"/(tag++".json")
  check (!(← destination.pathExists)) "preserve previous transport build audit"
  let modules ← #["SharedEncoder","SharedEncoderControls"].mapM fun name => do
    let source := base/"shared-transport-source/tools/research"/(name++".lean")
    let output := base/"shared-transport-build"/("tools_research_"++name++"-lean.stdout")
    let diagnostics ← if ← output.pathExists then pure (toJson (← IO.FS.readFile output)) else pure Json.null
    return Json.mkObj [("module",toJson name),("sourceSha256",toJson (← hash source)),
      ("diagnostics",diagnostics)]
  write destination (Json.mkObj [("guard",guard),("modules",toJson modules)])
  for name in ["SharedEncoder","SharedEncoderControls"] do
    IO.FS.writeFile (base/"shared-transport-source/tools/research"/(name++".lean"))
      (← IO.FS.readFile (workspace/"tools/research"/(name++".lean")))

def setupTransport (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh shared transport guard required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
        (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"shared-transport-settings.json").toString]
    | "controls" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"shared-transport-build/StudyMain").toString,
        (base/(tag++"-result")).toString]
    | _ => throw (IO.userError "build or controls required")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def collectTransport : IO Unit := do
  drained
  let guard ← read (base/"shared-transport-controls1.guard.json")
  let build ← read (base/"shared-transport-build7.guard.json")
  for value in [guard,build] do
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "exitCode" == toJson (0 : Nat) &&
      value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native shared transport has not passed and drained"
  let root := base/"shared-transport-controls1-result"
  let report ← read (root/"report.json")
  let shutdown ← read (root/"shutdown.json")
  check (report.getObjValD "allPassed" == toJson true && report.getObjValD "parallelRepliesExact" == toJson (34 : Nat) &&
    shutdown.getObjValD "closed" == toJson true && shutdown.getObjValD "readerJoined" == toJson true &&
    shutdown.getObjValD "pending" == toJson (0 : Nat)) "native shared transport closure incomplete"
  let sources ← #["SharedEncoder","SharedEncoderControls"].mapM fun name => do
    let witness : String × Array (String × String) ← IO.ofExcept (fromJson? (← read
      (base/"shared-transport-build"/("tools_research_"++name++".source"))))
    check (witness.1 == (← IO.FS.readFile (workspace/"tools/research"/(name++".lean"))))
      "native transport source differs from its checked Lean implementation"
    for (path,contents) in witness.2 do
      let actual := (base/"shared-transport-source/tools/research"/path).normalize
      check (actual.toString.startsWith (base/"shared-transport-source").toString &&
        (← IO.FS.readFile actual) == contents) "transport literal source changed"
    return Json.mkObj [("module",toJson name),("sourceSha256",toJson (← hash
      (workspace/"tools/research"/(name++".lean"))))]
  let destination := workspace/"docs/candidates/shared-model"
  write (destination/"transport-controls.json") (Json.mkObj [("guard",guard),("buildGuard",build),
    ("report",report),("shutdown",shutdown),("sources",toJson sources),
    ("runtimeSha256",toJson (← hash (base/"shared-transport-build/StudyMain"))),
    ("componentOnly",toJson true),("allProductCorePresent",toJson false),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  IO.FS.writeFile (destination/"transport-controls-stderr.txt") (← IO.FS.readFile (base/"shared-transport-controls1.stderr"))

def retireSuperseded : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/shared-model/retired-parent-executables.json"
  check (!(← destination.pathExists)) "preserve previous executable retirement"
  let current ← read (workspace/"docs/candidates/keyed-discovery/auditor-sources.json")
  check (current.getObjValD "allProductCorePresent" == toJson true &&
    current.getObjValD "commonSourcesUnchanged" == toJson true &&
    current.getObjValD "productSha256" == toJson (← hash (base/"keyed-discovery-build/StudyMain")) &&
    current.getObjValD "auditorSha256" == toJson (← hash (base/"keyed-discovery-auditor-build/StudyMain")))
    "preserve current coherent product and auditor"
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (process.exitCode == 0) "cannot inspect executable ownership"
  let mut files := #[]
  for family in ["elastic-encoder","keyed-inputs"] do
    let source ← read (workspace/"docs/candidates"/family/"auditor-sources.json")
    check (source.getObjValD "commonSourcesUnchanged" == toJson true &&
      source.getObjValD "allProductCorePresent" == toJson true) "old executable provenance is incomplete"
    for (relative,digest) in [(family++"-build/StudyMain",source.getObjValD "productSha256"),
      (family++"-prefix/libexec/eggshell",source.getObjValD "productSha256"),
      (family++"-auditor-build/StudyMain",source.getObjValD "auditorSha256")] do
      let path := base/relative
      if !(← path.pathExists) then continue
      check (!process.stdout.contains path.toString && digest == toJson (← hash path))
        "superseded executable is running or differs from its native provenance"
      files := files.push (Json.mkObj [("path",toJson path.toString),("sha256",digest),
        ("bytes",toJson (← path.metadata).byteSize.toNat)])
  let record := Json.mkObj [("removed",toJson files),("archived",toJson false),("completed",toJson false),
    ("baselineCurrentProductModelsOriginalsObjectsInterfacesAndSourceWitnessesRetained",toJson true)]
  write destination record
  for file in files do IO.FS.removeFile (.mk (← IO.ofExcept (file.getObjValAs? String "path")))
  write destination (record.setObjVal! "completed" (toJson true))

def retireKeyedParent : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/shared-model/retired-keyed-executables.json"
  check (!(← destination.pathExists)) "preserve previous executable retirement"
  let current ← read (workspace/"docs/candidates/shared-model/auditor-sources.json")
  check (current.getObjValD "allProductCorePresent" == toJson true &&
    current.getObjValD "commonSourcesUnchanged" == toJson true &&
    current.getObjValD "productSha256" == toJson (← hash (base/"shared-model-build/StudyMain")) &&
    current.getObjValD "auditorSha256" == toJson (← hash (base/"shared-model-auditor-build/StudyMain")))
    "retain the coherent current product and auditor"
  let capacity ← read (workspace/"docs/candidates/shared-model/capacity-80.json")
  let guard := capacity.getObjValD "guard"
  check (guard.getObjValD "state" == toJson "finished" &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
    (capacity.getObjValD "input").getObjValD "runtimeSha256" == current.getObjValD "productSha256")
    "retain the current runtime's terminal capacity evidence"
  for name in ["frontendShutdown","publisherShutdown"] do
    let stopped := capacity.getObjValD name
    check (stopped.getObjValD "processExited" == toJson true && stopped.getObjValD "daemonExitCode" == toJson (0 : Nat))
      "capacity service has not exited"
  let old ← read (workspace/"docs/candidates/keyed-discovery/auditor-sources.json")
  let client ← read (workspace/"docs/candidates/keyed-discovery/capacity-sources.json")
  for record in [old,client] do
    check (record.getObjValD "allProductCorePresent" == toJson true &&
      record.getObjValD "commonSourcesUnchanged" == toJson true) "old native provenance is incomplete"
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (process.exitCode == 0) "cannot inspect executable ownership"
  let mut files := #[]
  for (relative,digest) in [("keyed-discovery-build/StudyMain",old.getObjValD "productSha256"),
    ("keyed-discovery-prefix/libexec/eggshell",old.getObjValD "productSha256"),
    ("keyed-discovery-auditor-build/StudyMain",old.getObjValD "auditorSha256"),
    ("keyed-discovery-capacity-build/StudyMain",client.getObjValD "auditorSha256")] do
    let path := base/relative
    check ((← path.pathExists) && !process.stdout.contains path.toString && digest == toJson (← hash path))
      "ended parent executable is active, absent or differs from native provenance"
    files := files.push (Json.mkObj [("path",toJson path.toString),("sha256",digest),
      ("bytes",toJson (← path.metadata).byteSize.toNat)])
  let baseline := base/"delivery-ledger-build/StudyMain"
  check ((← hash baseline) == "d4349b126ae979c3a48e407a5fc1e98d7ac97796f97eb50c81e9fe472960385d")
    "retain the fixed adoption baseline"
  let record := Json.mkObj [("removed",toJson files),("archived",toJson false),("completed",toJson false),
    ("baselineCurrentRuntimeModelsOriginalsObjectsInterfacesAndSourceWitnessesRetained",toJson true)]
  write destination record
  for file in files do IO.FS.removeFile (.mk (← IO.ofExcept (file.getObjValAs? String "path")))
  write destination (record.setObjVal! "completed" (toJson true))
def main (args : List String) : IO Unit := match args with
  | ["setup",tag] => setup tag
  | ["run",root] => run (.mk root)
  | ["collect",tag] => collect tag
  | ["cleanup"] => cleanup
  | ["setup-prepacking",tag] => setup tag true
  | ["run-prepacking",root] => run (.mk root) true
  | ["collect-prepacking",tag] => collect tag true
  | ["cleanup-prepacking"] => cleanup true
  | ["setup-shared",tag] => setupShared tag
  | ["run-shared",root] => sharedSession (.mk root)
  | ["run-shared-cancel",root] => cancelShared (.mk root)
  | ["collect-shared"] => collectShared
  | ["cleanup-shared"] => cleanupShared
  | ["write-shared-kernel",path] => writeSharedKernel (.mk path)
  | ["prepare-transport"] => prepareTransport
  | ["refresh-transport"] => refreshTransport
  | ["refresh-transport",tag] => refreshTransport tag
  | ["setup-transport",action,tag] => setupTransport action tag
  | ["collect-transport"] => collectTransport
  | ["retire-superseded"] => retireSuperseded
  | ["retire-keyed-parent"] => retireKeyedParent
  | _ => throw (IO.userError "setup TAG | run OUTPUT")
end Eggshell.Research.ModelAllocationStudy
def main := Eggshell.Research.ModelAllocationStudy.main
