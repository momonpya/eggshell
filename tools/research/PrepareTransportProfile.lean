import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("transport profile anchor changed: " ++ toString (before.take 100))
  return source.replace before after
private def save (path : System.FilePath) (text : String) : IO Unit := do
  if ← path.pathExists then IO.FS.removeFile path
  IO.FS.writeFile path text
private def editFunction (source start finish : String) (patches : List (String × String)) : IO String := do
  let [before,tail] := source.splitOn start | throw (IO.userError "profile function start changed")
  let [body,after] := tail.splitOn finish | throw (IO.userError "profile function end changed")
  let mut body := body
  for (old,new) in patches do body ← once body old new
  return before ++ start ++ body ++ finish ++ after

private def clientRecord (kind : String) : String :=
  "  clientProfile \"" ++ kind ++ "\" profileStarted profileReceived profileDecoded response\n"

def main (args : List String) : IO Unit := do
  let [mode] := args | throw (IO.userError "runtime/hooks required")
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/transport-profile"
  let core := root / "transport-profile-core"
  let runtime := root / "transport-profile-runtime-build"
  let toolchain := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
  IO.FS.createDirAll records
  if mode == "runtime" then
    check (!(← core.pathExists)) "preserve transport profile candidate"
    let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-cR",(root / "selection-frames-core").toString,core.toString]}
    check (copied.exitCode == 0) "cannot isolate transport profiling"
    let stream := core / "Eggshell/PublicationStream.lean"
    let mut source ← IO.FS.readFile stream
    source ← once source "public import Eggshell.Blake3\n" "public import Eggshell.Blake3\npublic import Eggshell.Receipt\n"
    source ← once source "def receiveWith (frame : IO ByteArray) : IO String := do\n"
      ("def profile (stage : String) (fields : List (String × Json)) : IO Unit := do\n" ++
       "  if (← IO.getEnv \"EGGSHELL_TRACE_SERVICE_PROFILE\") == some \"1\" then\n" ++
       "    Receipt.observe (some (← Receipt.fresh)) stage (Json.mkObj fields)\n\n" ++
       "def receiveWith (frame : IO ByteArray) (kind : String := \"unclassified\") : IO String := do\n" ++
       "  let profileStarted ← IO.monoMsNow\n")
    source ← once source "  let mut bytes := ByteArray.emptyWithCapacity size\n"
      "  let profileHeader ← IO.monoMsNow\n  let mut bytes := ByteArray.emptyWithCapacity size\n"
    source ← once source "  unless Blake3.hex (Blake3.hash bytes) == digest do throw (IO.userError \"source stream digest mismatch\")\n"
      "  let profileReceived ← IO.monoMsNow\n  unless Blake3.hex (Blake3.hash bytes) == digest do throw (IO.userError \"source stream digest mismatch\")\n  let profileVerified ← IO.monoMsNow\n"
    source ← once source "  return result\n"
      ("  let profileFinished ← IO.monoMsNow\n" ++
       "  profile \"stream-receive-profile\" [(\"kind\",toJson kind),(\"bytes\",toJson size),\n" ++
       "    (\"startedMs\",toJson profileStarted),(\"finishedMs\",toJson profileFinished),\n" ++
       "    (\"headerMs\",toJson (profileHeader-profileStarted)),(\"payloadMs\",toJson (profileReceived-profileHeader)),\n" ++
       "    (\"verifyMs\",toJson (profileVerified-profileReceived)),(\"utf8Ms\",toJson (profileFinished-profileVerified))]\n" ++
       "  return result\n")
    source ← once source "def receive (client : Socket.Client) (deadline : Nat) : IO String :=\n  receiveWith (Daemon.receiveFrameBefore client deadline)\n"
      "def receive (client : Socket.Client) (deadline : Nat) (kind : String := \"unclassified\") : IO String :=\n  receiveWith (Daemon.receiveFrameBefore client deadline) kind\n"
    source ← once source "  let deadline := (← IO.monoMsNow)+budget\n  let client ← Daemon.connect endpoint\n  Daemon.sendFrame client (Daemon.request endpoint.secret kind payload).compress.toUTF8\n  receive client deadline\n"
      ("  let profileStarted ← IO.monoMsNow\n  let deadline := profileStarted+budget\n" ++
       "  let client ← Daemon.connect endpoint\n  let profileConnected ← IO.monoMsNow\n" ++
       "  let encoded ← (← IO.mkRef (Daemon.request endpoint.secret kind payload).compress.toUTF8).get\n" ++
       "  let profileEncoded ← IO.monoMsNow\n  Daemon.sendFrame client encoded\n  let profileSent ← IO.monoMsNow\n" ++
       "  let response ← receive client deadline kind\n  let profileFinished ← IO.monoMsNow\n" ++
       "  profile \"stream-exchange-profile\" [(\"kind\",toJson kind),(\"requestBytes\",toJson encoded.size),\n" ++
       "    (\"responseBytes\",toJson response.utf8ByteSize),(\"startedMs\",toJson profileStarted),(\"finishedMs\",toJson profileFinished),\n" ++
       "    (\"connectMs\",toJson (profileConnected-profileStarted)),(\"encodeMs\",toJson (profileEncoded-profileConnected)),\n" ++
       "    (\"sendMs\",toJson (profileSent-profileEncoded)),(\"receiveMs\",toJson (profileFinished-profileSent))]\n  return response\n")
    save stream source
    let client := core / "Eggshell/PublicationClient.lean"
    source ← IO.FS.readFile client
    source ← once source "namespace Eggshell.Plugin.Publication.Client\nopen Lean DB\n"
      ("namespace Eggshell.Plugin.Publication.Client\nopen Lean DB\n\n" ++
       "def clientProfile (kind : String) (started received decoded : Nat) (response : String) : IO Unit := do\n" ++
       "  let finished ← IO.monoMsNow\n" ++
       "  Stream.profile \"client-profile\" [(\"kind\",toJson kind),(\"startedMs\",toJson started),\n" ++
       "    (\"finishedMs\",toJson finished),(\"responseBytes\",toJson response.utf8ByteSize),\n" ++
       "    (\"requestAndExchangeMs\",toJson (received-started)),(\"decodeMs\",toJson (decoded-received)),\n" ++
       "    (\"validationMs\",toJson (finished-decoded))]\n")
    for (start,finish,decodedAnchor,returnAnchor,kind) in [
      ("\ndef sourcePalettes ","\ndef SourceBatch.release ","  unless palette.identities", "  return ⟨first.1.endpoint,requests,palette⟩", "source-palettes"),
      ("\ndef SourceBatch.select ","\ndef SourceBatch.fetch ","  unless result.getObjValD", "  return result.getObjValD \"choice\"", "source-plan"),
      ("\ndef SourceBatch.fetch ","\ndef endpoint? ","  unless result.identities", "  IO.ofExcept (Synapses.CanonicalSource.Delivery.merge rows)", "source-fetch-many"),
      ("\ndef sourceBindings ","\ndef sourceRecords ","  unless found.identity", "  return {\n    rows", "source-bindings"),
      ("\ndef sourceRecords ","\ndef ready ","  unless result.source", "  return result", "source-records")] do
      let tail := if kind == "source-fetch-many" then
        "  let merged ← IO.ofExcept (Synapses.CanonicalSource.Delivery.merge rows)\n" ++ clientRecord kind ++ "  return merged"
        else clientRecord kind ++ returnAnchor
      source ← editFunction source start finish [
        (":= do\n",":= do\n  let profileStarted ← IO.monoMsNow\n"),
        ("]) budget\n","]) budget\n  let profileReceived ← IO.monoMsNow\n"),
        (decodedAnchor,"  let profileDecoded ← IO.monoMsNow\n" ++ decodedAnchor),
        (returnAnchor,tail)]
    save client source
    let service := core / "Eggshell/PublicationService.lean"
    source ← IO.FS.readFile service
    source ← once source "  let reserved ← IO.mkRef (0 : Nat)\n" "  let profileStarted ← IO.monoMsNow\n  let reserved ← IO.mkRef (0 : Nat)\n"
    source ← once source "    let json ← IO.ofExcept (Json.parse text)\n" "    let profileReceived ← IO.monoMsNow\n    let json ← IO.ofExcept (Json.parse text)\n"
    source ← once source "    let kind ← IO.ofExcept (json.getObjValAs? String \"kind\")\n"
      "    let kind ← IO.ofExcept (json.getObjValAs? String \"kind\")\n    let profileDecoded ← IO.monoMsNow\n"
    source ← once source "    let value ← if kind == \"refresh-source\"" "    let profileDispatch ← IO.monoMsNow\n    let value ← if kind == \"refresh-source\""
    source ← once source "    pure (.ok value.compress : Except String String)\n"
      ("    let encoded ← (← IO.mkRef value.compress).get\n    let profileEncoded ← IO.monoMsNow\n" ++
       "    if streamedRead then\n" ++
       "      profile \"server-envelope-profile\" [(\"kind\",toJson kind),(\"requestBytes\",toJson size),\n" ++
       "        (\"responseBytes\",toJson encoded.utf8ByteSize),(\"startedMs\",toJson profileStarted),(\"finishedMs\",toJson profileEncoded),\n" ++
       "        (\"receiveMs\",toJson (profileReceived-profileStarted)),(\"decodeMs\",toJson (profileDecoded-profileReceived)),\n" ++
       "        (\"admitMs\",toJson (profileDispatch-profileDecoded)),(\"dispatchAndEncodeMs\",toJson (profileEncoded-profileDispatch))]\n" ++
       "    pure (.ok encoded : Except String String)\n")
    save service source
    let handoff := core / "Eggshell/Handoff.lean"
    source ← IO.FS.readFile handoff
    source ← editFunction source "\ndef PreparedRendering.usingService " "\ndef prepareAutomatic " [
      ("  | .plan pending =>\n","  | .plan pending =>\n    let profileStarted ← IO.monoMsNow\n"),
      ("    let selectedJson ← batch.select (toJson query) deadline\n","    let queryJson ← (← IO.mkRef (toJson query)).get\n    let profileQuery ← IO.monoMsNow\n    let selectedJson ← batch.select queryJson deadline\n    let profileSelected ← IO.monoMsNow\n"),
      ("    let selected := Std.HashSet.ofArray choice.sourceKeys\n","    let profileDecoded ← IO.monoMsNow\n    let selected := Std.HashSet.ofArray choice.sourceKeys\n"),
      ("    let rows ← if choice.sourceKeys.isEmpty","    let profileRequests ← IO.monoMsNow\n    let rows ← if choice.sourceKeys.isEmpty"),
      ("    unless rows.map (·.key)","    let profileFetched ← IO.monoMsNow\n    let profileSourceKeys := choice.sourceKeys.size\n    unless rows.map (·.key)"),
      ("    return pending.finish (some choice)\n",
       "    let profileMaterialized ← IO.monoMsNow\n" ++
       "    let finished ← (← IO.mkRef (pending.finish (some choice))).get\n    let profileFinished ← IO.monoMsNow\n" ++
       "    Publication.Stream.profile \"render-client-profile\" [(\"startedMs\",toJson profileStarted),(\"finishedMs\",toJson profileFinished),\n" ++
       "      (\"queryMs\",toJson (profileQuery-profileStarted)),(\"selectMs\",toJson (profileSelected-profileQuery)),\n" ++
       "      (\"choiceDecodeMs\",toJson (profileDecoded-profileSelected)),(\"fetchRequestMs\",toJson (profileRequests-profileDecoded)),\n" ++
       "      (\"fetchMs\",toJson (profileFetched-profileRequests)),(\"materializeMs\",toJson (profileMaterialized-profileFetched)),\n" ++
       "      (\"finishMs\",toJson (profileFinished-profileMaterialized)),(\"sourceKeys\",toJson profileSourceKeys)]\n    return finished\n")]
    source ← once source "    let rendering := prepareAutomatic staged selection.handoffChars current delivered enforce stagedVisible discovery\n"
      "    let profileAutomaticStarted ← IO.monoMsNow\n    let rendering := prepareAutomatic staged selection.handoffChars current delivered enforce stagedVisible discovery\n"
    source ← once source "    let rendered ← try rendering.usingService synaptic.batch advisoryDeadline\n"
      "    let rendering ← (← IO.mkRef rendering).get\n    let profileAutomaticReady ← IO.monoMsNow\n    let rendered ← try rendering.usingService synaptic.batch advisoryDeadline\n"
    source ← once source "    let rendered := rendered.map fun handoff => {handoff with synapticComplete := synaptic.complete}\n"
      ("    let profileRendered ← IO.monoMsNow\n    Publication.Stream.profile \"render-automatic-profile\" [(\"startedMs\",toJson profileAutomaticStarted),\n" ++
       "      (\"finishedMs\",toJson profileRendered),(\"prepareMs\",toJson (profileAutomaticReady-profileAutomaticStarted)),\n" ++
       "      (\"serviceAndFinishMs\",toJson (profileRendered-profileAutomaticReady))]\n" ++
       "    let rendered := rendered.map fun handoff => {handoff with synapticComplete := synaptic.complete}\n")
    save handoff source
    IO.FS.writeFile (records / "plan.json") (Json.mkObj [
      ("purpose",toJson "Attribute the unclassified hook time without changing nomination, scores, selection, source, authority or delivery prompt."),
      ("schedule",toJson "Reuse the sole prepared R40 DB/private histories. Seal runtime/helper, activate and recheck warm, then one normal new-session topic-1 hook. Stop on a parent-body mismatch, incomplete hook or resource guard."),
      ("parentRuntimeSha256",toJson "ce2459c4a77afe1ef41c2103fc9a328c22d5cea5b88e93061975a6483848b8c5"),
      ("profile",toJson "Only fixed API kinds, bytes, counts and monotonic timestamps. Inclusive nested intervals must not be summed as independent CPU. No raw query, source text, capability or token is written."),
      ("limits",toJson "Unchanged 30-second hook limit, 3.5GiB RSS stop and 2GiB free-space floor. No answering-model calls or new seed."),
      ("adopted",toJson false)]).pretty
  else if mode == "hooks" then
    let target := core / "tools/research/TransportProfileHook.lean"
    check (!(← target.pathExists)) "preserve transport hook helper"
    let mut source ← IO.FS.readFile (root / "selection-frames-core/tools/research/SelectionFramesHook.lean")
    source := source.replace "selection-frames" "transport-profile"
    source ← once source "docs/candidates/selection-witness/frames/hooks" "docs/candidates/transport-profile/hooks"
    source ← once source "private def armPath (arm : String) : System.FilePath := study / \"shared-snapshot/transport-profile-trial\" / arm\n"
      "private def armPath (arm : String) : System.FilePath := study / \"shared-snapshot/selection-frames-trial\" / arm\n"
    source ← once source "  if mode == \"prepare\" then\n"
      ("  if mode == \"activate\" then\n" ++
       "    check (rest.isEmpty && !(← (saved / \"ready.json\").pathExists)) \"preserve activated profile\"\n" ++
       "    check ((← StudyRuntime.files database) == originalFiles) \"shared prepared source changed\"\n" ++
       "    let copied ← IO.Process.output {cmd := \"/bin/cp\",args := #[\"-c\",(runtimePath arm).toString,binary.toString]}\n" ++
       "    check (copied.exitCode == 0 && (← ArtifactHash.hex binary) == expected.sha256) \"cannot activate fixed profile runtime\"\n" ++
       "    let publisher ← StudyRuntime.startPublisher binary (root / \"data\") (environment arm true) (expectedRuntime := some expected)\n" ++
       "    try\n" ++
       "      let warmed ← StudyCommand.run binary.toString #[\"egg\",\"warm\",\"work\"] (environment arm true) workspace \"\" (saved / \"warm\") 240000\n" ++
       "      check (warmed.exitCode == 0) \"transport profile warm recheck failed\"\n" ++
       "    finally StudyRuntime.stopManaged publisher (saved / \"activate-shutdown.json\")\n" ++
       "    check ((← StudyRuntime.files database) == originalFiles) \"activation changed original source\"\n" ++
       "    IO.FS.writeFile (saved / \"ready.json\") (Json.mkObj [(\"sourceFiles\",toJson originalFiles),(\"runtime\",toJson expected)]).pretty\n    return\n" ++
       "  if mode == \"prepare\" then\n")
    source ← once source "for stage in [\"source-plan-profile\",\"source-bindings-profile\"]"
      "for stage in [\"source-plan-profile\",\"source-bindings-profile\",\"server-envelope-profile\",\"client-profile\",\"stream-exchange-profile\",\"stream-receive-profile\",\"render-client-profile\",\"render-automatic-profile\"]"
    save target source
  else throw (IO.userError "unknown transport profile action")
  let baseline := if mode == "runtime" then root / "selection-frames-runtime-build" else runtime
  let output := if mode == "runtime" then runtime else root / "transport-profile-hook-candidate-build"
  let settings := root / s!"transport-profile-{mode}.settings.json"
  IO.FS.writeFile settings (Json.mkObj [
    ("project",toJson core.toString),("core",toJson core.toString),("output",toJson output.toString),
    ("baselineCore",toJson (root / "query-cache-baseline-core").toString),("toolchain",toJson toolchain),
    ("baselineResponse",toJson (baseline / "runtime.rsp").toString),("baselineMain",toJson (baseline / "Main.o").toString),
    ("objectModules",toJson (baseline / "object-mapping.json").toString),("parents",toJson #[baseline.toString]),
    ("force",toJson (#[] : Array String)),("mainModule",toJson (if mode == "runtime" then "Main" else "tools.research.TransportProfileHook"))]).compress
  let mut jobs := [(mode ++ "-build",#["/usr/bin/env","LEAN_NUM_THREADS=1",toolchain ++ "/bin/lean","-M1024","--run",
    (project / "tools/research/StudyBuildMain.lean").toString,settings.toString])]
  if mode == "hooks" then jobs := jobs ++ [("describe",#[(output / "StudyMain").toString,"describe","candidate"]),
    ("activate",#[(output / "StudyMain").toString,"activate","candidate"]),
    ("normal-1",#[(output / "StudyMain").toString,"run","candidate","0","1"])]
  for (label,command) in jobs do
    IO.FS.writeFile (root / s!"transport-profile-{label}.guard.settings.json") (Json.mkObj [
      ("cwd",toJson core.toString),("ownedPrefixes",toJson #[root.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (records / (label ++ ".guard.json")).toString),("command",toJson command)]).compress
